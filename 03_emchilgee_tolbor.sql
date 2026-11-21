BEGIN;
SET LOCAL search_path TO dental_clinic, public;

CREATE TYPE tooth_surface AS ENUM ('M', 'D', 'O', 'I', 'F', 'L');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer');

CREATE TABLE service (
    service_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_code text NOT NULL UNIQUE CHECK (service_code ~ '^SR[0-9]{2,}$'),
    service_name text NOT NULL UNIQUE CHECK (btrim(service_name) <> '')
);

CREATE TABLE service_price (
    service_id integer NOT NULL REFERENCES service (service_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    valid_from date NOT NULL CHECK (isfinite(valid_from)),
    fee numeric(12, 0) NOT NULL CHECK (fee > 0 AND fee <> 'NaN'::numeric),
    PRIMARY KEY (service_id, valid_from)
);
CREATE TABLE treatment (
    patient_id integer NOT NULL,
    visit_no integer NOT NULL,
    line_no integer NOT NULL CHECK (line_no > 0),
    visit_status appointment_status GENERATED ALWAYS AS ('completed'::appointment_status) STORED,
    service_id integer NOT NULL,
    price_from date NOT NULL,
    primary_fdi smallint NOT NULL,
    primary_surface tooth_surface NOT NULL,
    note text,
    PRIMARY KEY (patient_id, visit_no, line_no),
    CONSTRAINT treatment_completed_visit FOREIGN KEY (patient_id, visit_no, visit_status)
        REFERENCES appointment (patient_id, visit_no, status)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT treatment_price_fk FOREIGN KEY (service_id, price_from)
        REFERENCES service_price (service_id, valid_from)
        ON UPDATE RESTRICT ON DELETE RESTRICT
);

CREATE TABLE treatment_surface (
    patient_id integer NOT NULL,
    visit_no integer NOT NULL,
    line_no integer NOT NULL,
    fdi smallint NOT NULL,
    surface tooth_surface NOT NULL,
    PRIMARY KEY (patient_id, visit_no, line_no, fdi, surface),
    CONSTRAINT surface_treatment_fk FOREIGN KEY (patient_id, visit_no, line_no)
        REFERENCES treatment (patient_id, visit_no, line_no)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT surface_patient_tooth_fk FOREIGN KEY (patient_id, fdi)
        REFERENCES tooth (patient_id, fdi) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT surface_matches_tooth CHECK (
        (surface <> 'I' OR fdi % 10 BETWEEN 1 AND 3)
        AND (surface <> 'O' OR fdi % 10 >= 4)
    )
);
ALTER TABLE treatment ADD CONSTRAINT treatment_requires_primary_surface
    FOREIGN KEY (patient_id, visit_no, line_no, primary_fdi, primary_surface)
    REFERENCES treatment_surface (patient_id, visit_no, line_no, fdi, surface)
    ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE payment (
    payment_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id integer NOT NULL,
    visit_no integer NOT NULL,
    paid_at timestamp without time zone NOT NULL DEFAULT LOCALTIMESTAMP
        CHECK (isfinite(paid_at)),
    amount numeric(12, 0) NOT NULL CHECK (amount > 0 AND amount <> 'NaN'::numeric),
    method payment_method NOT NULL,
    CONSTRAINT payment_visit_fk FOREIGN KEY (patient_id, visit_no)
        REFERENCES appointment (patient_id, visit_no)
        ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT c.conname AS constraint_name
FROM pg_constraint AS c
WHERE c.conrelid IN ('dental_clinic.treatment'::regclass,
                     'dental_clinic.treatment_surface'::regclass)
  AND c.conname IN ('treatment_completed_visit', 'surface_patient_tooth_fk',
                    'treatment_requires_primary_surface')
ORDER BY c.conname;

COMMIT;
