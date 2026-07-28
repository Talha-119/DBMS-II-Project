-- ============================================================================
-- seeds/01_reference.sql
-- Authoritative reference registries (idempotent via ON CONFLICT DO NOTHING).
-- These are the data the application auto-fills / validates against.
-- ============================================================================

-- Quota types: priority = lottery order (1 first); default_share splits a seat;
-- is_default = the catch-all that absorbs the remainder (GENERAL). New quotas can
-- be added at runtime by the master admin without any schema change.
INSERT INTO quota_type (code, name, requires_reference, priority, default_share, is_default) VALUES
    ('FREEDOM_FIGHTER', 'Freedom Fighter Quota', TRUE,  1, 0.200, FALSE),
    ('AREA',            'Local Area Quota',      FALSE, 2, 0.100, FALSE),
    ('GENERAL',         'General',               FALSE, 3, 0.700, TRUE)
ON CONFLICT (code) DO NOTHING;

-- Postcodes -> administrative areas (Dhaka).
INSERT INTO postcode (postcode, division, district, thana) VALUES
    ('1000', 'DHAKA', 'DHAKA', 'MOTIJHEEL'),
    ('1206', 'DHAKA', 'DHAKA', 'CANTONMENT'),
    ('1217', 'DHAKA', 'DHAKA', 'RAMNA')
ON CONFLICT (postcode) DO NOTHING;

-- Age eligibility windows per class (a child is eligible if DOB is in range).
INSERT INTO class_eligibility (class_level, min_dob, max_dob) VALUES
    (1, DATE '2019-01-01', DATE '2020-12-31'),
    (3, DATE '2017-01-01', DATE '2018-12-31'),
    (6, DATE '2014-01-01', DATE '2015-12-31'),
    (9, DATE '2011-01-01', DATE '2012-12-31')
ON CONFLICT (class_level) DO NOTHING;

-- NID registry: fathers (1991...), mothers (1992...), a local guardian (1993...).
-- Names here must match the birth-certificate parent names (the match is enforced).
INSERT INTO nid (nid, name) VALUES
    ('19910000000000001', 'MD. KAMAL HASAN'),
    ('19910000000000002', 'MD. SELIM UDDIN'),
    ('19910000000000003', 'MD. NURUL ISLAM'),
    ('19910000000000004', 'MD. AZIZUL HAQUE'),
    ('19910000000000005', 'MD. RAFIQUL ISLAM'),
    ('19910000000000006', 'MD. IMRAN HOSSAIN'),
    ('19910000000000007', 'MD. MAHBUB ALAM'),
    ('19910000000000008', 'MD. SAIFUR RAHMAN'),
    ('19910000000000009', 'MD. TOFAZZAL HOSSAIN'),
    ('19910000000000010', 'MD. ABDUR RAHMAN'),
    ('19910000000000011', 'MD. JAHANGIR ALAM'),
    ('19910000000000012', 'MD. SHAHIN MIA'),
    ('19920000000000001', 'FARHANA AKTER'),
    ('19920000000000002', 'RUKEYA BEGUM'),
    ('19920000000000003', 'SALMA KHATUN'),
    ('19920000000000004', 'NASRIN SULTANA'),
    ('19920000000000005', 'SHAHINUR BEGUM'),
    ('19920000000000006', 'MORIUM BEGUM'),
    ('19920000000000007', 'MAHFUZA AKTER'),
    ('19920000000000008', 'JANNATARA BEGUM'),
    ('19920000000000009', 'AYESHA SIDDIKA'),
    ('19920000000000010', 'RAHIMA KHATUN'),
    ('19920000000000011', 'NILUFA YASMIN'),
    ('19920000000000012', 'SHIRIN AKTER'),
    ('19930000000000001', 'MD. ABUL KALAM')
ON CONFLICT (nid) DO NOTHING;

-- Birth-certificate registry. DOBs are chosen to fall inside class windows.
INSERT INTO birth_certificate (bc_no, name, dob, father_name, mother_name, gender, postcode) VALUES
    ('BC3001', 'RAHIM HASAN',   DATE '2018-03-10', 'MD. KAMAL HASAN',     'FARHANA AKTER',   'MALE',   '1000'),
    ('BC3002', 'KAMRUN NAHAR',  DATE '2015-02-11', 'MD. SELIM UDDIN',     'RUKEYA BEGUM',    'FEMALE', '1217'),
    ('BC3003', 'SAMIUL ISLAM',  DATE '2018-09-05', 'MD. NURUL ISLAM',     'SALMA KHATUN',    'MALE',   '1206'),
    ('BC3004', 'NUSRAT JAHAN',  DATE '2017-03-18', 'MD. AZIZUL HAQUE',    'NASRIN SULTANA',  'FEMALE', '1000'),
    ('BC3005', 'TASNIM AKTER',  DATE '2019-01-09', 'MD. RAFIQUL ISLAM',   'SHAHINUR BEGUM',  'FEMALE', '1217'),
    ('BC3006', 'ARIF HOSSAIN',  DATE '2014-11-12', 'MD. IMRAN HOSSAIN',   'MORIUM BEGUM',    'MALE',   '1206'),
    ('BC3007', 'MEHEDI HASAN',  DATE '2012-05-20', 'MD. MAHBUB ALAM',     'MAHFUZA AKTER',   'MALE',   '1000'),
    ('BC3008', 'SADIA ISLAM',   DATE '2018-08-02', 'MD. SAIFUR RAHMAN',   'JANNATARA BEGUM', 'FEMALE', '1217'),
    ('BC3009', 'TANVIR AHMED',  DATE '2015-06-15', 'MD. TOFAZZAL HOSSAIN','AYESHA SIDDIKA',  'MALE',   '1000'),
    ('BC3010', 'MAHIYA RAHMAN', DATE '2011-10-30', 'MD. ABDUR RAHMAN',    'RAHIMA KHATUN',   'FEMALE', '1206'),
    ('BC3011', 'RIDOY MIA',     DATE '2018-12-12', 'MD. JAHANGIR ALAM',   'NILUFA YASMIN',   'MALE',   '1217'),
    ('BC3012', 'LAMIA AKTER',   DATE '2019-04-04', 'MD. SHAHIN MIA',      'SHIRIN AKTER',    'FEMALE', '1000')
ON CONFLICT (bc_no) DO NOTHING;

-- Freedom-fighter references (each tied to a father's NID).
INSERT INTO quota_reference (ref_id, nid, quota_code) VALUES
    ('FF-1001', '19910000000000001', 'FREEDOM_FIGHTER'),
    ('FF-1002', '19910000000000006', 'FREEDOM_FIGHTER')
ON CONFLICT (ref_id) DO NOTHING;
