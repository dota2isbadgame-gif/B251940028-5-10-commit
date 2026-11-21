BEGIN READ ONLY;
SET LOCAL search_path TO dental_clinic, public;

SELECT d.staff_id AS dentist_id, s.first_name AS dentist_name,
       d.backup_dentist_id, replacement.first_name AS backup_name
FROM dentist AS d
JOIN staff AS s ON s.staff_id = d.staff_id
LEFT JOIN staff AS replacement ON replacement.staff_id = d.backup_dentist_id
ORDER BY d.staff_id;

SELECT patient_id, visit_no, count(*) AS payment_count, sum(amount) AS paid_mnt
FROM payment
GROUP BY patient_id, visit_no
HAVING count(*) > 1
ORDER BY payment_count DESC, patient_id, visit_no;

SELECT payment_id, patient_id, visit_no, amount, method
FROM payment
WHERE amount > (SELECT avg(amount) FROM payment)
ORDER BY amount DESC, payment_id;

SELECT s.service_code, p.valid_from, p.fee
FROM service_price AS p
JOIN service AS s USING (service_id)
WHERE p.fee > (
    SELECT avg(history.fee)
    FROM service_price AS history
    WHERE history.service_id = p.service_id
)
ORDER BY s.service_code, p.valid_from;

SELECT patient_id
FROM appointment
WHERE slot_start >= timestamp '2026-09-17' AND slot_start < timestamp '2026-09-18'
  AND status <> 'cancelled'
UNION
SELECT patient_id
FROM payment
WHERE paid_at >= timestamp '2026-09-17' AND paid_at < timestamp '2026-09-18'
ORDER BY patient_id;

WITH totals AS (
    SELECT date_trunc('month', p.paid_at)::date AS paid_month,
           a.dentist_id, sum(p.amount) AS revenue_mnt
    FROM payment AS p
    JOIN appointment AS a USING (patient_id, visit_no)
    GROUP BY date_trunc('month', p.paid_at)::date, a.dentist_id
)
SELECT paid_month, dentist_id, revenue_mnt,
       dense_rank() OVER (PARTITION BY paid_month ORDER BY revenue_mnt DESC) AS position
FROM totals
ORDER BY paid_month, position, dentist_id;

WITH prices_with_previous AS (
    SELECT s.service_code, p.valid_from, p.fee,
           lag(p.fee) OVER (PARTITION BY p.service_id ORDER BY p.valid_from) AS previous_fee
    FROM service_price AS p
    JOIN service AS s USING (service_id)
)
SELECT service_code, valid_from, fee, previous_fee, fee - previous_fee AS change_mnt
FROM prices_with_previous
ORDER BY service_code, valid_from;

WITH daily AS (
    SELECT slot_start::date AS visit_day, count(*) AS booking_count,
           count(*) FILTER (WHERE status = 'cancelled') AS cancellation_count
    FROM appointment
    WHERE slot_start >= timestamp '2026-09-01' AND slot_start < timestamp '2026-10-01'
    GROUP BY slot_start::date
)
SELECT visit_day, booking_count, cancellation_count,
       round(100.0 * cancellation_count / booking_count, 1) AS cancellation_pct
FROM daily
ORDER BY visit_day;

SELECT a.patient_id, a.visit_no, a.slot_start, count(DISTINCT x.fdi) AS tooth_count
FROM appointment AS a
JOIN treatment_surface AS x USING (patient_id, visit_no)
GROUP BY a.patient_id, a.visit_no, a.slot_start
HAVING count(DISTINCT x.fdi) >= 2
ORDER BY tooth_count DESC, a.patient_id, a.visit_no;

SELECT method, count(*) AS payment_count, sum(amount) AS revenue_mnt
FROM payment
WHERE paid_at >= timestamp '2026-09-01' AND paid_at < timestamp '2026-10-01'
GROUP BY method
ORDER BY revenue_mnt DESC, method;

COMMIT;
