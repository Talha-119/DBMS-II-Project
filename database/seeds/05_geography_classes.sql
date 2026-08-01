-- ============================================================================
-- seeds/05_geography_classes.sql
-- NATIONAL ROLLOUT DATA (pre-launch master data; no applicants yet).
--
-- 1) Complete the class ladder: classes 1,3,6,9 are seeded in 01_reference.sql
--    with 2-year admission windows (each effectively covers two grade-ages, as
--    is common with loose age cut-offs). Here we add the remaining classes so a
--    school can offer ANY class 1-12 (this is why "Class 4 is not configured"
--    used to appear — only 1/3/6/9 had an eligibility window).
--
-- 2) Geography: every district of Bangladesh (all 64, across 8 divisions) keyed
--    by its Sadar (HQ) postcode, plus a few extra Dhaka city thanas so the
--    largest metro has multiple areas in the cascading dropdown. Real 4-digit
--    postal codes. Idempotent via ON CONFLICT DO NOTHING.
-- ============================================================================

-- ---- Remaining class eligibility windows (single birth-year each) -----------
-- Existing (kept untouched): 1=[2019-2020], 3=[2017-2018], 6=[2014-2015], 9=[2011-2012].
INSERT INTO class_eligibility (class_level, min_dob, max_dob) VALUES
    (2,  DATE '2019-01-01', DATE '2019-12-31'),
    (4,  DATE '2017-01-01', DATE '2017-12-31'),
    (5,  DATE '2016-01-01', DATE '2016-12-31'),
    (7,  DATE '2014-01-01', DATE '2014-12-31'),
    (8,  DATE '2013-01-01', DATE '2013-12-31'),
    (10, DATE '2011-01-01', DATE '2011-12-31'),
    (11, DATE '2010-01-01', DATE '2010-12-31'),
    (12, DATE '2009-01-01', DATE '2009-12-31')
ON CONFLICT (class_level) DO NOTHING;

