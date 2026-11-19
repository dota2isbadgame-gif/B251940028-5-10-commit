BEGIN;
CREATE SCHEMA dental_clinic;
SET LOCAL search_path TO dental_clinic, public;

CREATE TYPE staff_role AS ENUM ('dentist', 'receptionist');

CREATE TABLE patient (
    patient_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_no text NOT NULL UNIQUE CHECK (patient_no ~ '^P[0-9]{3,}$'),
    last_name text NOT NULL CHECK (btrim(last_name) <> ''),
    first_name text NOT NULL CHECK (btrim(first_name) <> ''),
    birth_date date NOT NULL CHECK (isfinite(birth_date)),
    district text NOT NULL CHECK (btrim(district) <> ''),
    khoroo smallint NOT NULL CHECK (khoroo BETWEEN 1 AND 99),
    address_detail text NOT NULL CHECK (btrim(address_detail) <> '')
);

CREATE TABLE patient_phone (
    patient_id integer NOT NULL REFERENCES patient (patient_id)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    phone text NOT NULL CHECK (phone ~ '^[0-9]{8}$'),
    PRIMARY KEY (patient_id, phone)
);

CREATE TABLE dental_card (
    patient_id integer PRIMARY KEY REFERENCES patient (patient_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    card_no text NOT NULL UNIQUE CHECK (card_no ~ '^SC[0-9]{3,}$'),
    opened_on date NOT NULL DEFAULT CURRENT_DATE CHECK (isfinite(opened_on))
);

CREATE TABLE tooth (
    patient_id integer NOT NULL REFERENCES dental_card (patient_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    fdi smallint NOT NULL,
    PRIMARY KEY (patient_id, fdi),
    CONSTRAINT tooth_valid_fdi CHECK (
        (fdi / 10 BETWEEN 1 AND 4 AND fdi % 10 BETWEEN 1 AND 8)
        OR (fdi / 10 BETWEEN 5 AND 8 AND fdi % 10 BETWEEN 1 AND 5)
    )
);

CREATE TABLE staff (
    staff_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    staff_no text NOT NULL UNIQUE CHECK (staff_no ~ '^ST[0-9]{3,}$'),
    last_name text NOT NULL CHECK (btrim(last_name) <> ''),
    first_name text NOT NULL CHECK (btrim(first_name) <> ''),
    role staff_role NOT NULL,
    active boolean NOT NULL DEFAULT true,
    UNIQUE (staff_id, role)
);

CREATE TABLE dentist (
    staff_id integer PRIMARY KEY,
    role staff_role GENERATED ALWAYS AS ('dentist'::staff_role) STORED,
    license_no text NOT NULL UNIQUE CHECK (btrim(license_no) <> ''),
    specialty text NOT NULL CHECK (btrim(specialty) <> ''),
    backup_dentist_id integer REFERENCES dentist (staff_id)
        ON UPDATE RESTRICT ON DELETE SET NULL,
    CONSTRAINT dentist_staff_role_fk FOREIGN KEY (staff_id, role)
        REFERENCES staff (staff_id, role) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT dentist_different_backup CHECK (backup_dentist_id <> staff_id)
);

CREATE TABLE receptionist (
    staff_id integer PRIMARY KEY,
    role staff_role GENERATED ALWAYS AS ('receptionist'::staff_role) STORED,
    desk_no smallint NOT NULL CHECK (desk_no > 0),
    CONSTRAINT receptionist_staff_role_fk FOREIGN KEY (staff_id, role)
        REFERENCES staff (staff_id, role) ON UPDATE RESTRICT ON DELETE CASCADE
);

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'dental_clinic'
AND table_name IN ('patient', 'patient_phone', 'dental_card', 'tooth','staff', 'dentist', 'receptionist')
ORDER BY table_name;

COMMIT;
