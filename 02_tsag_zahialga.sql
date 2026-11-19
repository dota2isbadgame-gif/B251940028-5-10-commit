BEGIN;
SET LOCAL search_path TO dental_clinic, public;

CREATE TYPE appointment_status AS ENUM ('booked', 'completed', 'cancelled', 'no_show');
CREATE TABLE work_slot (
    dentist_id integer NOT NULL REFERENCES dentist (staff_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    slot_start timestamp without time zone NOT NULL,
    PRIMARY KEY (dentist_id, slot_start),
    CONSTRAINT work_slot_half_hour CHECK (
        isfinite(slot_start)
        AND extract(minute FROM slot_start) IN (0, 30)
        AND date_trunc('minute', slot_start) = slot_start
    )
);

CREATE TABLE appointment (
    patient_id integer NOT NULL REFERENCES patient (patient_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    visit_no integer NOT NULL CHECK (visit_no > 0),
    dentist_id integer NOT NULL,
    slot_start timestamp without time zone NOT NULL,
    booked_by integer NOT NULL REFERENCES receptionist (staff_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    booked_at timestamp without time zone NOT NULL DEFAULT LOCALTIMESTAMP,
    status appointment_status NOT NULL DEFAULT 'booked',
    PRIMARY KEY (patient_id, visit_no),
    UNIQUE (patient_id, visit_no, status),
    CONSTRAINT appointment_in_schedule FOREIGN KEY (dentist_id, slot_start)
        REFERENCES work_slot (dentist_id, slot_start)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT appointment_booked_in_time CHECK (
        isfinite(booked_at) AND booked_at <= slot_start
    )
);
CREATE UNIQUE INDEX appointment_dentist_slot_unique
    ON appointment (dentist_id, slot_start)
    WHERE status <> 'cancelled';
CREATE UNIQUE INDEX appointment_patient_slot_unique
    ON appointment (patient_id, slot_start)
    WHERE status <> 'cancelled';

-- Шалгалт. Нэг слотод хоёр цуцлагдаагүй захиалга оруулж болохгүй.
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'dental_clinic' AND tablename = 'appointment'
  AND indexname IN ('appointment_dentist_slot_unique', 'appointment_patient_slot_unique')
ORDER BY indexname;

COMMIT;
