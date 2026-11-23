SET search_path TO dental_clinic, public;
SELECT pg_backend_pid() AS session_id;

DELETE FROM appointment
WHERE (patient_id, visit_no, booked_by) IN ((1, 9001, 16), (2, 9002, 17))
  AND dentist_id = 1 AND slot_start = timestamp '2027-01-20 14:00';

BEGIN ISOLATION LEVEL READ COMMITTED;
SHOW transaction_isolation;
SELECT count(*) AS occupied
FROM appointment
WHERE dentist_id = 1 AND slot_start = timestamp '2027-01-20 14:00'
  AND status <> 'cancelled';

INSERT INTO appointment (patient_id, visit_no, dentist_id, slot_start, booked_by, booked_at)
VALUES (1, 9001, 1, timestamp '2027-01-20 14:00', 16, timestamp '2027-01-19 14:00')
ON CONFLICT (dentist_id, slot_start) WHERE status <> 'cancelled' DO NOTHING
RETURNING patient_id, visit_no, booked_by;

INSERT INTO appointment (patient_id, visit_no, dentist_id, slot_start, booked_by, booked_at)
VALUES (2, 9002, 1, timestamp '2027-01-20 14:00', 17, timestamp '2027-01-19 14:00')
ON CONFLICT (dentist_id, slot_start) WHERE status <> 'cancelled' DO NOTHING
RETURNING patient_id, visit_no, booked_by;
COMMIT;

SELECT count(*) AS occupied
FROM appointment
WHERE dentist_id = 1 AND slot_start = timestamp '2027-01-20 14:00'
  AND status <> 'cancelled';
COMMIT;

SELECT patient_id, visit_no, dentist_id, slot_start, booked_by, status
FROM appointment
WHERE dentist_id = 1 AND slot_start = timestamp '2027-01-20 14:00'
  AND status <> 'cancelled';
