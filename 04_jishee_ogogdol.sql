-- Шүдний эмнэлэг · B251940028 · Өдөр 2 · Алхам 04
-- 01–03-ыг ажиллуулсан ижил өгөгдлийн санд нэг удаа ажиллуул. Нэр, утас, дүн нь жишээ.
-- Үр дүнгээс patient=24, work_slot=7201, appointment=4800 гэж байгаа эсэхийг шалга.

-- Сургалтын зориулалттай зохиомол өгөгдөл, бодит хүний бүртгэл агуулаагүй.
BEGIN;
SET LOCAL search_path TO dental_clinic, public;

INSERT INTO patient (patient_no, last_name, first_name, birth_date, district, khoroo, address_detail)
SELECT 'P' || lpad(g::text, 3, '0'),
       (ARRAY['Бат', 'Дорж', 'Мөнх', 'Энх', 'Төмөр', 'Сүрэн'])[1 + (g - 1) % 6],
       (ARRAY['Ану', 'Билгүүн', 'Номин', 'Тэмүүлэн', 'Уянга', 'Саруул',
              'Ирмүүн', 'Энхжин', 'Тэнүүн', 'Хулан', 'Хүслэн', 'Гэгээн'])[1 + (g - 1) % 12],
       make_date(CASE WHEN g % 4 = 0 THEN 2017 + g % 3 ELSE 1978 + g * 7 % 28 END,
                 1 + g % 12, 1 + g % 25),
       (ARRAY['Баянзүрх', 'Баянгол', 'Сүхбаатар', 'Хан-Уул', 'Чингэлтэй', 'Сонгинохайрхан'])
           [1 + (g - 1) % 6],
       (1 + g % 15)::smallint, format('%s-р байр, %s тоот', 6 + g, 10 + g)
FROM generate_series(1, 24) AS s(g)
ORDER BY g;

-- 00-ээр эхлэх дугаарууд нь зөвхөн тестийн утга.
INSERT INTO patient_phone (patient_id, phone)
SELECT patient_id, '00' || lpad(patient_id::text, 6, '0') FROM patient
UNION ALL
SELECT patient_id, '01' || lpad(patient_id::text, 6, '0') FROM patient WHERE patient_id % 3 <> 0;

INSERT INTO dental_card (patient_id, card_no, opened_on)
SELECT patient_id, 'SC' || lpad(patient_id::text, 3, '0'), date '2026-06-01' + patient_id
FROM patient;

INSERT INTO tooth (patient_id, fdi)
SELECT c.patient_id, code.fdi
FROM dental_card AS c
CROSS JOIN unnest(ARRAY[11, 16, 26, 36, 46]::smallint[]) AS code(fdi)
UNION ALL
SELECT c.patient_id, code.fdi
FROM dental_card AS c
CROSS JOIN unnest(ARRAY[54, 65]::smallint[]) AS code(fdi)
WHERE c.patient_id % 4 = 0;

INSERT INTO staff (staff_no, last_name, first_name, role)
SELECT 'ST' || lpad(g::text, 3, '0'),
       (ARRAY['Батсайхан', 'Даваа', 'Эрдэнэ', 'Ганболд', 'Сүх', 'Алтан'])[1 + (g - 1) % 6],
       (ARRAY['Оюун', 'Төгс', 'Хишиг', 'Ариун', 'Анударь', 'Ганзориг',
              'Наран', 'Эгшиглэн', 'Мишээл', 'Отгон'])[1 + (g - 1) % 10],
       CASE WHEN g <= 15 THEN 'dentist'::staff_role ELSE 'receptionist'::staff_role END
FROM generate_series(1, 30) AS s(g)
ORDER BY g;

INSERT INTO dentist (staff_id, license_no, specialty)
SELECT staff_id, 'DENT-DEMO-' || lpad(staff_id::text, 3, '0'),
       (ARRAY['Ерөнхий шүдний эмчилгээ', 'Хүүхдийн шүд', 'Нөхөн сэргээх'])
           [1 + (staff_id - 1) % 3]
FROM staff WHERE role = 'dentist';

UPDATE dentist SET backup_dentist_id = staff_id + 1 WHERE staff_id < 15;

INSERT INTO receptionist (staff_id, desk_no)
SELECT staff_id, (1 + (staff_id - 16) % 5)::smallint
FROM staff WHERE role = 'receptionist';

INSERT INTO service (service_code, service_name) VALUES
    ('SR01', 'Урд шүдний гадаргуугийн нөхөн сэргээлт'),
    ('SR02', 'Араа шүдний гадаргуугийн нөхөн сэргээлт'),
    ('SR03', 'Түр ломбо'),
    ('SR04', 'Ховилын битүүмжлэл'),
    ('SR05', 'Шүдний гадаргуу өнгөлөх'),
    ('SR06', 'Шүдний гадаргуугийн мэдрэгшил бууруулах үйлчилгээ'),
    ('SR07', 'Хуучин ломбо авах'),
    ('SR08', 'Ломбо засах'),
    ('SR09', 'Ломбо өнгөлөх'),
    ('SR10', 'Шүдний чулуу цэвэрлэх'),
    ('SR11', 'Шүдний өнгөр цэвэрлэх'),
    ('SR12', 'Гадаргуугийн толбо цэвэрлэх'),
    ('SR13', 'Фторт түрхлэг'),
    ('SR14', 'Шүдний эрдэсжүүлэх түрхлэг'),
    ('SR15', 'Шүдний хамгаалах түрхлэг');

INSERT INTO service_price (service_id, valid_from, fee)
SELECT service_id, date '2026-01-01',
       (ARRAY[85000, 105000, 45000, 45000, 35000, 40000, 55000, 60000,
              35000, 65000, 30000, 42000, 25000, 38000, 33000])[service_id]