-- ---- All 64 districts, keyed by Sadar postcode ------------------------------
-- thana = '<DISTRICT> SADAR' is the marker the school generator (06) keys off.
INSERT INTO postcode (postcode, division, district, thana) VALUES
    -- DHAKA DIVISION (Dhaka city itself is already seeded as separate thanas)
    ('7800', 'DHAKA', 'FARIDPUR',       'FARIDPUR SADAR'),
    ('1700', 'DHAKA', 'GAZIPUR',        'GAZIPUR SADAR'),
    ('8100', 'DHAKA', 'GOPALGANJ',      'GOPALGANJ SADAR'),
    ('2300', 'DHAKA', 'KISHOREGANJ',    'KISHOREGANJ SADAR'),
    ('7900', 'DHAKA', 'MADARIPUR',      'MADARIPUR SADAR'),
    ('1800', 'DHAKA', 'MANIKGANJ',      'MANIKGANJ SADAR'),
    ('1500', 'DHAKA', 'MUNSHIGANJ',     'MUNSHIGANJ SADAR'),
    ('1400', 'DHAKA', 'NARAYANGANJ',    'NARAYANGANJ SADAR'),
    ('1600', 'DHAKA', 'NARSINGDI',      'NARSINGDI SADAR'),
    ('7700', 'DHAKA', 'RAJBARI',        'RAJBARI SADAR'),
    ('8000', 'DHAKA', 'SHARIATPUR',     'SHARIATPUR SADAR'),
    ('1900', 'DHAKA', 'TANGAIL',        'TANGAIL SADAR'),
    -- CHATTOGRAM DIVISION
    ('4000', 'CHATTOGRAM', 'CHATTOGRAM',   'CHATTOGRAM SADAR'),
    ('4600', 'CHATTOGRAM', 'BANDARBAN',    'BANDARBAN SADAR'),
    ('3400', 'CHATTOGRAM', 'BRAHMANBARIA', 'BRAHMANBARIA SADAR'),
    ('3600', 'CHATTOGRAM', 'CHANDPUR',     'CHANDPUR SADAR'),
    ('4700', 'CHATTOGRAM', 'COX''S BAZAR', 'COX''S BAZAR SADAR'),
    ('3500', 'CHATTOGRAM', 'CUMILLA',      'CUMILLA SADAR'),
    ('3900', 'CHATTOGRAM', 'FENI',         'FENI SADAR'),
    ('4400', 'CHATTOGRAM', 'KHAGRACHHARI', 'KHAGRACHHARI SADAR'),
    ('3700', 'CHATTOGRAM', 'LAKSHMIPUR',   'LAKSHMIPUR SADAR'),
    ('3800', 'CHATTOGRAM', 'NOAKHALI',     'NOAKHALI SADAR'),
    ('4500', 'CHATTOGRAM', 'RANGAMATI',    'RANGAMATI SADAR'),
    -- RAJSHAHI DIVISION
    ('6000', 'RAJSHAHI', 'RAJSHAHI',         'RAJSHAHI SADAR'),
    ('5800', 'RAJSHAHI', 'BOGURA',           'BOGURA SADAR'),
    ('5900', 'RAJSHAHI', 'JOYPURHAT',        'JOYPURHAT SADAR'),
    ('6500', 'RAJSHAHI', 'NAOGAON',          'NAOGAON SADAR'),
    ('6400', 'RAJSHAHI', 'NATORE',           'NATORE SADAR'),
    ('6300', 'RAJSHAHI', 'CHAPAINAWABGANJ',  'CHAPAINAWABGANJ SADAR'),
    ('6600', 'RAJSHAHI', 'PABNA',            'PABNA SADAR'),
    ('6700', 'RAJSHAHI', 'SIRAJGANJ',        'SIRAJGANJ SADAR'),
    -- KHULNA DIVISION
    ('9000', 'KHULNA', 'KHULNA',     'KHULNA SADAR'),
    ('9300', 'KHULNA', 'BAGERHAT',   'BAGERHAT SADAR'),
    ('7200', 'KHULNA', 'CHUADANGA',  'CHUADANGA SADAR'),
    ('7400', 'KHULNA', 'JASHORE',    'JASHORE SADAR'),
    ('7300', 'KHULNA', 'JHENAIDAH',  'JHENAIDAH SADAR'),
    ('7000', 'KHULNA', 'KUSHTIA',    'KUSHTIA SADAR'),
    ('7600', 'KHULNA', 'MAGURA',     'MAGURA SADAR'),
    ('7100', 'KHULNA', 'MEHERPUR',   'MEHERPUR SADAR'),
    ('7500', 'KHULNA', 'NARAIL',     'NARAIL SADAR'),
    ('9400', 'KHULNA', 'SATKHIRA',   'SATKHIRA SADAR'),
    -- BARISHAL DIVISION
    ('8200', 'BARISHAL', 'BARISHAL',   'BARISHAL SADAR'),
    ('8700', 'BARISHAL', 'BARGUNA',    'BARGUNA SADAR'),
    ('8300', 'BARISHAL', 'BHOLA',      'BHOLA SADAR'),
    ('8400', 'BARISHAL', 'JHALOKATI',  'JHALOKATI SADAR'),
    ('8600', 'BARISHAL', 'PATUAKHALI', 'PATUAKHALI SADAR'),
    ('8500', 'BARISHAL', 'PIROJPUR',   'PIROJPUR SADAR'),
    -- SYLHET DIVISION
    ('3100', 'SYLHET', 'SYLHET',      'SYLHET SADAR'),
    ('3300', 'SYLHET', 'HABIGANJ',    'HABIGANJ SADAR'),
    ('3200', 'SYLHET', 'MOULVIBAZAR', 'MOULVIBAZAR SADAR'),
    ('3000', 'SYLHET', 'SUNAMGANJ',   'SUNAMGANJ SADAR'),
    -- RANGPUR DIVISION
    ('5400', 'RANGPUR', 'RANGPUR',      'RANGPUR SADAR'),
    ('5200', 'RANGPUR', 'DINAJPUR',     'DINAJPUR SADAR'),
    ('5700', 'RANGPUR', 'GAIBANDHA',    'GAIBANDHA SADAR'),
    ('5600', 'RANGPUR', 'KURIGRAM',     'KURIGRAM SADAR'),
    ('5500', 'RANGPUR', 'LALMONIRHAT',  'LALMONIRHAT SADAR'),
    ('5300', 'RANGPUR', 'NILPHAMARI',   'NILPHAMARI SADAR'),
    ('5000', 'RANGPUR', 'PANCHAGARH',   'PANCHAGARH SADAR'),
    ('5100', 'RANGPUR', 'THAKURGAON',   'THAKURGAON SADAR'),
    -- MYMENSINGH DIVISION
    ('2200', 'MYMENSINGH', 'MYMENSINGH', 'MYMENSINGH SADAR'),
    ('2000', 'MYMENSINGH', 'JAMALPUR',   'JAMALPUR SADAR'),
    ('2400', 'MYMENSINGH', 'NETROKONA',  'NETROKONA SADAR'),
    ('2100', 'MYMENSINGH', 'SHERPUR',    'SHERPUR SADAR')
ON CONFLICT (postcode) DO NOTHING;

-- ---- Extra Dhaka-city thanas (richer cascading dropdown for the metro) -------
INSERT INTO postcode (postcode, division, district, thana) VALUES
    ('1205', 'DHAKA', 'DHAKA', 'DHANMONDI'),
    ('1207', 'DHAKA', 'DHAKA', 'MOHAMMADPUR'),
    ('1209', 'DHAKA', 'DHAKA', 'TEJGAON'),
    ('1216', 'DHAKA', 'DHAKA', 'MIRPUR'),
    ('1219', 'DHAKA', 'DHAKA', 'BADDA'),
    ('1230', 'DHAKA', 'DHAKA', 'UTTARA')
ON CONFLICT (postcode) DO NOTHING;
