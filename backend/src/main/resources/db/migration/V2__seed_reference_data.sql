-- ============================================================
-- V2: Seed reference data
-- SuperAdmin person+user, system units+conversions,
-- default categories, account types, store categories,
-- payment methods, purchase nature tags, platform patterns.
-- ============================================================

-- ── SuperAdmin person & user ─────────────────────────────────
-- Password: Admin@1234  (BCrypt strength 12)
-- Must be changed on first login.

INSERT INTO persons (household_id, name, is_whole_household)
VALUES (NULL, 'Admin', FALSE);

INSERT INTO users (person_id, household_id, email, password_hash, role, must_change_password)
VALUES (
    (SELECT id FROM persons WHERE name = 'Admin' AND household_id IS NULL),
    NULL,
    'admin@budgettracker.local',
    '$2a$12$rXDu9E6k1mX4F2z8Y.vQ8.xQ1Y3JKkqV5fZvZ8mN4PqR6wL7sT2Oi',
    'SUPER_ADMIN',
    TRUE
);

-- ── System units of measure ──────────────────────────────────

INSERT INTO units_of_measure (household_id, name, symbol, is_system) VALUES
-- Weight
(NULL, 'Kilogram', 'kg',  TRUE),
(NULL, 'Gram',     'g',   TRUE),
(NULL, 'Milligram','mg',  TRUE),
-- Volume
(NULL, 'Litre',    'L',   TRUE),
(NULL, 'Millilitre','mL', TRUE),
-- Count
(NULL, 'Each',     'ea',  TRUE),
(NULL, 'Dozen',    'doz', TRUE),
-- Length
(NULL, 'Metre',    'm',   TRUE),
(NULL, 'Centimetre','cm', TRUE),
(NULL, 'Millimetre','mm', TRUE),
(NULL, 'Foot',     'ft',  TRUE),
(NULL, 'Inch',     'in',  TRUE),
(NULL, 'Yard',     'yd',  TRUE);

-- ── System unit conversions ──────────────────────────────────
-- Stored as bidirectional pairs (A→B and B→A).

INSERT INTO unit_conversions (household_id, from_unit_id, to_unit_id, factor, is_system)
SELECT NULL,
       (SELECT id FROM units_of_measure WHERE symbol = f AND is_system),
       (SELECT id FROM units_of_measure WHERE symbol = t AND is_system),
       v,
       TRUE
FROM (VALUES
    -- Weight
    ('kg',  'g',   1000),
    ('g',   'kg',  0.001),
    ('g',   'mg',  1000),
    ('mg',  'g',   0.001),
    ('kg',  'mg',  1000000),
    ('mg',  'kg',  0.000001),
    -- Volume
    ('L',   'mL',  1000),
    ('mL',  'L',   0.001),
    -- Count
    ('doz', 'ea',  12),
    ('ea',  'doz', 0.08333333),
    -- Length
    ('m',   'cm',  100),
    ('cm',  'm',   0.01),
    ('cm',  'mm',  10),
    ('mm',  'cm',  0.1),
    ('m',   'mm',  1000),
    ('mm',  'm',   0.001),
    ('m',   'ft',  3.28084),
    ('ft',  'm',   0.3048),
    ('ft',  'in',  12),
    ('in',  'ft',  0.08333333),
    ('yd',  'ft',  3),
    ('ft',  'yd',  0.33333333),
    ('yd',  'm',   0.9144),
    ('m',   'yd',  1.09361)
) AS c(f, t, v);

-- ── Default platform sender patterns (system-wide, no household) ──
-- These will be copied per household on registration.
-- Stored here as a reference; actual per-household rows seeded on approval.
-- (No insert needed here — seeded in application code during household activation.)

-- Note: Per-household reference data (categories, account types, store categories,
-- payment methods, purchase nature tags) is seeded programmatically in
-- HouseholdService.activate() so each household gets its own isolated copies.
-- See HouseholdService for the seeding logic.