FROM service;

INSERT INTO service_price (service_id, valid_from, fee)
SELECT service_id, date '2026-09-01', fee + 7500
FROM service_price WHERE valid_from = date '2026-01-01';

INSERT INTO work_slot (dentist_id, slot_start)
SELECT d.staff_id,
       (date '2026-07-01' + day_offset) + time '09:00' + slot_number * interval '30 minutes'
FROM dentist AS d
CROSS JOIN generate_series(0, 119) AS days(day_offset)
CROSS JOIN generate_series(0, 3) AS slots(slot_number);

-- Транзакц болон бизнес дүрмийн туршилтад зориулсан сул слот.
INSERT INTO work_slot (dentist_id, slot_start) VALUES (1, timestamp '2027-01-20 14:00');

WITH numbered_slots AS (
    SELECT dentist_id, slot_start, slot_start::date - date '2026-07-01' AS day_no,
           ((extract(hour FROM slot_start)::integer - 9) * 2
            + extract(minute FROM slot_start)::integer / 30) AS slot_no
    FROM work_slot
    WHERE slot_start < timestamp '2026-11-01'
), chosen_slots AS (
    SELECT *, 1 + (dentist_id + 5 * day_no + 7 * slot_no) % 23 AS patient_id,
           1 + 60 * day_no + 4 * (dentist_id - 1) + slot_no AS seed_no
    FROM numbered_slots
    WHERE (dentist_id + day_no + slot_no) % 3 <> 0
)
INSERT INTO appointment (patient_id, visit_no, dentist_id, slot_start, booked_by, booked_at, status)
SELECT patient_id,
       row_number() OVER (PARTITION BY patient_id ORDER BY slot_start, dentist_id)::integer,
       dentist_id, slot_start, 16 + seed_no % 15, slot_start - interval '2 days',
       CASE WHEN seed_no % 19 = 0 THEN 'cancelled'::appointment_status
            WHEN seed_no % 17 = 0 THEN 'no_show'::appointment_status
            WHEN day_no >= 105 AND seed_no % 4 = 0 THEN 'booked'::appointment_status
            ELSE 'completed'::appointment_status END
FROM chosen_slots;

WITH lines AS (
    SELECT a.patient_id, a.visit_no, a.slot_start, n.line_no,
           CASE WHEN n.line_no = 2 THEN n.line_no
                ELSE 1 + (a.patient_id + a.visit_no) % 15 END AS service_id,
           CASE WHEN n.line_no = 2 THEN 16
                ELSE (ARRAY[11, 16, 26, 36, 46])[1 + (a.visit_no + a.patient_id) % 5]
                END::smallint AS fdi
    FROM appointment AS a
    CROSS JOIN LATERAL generate_series(1, CASE WHEN a.visit_no % 5 = 0 THEN 2 ELSE 1 END)
        AS n(line_no)
    WHERE a.status = 'completed'
)
INSERT INTO treatment (patient_id, visit_no, line_no, service_id, price_from, primary_fdi, primary_surface)
SELECT l.patient_id, l.visit_no, l.line_no, l.service_id, rate.valid_from, l.fdi, 'M'
FROM lines AS l
CROSS JOIN LATERAL (
    SELECT sp.valid_from
    FROM service_price AS sp
    WHERE sp.service_id = l.service_id AND sp.valid_from <= l.slot_start::date
    ORDER BY sp.valid_from DESC
    LIMIT 1
) AS rate;

INSERT INTO treatment_surface (patient_id, visit_no, line_no, fdi, surface)
SELECT patient_id, visit_no, line_no, primary_fdi, primary_surface FROM treatment
UNION ALL
SELECT patient_id, visit_no, line_no, primary_fdi,
       CASE WHEN primary_fdi % 10 <= 3 THEN 'I'::tooth_surface ELSE 'O'::tooth_surface END
FROM treatment WHERE line_no = 1 AND visit_no % 3 = 0;

WITH bills AS (
    SELECT t.patient_id, t.visit_no, sum(p.fee) AS bill
    FROM treatment AS t
    JOIN service_price AS p
      ON p.service_id = t.service_id AND p.valid_from = t.price_from
    GROUP BY t.patient_id, t.visit_no
)
INSERT INTO payment (patient_id, visit_no, paid_at, amount, method)
SELECT b.patient_id, b.visit_no, a.slot_start + interval '30 minutes',
       CASE WHEN b.visit_no % 3 = 0 THEN round(b.bill / 2) ELSE b.bill END,
       (ARRAY['cash', 'card', 'transfer']::payment_method[])[1 + b.visit_no % 3]
FROM bills AS b JOIN appointment AS a USING (patient_id, visit_no)
WHERE b.visit_no % 7 <> 0
UNION ALL
SELECT b.patient_id, b.visit_no, a.slot_start + interval '1 day',
       b.bill - round(b.bill / 2), 'transfer'::payment_method
FROM bills AS b JOIN appointment AS a USING (patient_id, visit_no)
WHERE b.visit_no % 7 <> 0 AND b.visit_no % 6 = 0;

-- Шалгалт. Жишээ өгөгдлийн үндсэн мөрийн тоо.
SELECT 'patient' AS table_name, count(*) AS row_count FROM patient
UNION ALL SELECT 'work_slot', count(*) FROM work_slot
UNION ALL SELECT 'appointment', count(*) FROM appointment
UNION ALL SELECT 'treatment', count(*) FROM treatment
UNION ALL SELECT 'treatment_surface', count(*) FROM treatment_surface
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY table_name;

COMMIT;
