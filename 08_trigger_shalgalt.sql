BEGIN;
SET LOCAL search_path TO dental_clinic, public;

CREATE FUNCTION guard_appointment_slot() RETURNS trigger
LANGUAGE plpgsql
SET search_path TO dental_clinic, pg_temp
AS $function$
BEGIN
    IF NOT isfinite(NEW.slot_start)
       OR extract(minute FROM NEW.slot_start) NOT IN (0, 30)
       OR date_trunc('minute', NEW.slot_start) <> NEW.slot_start THEN
        RAISE EXCEPTION 'Цаг минутын 00 эсвэл 30 дээр эхлэх ёстой: %', NEW.slot_start
            USING ERRCODE = '23514';
    END IF;

    PERFORM 1
    FROM work_slot
    WHERE dentist_id = NEW.dentist_id AND slot_start = NEW.slot_start
    FOR KEY SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Эмч % энэ цагт ажлын хуваарьгүй: %', NEW.dentist_id, NEW.slot_start
            USING ERRCODE = '23503';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER appointment_slot_guard
    BEFORE INSERT OR UPDATE OF dentist_id, slot_start ON appointment
    FOR EACH ROW EXECUTE FUNCTION guard_appointment_slot();

CREATE FUNCTION protect_price_history() RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION 'Тарифын түүхийг өөрчлөхгүй. Шинэ хүчинтэй өдрөөр хувилбар нэмнэ'
        USING ERRCODE = '55000';
END;
$function$;

CREATE TRIGGER price_history_guard
    BEFORE UPDATE OR DELETE ON service_price
    FOR EACH ROW EXECUTE FUNCTION protect_price_history();

COMMIT;

BEGIN;
SET LOCAL search_path TO dental_clinic, public;

DO $check$
DECLARE
    v_booked integer;
    v_completed integer;
    v_line integer;
    v_constraint text;
    v_fee_day date;
    v_count integer;
BEGIN
    SELECT min(visit_no) INTO STRICT v_completed
    FROM appointment WHERE patient_id = 1 AND status = 'completed';
    IF v_completed IS NULL THEN
        RAISE EXCEPTION 'Seed-ийн patient_id = 1 дээр дууссан үзлэг алга';
    END IF;

    v_booked := book_appointment(
        24, 1, timestamp '2027-01-20 14:00', 16, timestamp '2027-01-19 14:00'
    );
    IF NOT EXISTS (
        SELECT 1 FROM v_booked_appointments WHERE patient_id = 24 AND visit_no = v_booked
    ) THEN
        RAISE EXCEPTION 'Зөв захиалга идэвхтэй view-д харагдсангүй';
    END IF;
    RAISE NOTICE 'OK: хуваарьтай слотыг захиалав';

    BEGIN
        PERFORM book_appointment(2, 1, timestamp '2027-01-20 14:15', 17, timestamp '2027-01-19');
        RAISE EXCEPTION '15 минутын цагийг хүлээж авлаа';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK 23514: %', SQLERRM;
    END;

    BEGIN
        PERFORM book_appointment(2, 1, timestamp '2027-01-20 14:30', 17, timestamp '2027-01-19');
        RAISE EXCEPTION 'Хуваарьгүй цагийг хүлээж авлаа';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK 23503: %', SQLERRM;
    END;

    BEGIN
        PERFORM book_appointment(2, 1, timestamp '2027-01-20 14:00', 17, timestamp '2027-01-19');
        RAISE EXCEPTION 'Эмчийн давхар захиалгыг хүлээж авлаа';
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint <> 'appointment_dentist_slot_unique' THEN
            RAISE;
        END IF;
        RAISE NOTICE 'OK 23505: %', SQLERRM;
    END;

    v_line := record_treatment(1, v_completed, 4, ARRAY[16,16]::smallint[],
                               ARRAY['M','O']::tooth_surface[], 'Дүрмийн туршилт');
    SELECT count(*) INTO v_count
    FROM v_treatment_chart WHERE patient_id = 1 AND visit_no = v_completed AND line_no = v_line;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Хоёр гадаргууг тус бүрд бүртгэсэнгүй';
    END IF;
    RAISE NOTICE 'OK: 16M, 16O хоёр гадаргууг нэг эмчилгээний мөртэй холбов';

    INSERT INTO tooth (patient_id, fdi) VALUES (24, 18);
    BEGIN
        PERFORM record_treatment(1, v_completed, 4, ARRAY[18]::smallint[],
                                 ARRAY['M']::tooth_surface[]);
        RAISE EXCEPTION 'Өөр хүний шүдийг эмчилгээнд холболоо';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint <> 'surface_patient_tooth_fk' THEN
            RAISE;
        END IF;
        RAISE NOTICE 'OK 23503: %', SQLERRM;
    END;

    BEGIN
        PERFORM record_treatment(1, v_completed, 4, ARRAY[11]::smallint[],
                                 ARRAY['O']::tooth_surface[]);
        RAISE EXCEPTION '11 шүдний O гадаргууг хүлээж авлаа';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint <> 'surface_matches_tooth' THEN
            RAISE;
        END IF;
        RAISE NOTICE 'OK 23514: %', SQLERRM;
    END;

    SELECT price_from INTO STRICT v_fee_day
    FROM treatment WHERE patient_id = 1 AND visit_no = v_completed AND line_no = v_line;
    BEGIN
        INSERT INTO treatment (
            patient_id, visit_no, line_no, service_id, price_from, primary_fdi, primary_surface
        ) VALUES (1, v_completed, v_line + 1, 4, v_fee_day, 16, 'M');
        SET CONSTRAINTS treatment_requires_primary_surface IMMEDIATE;
        RAISE EXCEPTION 'Гадаргуугүй эмчилгээг зөвшөөрлөө';
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint <> 'treatment_requires_primary_surface' THEN
            RAISE;
        END IF;
        RAISE NOTICE 'OK 23503: %', SQLERRM;
    END;

    BEGIN
        UPDATE v_booked_appointments SET status = 'cancelled'
        WHERE patient_id = 24 AND visit_no = v_booked;
        RAISE EXCEPTION 'View төлөвийн шүүлтээ зөрчлөө';
    EXCEPTION WHEN with_check_option_violation THEN
        RAISE NOTICE 'OK 44000: %', SQLERRM;
    END;

    BEGIN
        UPDATE service_price SET fee = fee + 1 WHERE service_id = 4 AND valid_from = v_fee_day;
        RAISE EXCEPTION 'Тарифын түүхийг өөрчилж боллоо';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        RAISE NOTICE 'OK 55000: %', SQLERRM;
    END;

    UPDATE appointment SET status = 'cancelled'
    WHERE patient_id = 24 AND visit_no = v_booked;
    PERFORM book_appointment(2, 1, timestamp '2027-01-20 14:00', 17, timestamp '2027-01-19');
    RAISE NOTICE 'OK: цуцалсан цагийг дахин захиаллаа';
END;
$check$;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
