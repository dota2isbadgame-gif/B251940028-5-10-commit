BEGIN READ ONLY;
SET LOCAL search_path TO dental_clinic, public;
SELECT w.dentist_id, w.slot_start
FROM work_slot AS w
WHERE w.dentist_id = 1
  AND w.slot_start >= timestamp '2026-09-17'
  AND w.slot_start < timestamp '2026-09-18'
EXCEPT
SELECT a.dentist_id, a.slot_start
FROM appointment AS a
WHERE a.dentist_id = 1
  AND a.slot_start >= timestamp '2026-09-17'
  AND a.slot_start < timestamp '2026-09-18'
  AND a.status <> 'cancelled'
ORDER BY dentist_id, slot_start;

SELECT a.patient_id, a.visit_no, p.last_name, p.first_name,
       a.dentist_id, a.slot_start, a.status
FROM appointment AS a
JOIN patient AS p ON p.patient_id = a.patient_id
WHERE a.slot_start >= timestamp '2026-09-17'
  AND a.slot_start < timestamp '2026-09-18'
  AND a.status <> 'cancelled'
ORDER BY a.slot_start, a.dentist_id, a.patient_id, a.visit_no;

SELECT a.slot_start, x.visit_no, x.line_no, x.fdi, x.surface, s.service_name
FROM treatment_surface AS x
JOIN treatment AS t USING (patient_id, visit_no, line_no)
JOIN appointment AS a USING (patient_id, visit_no)
JOIN service AS s ON s.service_id = t.service_id
WHERE x.patient_id = 1
ORDER BY a.slot_start, x.visit_no, x.line_no, x.fdi, x.surface;

SELECT paid_at::date AS paid_day, count(*) AS payment_count, sum(amount) AS revenue_mnt
FROM payment
WHERE paid_at >= timestamp '2026-09-01' AND paid_at < timestamp '2026-10-01'
GROUP BY paid_at::date
ORDER BY paid_day;

WITH billed AS (
    SELECT t.patient_id, t.visit_no, sum(pr.fee) AS billed_mnt
    FROM treatment AS t
    JOIN service_price AS pr ON pr.service_id = t.service_id AND pr.valid_from = t.price_from
    GROUP BY t.patient_id, t.visit_no
), collected AS (
    SELECT patient_id, visit_no, sum(amount) AS paid_mnt
    FROM payment
    GROUP BY patient_id, visit_no
)
SELECT a.patient_id, a.visit_no, a.slot_start,
       coalesce(b.billed_mnt, 0) AS billed_mnt, coalesce(c.paid_mnt, 0) AS paid_mnt,
       coalesce(b.billed_mnt, 0) - coalesce(c.paid_mnt, 0) AS balance_mnt
FROM appointment AS a
LEFT JOIN billed AS b USING (patient_id, visit_no)
LEFT JOIN collected AS c USING (patient_id, visit_no)
WHERE a.status = 'completed'
  AND a.slot_start >= timestamp '2026-09-01' AND a.slot_start < timestamp '2026-10-01'
  AND coalesce(b.billed_mnt, 0) > coalesce(c.paid_mnt, 0)
ORDER BY balance_mnt DESC, a.patient_id, a.visit_no;

SELECT a.dentist_id, s.last_name, s.first_name, count(*) AS completed_visits
FROM appointment AS a
JOIN staff AS s ON s.staff_id = a.dentist_id
WHERE a.status = 'completed'
  AND a.slot_start >= timestamp '2026-09-01' AND a.slot_start < timestamp '2026-10-01'
GROUP BY a.dentist_id, s.last_name, s.first_name
HAVING count(*) > 25
ORDER BY completed_visits DESC, a.dentist_id;

SELECT p.patient_id, p.last_name, p.first_name
FROM patient AS p
WHERE NOT EXISTS (
    SELECT 1 FROM appointment AS a WHERE a.patient_id = p.patient_id
)
ORDER BY p.patient_id;

SELECT p.patient_id, p.last_name, p.first_name
FROM patient AS p
WHERE EXISTS (
    SELECT 1 FROM treatment AS t WHERE t.patient_id = p.patient_id
)
AND NOT EXISTS (
    SELECT 1
    FROM service AS s
    WHERE s.service_code IN ('SR04', 'SR05')
      AND NOT EXISTS (
          SELECT 1
          FROM treatment AS t
          WHERE t.patient_id = p.patient_id AND t.service_id = s.service_id
      )
)
ORDER BY p.patient_id;

