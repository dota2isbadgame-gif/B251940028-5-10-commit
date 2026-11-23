BEGIN;
SET LOCAL search_path TO dental_clinic, public;
ANALYZE appointment;
ANALYZE payment;

EXPLAIN (ANALYZE, BUFFERS)
SELECT patient_id, visit_no, dentist_id, status
FROM appointment
WHERE slot_start >= timestamp '2026-09-17 09:30'
  AND slot_start < timestamp '2026-09-17 09:31';

EXPLAIN (ANALYZE, BUFFERS)
SELECT payment_id, amount, method
FROM payment
WHERE paid_at >= timestamp '2026-09-17 10:00'
  AND paid_at < timestamp '2026-09-17 10:01';

CREATE INDEX idx_demo_appointment_start ON appointment (slot_start);
CREATE INDEX idx_demo_payment_paid_at ON payment (paid_at);
ANALYZE appointment;
ANALYZE payment;

EXPLAIN (ANALYZE, BUFFERS)
SELECT patient_id, visit_no, dentist_id, status
FROM appointment
WHERE slot_start >= timestamp '2026-09-17 09:30'
  AND slot_start < timestamp '2026-09-17 09:31';

EXPLAIN (ANALYZE, BUFFERS)
SELECT payment_id, amount, method
FROM payment
WHERE paid_at >= timestamp '2026-09-17 10:00'
  AND paid_at < timestamp '2026-09-17 10:01';

ROLLBACK;
