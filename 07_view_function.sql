BEGIN;
SET LOCAL search_path TO dental_clinic, public;

CREATE VIEW v_booked_appointments AS
SELECT patient_id, visit_no, dentist_id, slot_start, booked_by, booked_at, status
FROM appointment
WHERE status = 'booked'
WITH LOCAL CHECK OPTION;

CREATE VIEW v_treatment_chart AS
SELECT x.patient_id, x.visit_no, x.line_no, a.slot_start, x.fdi, x.surface,
       s.service_code, s.service_name,
       (x.fdi = t.primary_fdi AND x.surface = t.primary_surface) AS is_primary,
       t.note
FROM treatment_surface AS x
JOIN treatment AS t USING (patient_id, visit_no, line_no)
JOIN appointment AS a USING (patient_id, visit_no)
JOIN service AS s ON s.service_id = t.service_id;

CREATE VIEW v_visit_balance AS
WITH billed AS (
    SELECT t.patient_id, t.visit_no, sum(p.fee) AS billed_mnt
    FROM treatment AS t
    JOIN service_price AS p ON p.service_id = t.service_id AND p.valid_from = t.price_from
    GROUP BY t.patient_id, t.visit_no
), collected AS (
    SELECT patient_id, visit_no, sum(amount) AS paid_mnt
    FROM payment
    GROUP BY patient_id, visit_no
)
SELECT a.patient_id, a.visit_no, a.slot_start, a.status,
       coalesce(b.billed_mnt, 0) AS billed_mnt, coalesce(c.paid_mnt, 0) AS paid_mnt,
       coalesce(b.billed_mnt, 0) - coalesce(c.paid_mnt, 0) AS balance_mnt
FROM appointment AS a
LEFT JOIN billed AS b USING (patient_id, visit_no)
LEFT JOIN collected AS c USING (patient_id, visit_no);

CREATE FUNCTION book_appointment(
    p_patient_id integer,
    p_dentist_id integer,
    p_slot_start timestamp without time zone,
    p_receptionist_id integer,
    p_booked_at timestamp without time zone DEFAULT LOCALTIMESTAMP
) RETURNS integer
LANGUAGE plpgsql
SET search_path TO dental_clinic, pg_temp
AS $function$
DECLARE
    v_visit_no integer;
BEGIN
    PERFORM 1 FROM patient WHERE patient_id = p_patient_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Үйлчлүүлэгчийн код олдсонгүй: %', p_patient_id
            USING ERRCODE = '23503';
    END IF;

    SELECT coalesce(max(visit_no), 0) + 1 INTO v_visit_no
    FROM appointment WHERE patient_id = p_patient_id;

    INSERT INTO appointment (patient_id, visit_no, dentist_id, slot_start, booked_by, booked_at)
    VALUES (p_patient_id, v_visit_no, p_dentist_id, p_slot_start, p_receptionist_id, p_booked_at);

    RETURN v_visit_no;
END;
$function$;

CREATE FUNCTION record_treatment(
    p_patient_id integer,
    p_visit_no integer,
    p_service_id integer,
    p_fdi smallint[],
    p_surfaces tooth_surface[],
    p_note text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SET search_path TO dental_clinic, pg_temp
AS $function$
DECLARE
    v_visit_date date;
    v_price_from date;
    v_line_no integer;
    v_primary_fdi smallint;
    v_primary_surface tooth_surface;
BEGIN
    IF p_fdi IS NULL OR p_surfaces IS NULL OR cardinality(p_fdi) = 0
       OR cardinality(p_fdi) <> cardinality(p_surfaces)
       OR array_ndims(p_fdi) <> 1 OR array_ndims(p_surfaces) <> 1 THEN
        RAISE EXCEPTION 'Шүд, гадаргууны хос жагсаалт ижил урттай, хоосонгүй байх ёстой'
            USING ERRCODE = '22023';
    END IF;

    SELECT slot_start::date INTO v_visit_date
    FROM appointment
    WHERE patient_id = p_patient_id AND visit_no = p_visit_no AND status = 'completed'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Дууссан үзлэг олдсонгүй'
            USING ERRCODE = '23503';
    END IF;

    SELECT valid_from INTO v_price_from
    FROM service_price
    WHERE service_id = p_service_id AND valid_from <= v_visit_date
    ORDER BY valid_from DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Үзлэгийн өдөрт хүчинтэй тариф олдсонгүй'
            USING ERRCODE = '23503';
    END IF;

    SELECT coalesce(max(line_no), 0) + 1 INTO v_line_no
    FROM treatment WHERE patient_id = p_patient_id AND visit_no = p_visit_no;

    SELECT pair.fdi, pair.surface INTO v_primary_fdi, v_primary_surface
    FROM unnest(p_fdi, p_surfaces) WITH ORDINALITY AS pair(fdi, surface, pair_no)
    WHERE pair.pair_no = 1;

    INSERT INTO treatment (patient_id, visit_no, line_no, service_id, price_from,
                           primary_fdi, primary_surface, note)
    VALUES (p_patient_id, p_visit_no, v_line_no, p_service_id, v_price_from,
            v_primary_fdi, v_primary_surface, p_note);

    INSERT INTO treatment_surface (patient_id, visit_no, line_no, fdi, surface)
    SELECT p_patient_id, p_visit_no, v_line_no, pair.fdi, pair.surface
    FROM unnest(p_fdi, p_surfaces) AS pair(fdi, surface);

    RETURN v_line_no;
END;
$function$;

SELECT 'view' AS kind, table_name AS object_name
FROM information_schema.views
WHERE table_schema = 'dental_clinic'
  AND table_name IN ('v_booked_appointments', 'v_treatment_chart', 'v_visit_balance')
UNION ALL
SELECT 'function', routine_name
FROM information_schema.routines
WHERE routine_schema = 'dental_clinic'
  AND routine_name IN ('book_appointment', 'record_treatment')
ORDER BY kind, object_name;

COMMIT;