SELECT s.service_code, s.service_name, count(*) AS treatment_lines
FROM treatment AS t
JOIN appointment AS a USING (patient_id, visit_no)
JOIN service AS s ON s.service_id = t.service_id
WHERE a.slot_start >= timestamp '2026-09-01' AND a.slot_start < timestamp '2026-10-01'
GROUP BY s.service_code, s.service_name
HAVING count(*) >= 40
ORDER BY treatment_lines DESC, s.service_code;

SELECT fdi, surface, count(*) AS entries
FROM treatment_surface
GROUP BY fdi, surface
HAVING count(*) >= 10
ORDER BY entries DESC, fdi, surface;

COMMIT;

BEGIN;
SET LOCAL search_path TO pg_temp, dental_clinic, public;

CREATE TEMP TABLE work_slot (dentist_id integer, slot_start timestamp);
CREATE TEMP TABLE patient (patient_id integer, last_name text, first_name text);
CREATE TEMP TABLE appointment (
    patient_id integer, visit_no integer, dentist_id integer, slot_start timestamp, status text
);
INSERT INTO work_slot VALUES
    (1, timestamp '2026-09-17 09:00'), (1, timestamp '2026-09-17 09:30');
INSERT INTO patient VALUES (1, 'Бат', 'Ану'), (2, 'Дорж', 'Билгүүн');
INSERT INTO appointment VALUES
    (1, 1, 1, timestamp '2026-09-17 09:00', 'booked'),
    (1, 2, 1, timestamp '2026-09-17 09:30', 'cancelled');

CREATE TEMP VIEW q01 AS
SELECT w.dentist_id, w.slot_start FROM work_slot AS w
WHERE w.dentist_id = 1 AND w.slot_start >= timestamp '2026-09-17'
  AND w.slot_start < timestamp '2026-09-18'
EXCEPT
SELECT a.dentist_id, a.slot_start FROM appointment AS a
WHERE a.dentist_id = 1 AND a.slot_start >= timestamp '2026-09-17'
  AND a.slot_start < timestamp '2026-09-18' AND a.status <> 'cancelled';

CREATE TEMP VIEW q02 AS
SELECT a.patient_id, a.visit_no, p.last_name, p.first_name, a.dentist_id, a.slot_start, a.status
FROM appointment AS a JOIN patient AS p ON p.patient_id = a.patient_id
WHERE a.slot_start >= timestamp '2026-09-17' AND a.slot_start < timestamp '2026-09-18'
  AND a.status <> 'cancelled';

CREATE TEMP VIEW q07 AS
SELECT p.patient_id, p.last_name, p.first_name FROM patient AS p
WHERE NOT EXISTS (SELECT 1 FROM appointment AS a WHERE a.patient_id = p.patient_id);

DO $verify$
BEGIN
    IF (SELECT count(*) FROM q01) <> 1
       OR NOT EXISTS (SELECT 1 FROM q01 WHERE dentist_id = 1
                      AND slot_start = timestamp '2026-09-17 09:30') THEN
        RAISE EXCEPTION 'Q01: гараар бодсон үр дүнтэй таарахгүй';
    END IF;
    IF (SELECT count(*) FROM q02) <> 1
       OR NOT EXISTS (SELECT 1 FROM q02 WHERE patient_id = 1 AND visit_no = 1
                      AND dentist_id = 1 AND last_name = 'Бат' AND first_name = 'Ану'
                      AND slot_start = timestamp '2026-09-17 09:00' AND status = 'booked') THEN
        RAISE EXCEPTION 'Q02: гараар бодсон үр дүнтэй таарахгүй';
    END IF;
    IF (SELECT count(*) FROM q07) <> 1
       OR NOT EXISTS (SELECT 1 FROM q07 WHERE patient_id = 2 AND last_name = 'Дорж'
                      AND first_name = 'Билгүүн') THEN
        RAISE EXCEPTION 'Q07: гараар бодсон үр дүнтэй таарахгүй';
    END IF;
    RAISE NOTICE 'Q01, Q02, Q07 гараар бодсон үр дүнтэй таарлаа';
END;
$verify$;

SELECT dentist_id, slot_start FROM q01;
SELECT patient_id, visit_no, last_name, first_name, dentist_id, slot_start, status FROM q02;
SELECT patient_id, last_name, first_name FROM q07;
ROLLBACK;
