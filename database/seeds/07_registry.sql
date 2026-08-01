-- ============================================================================
-- seeds/07_registry.sql
-- NATIONAL CITIZEN REGISTRIES (pre-launch master data; still NO applicants).
--
-- These mirror the authoritative external sources the system auto-fills from:
--   * nid               -> National ID registry (adults: guardians/parents)
--   * quota_reference   -> documented quota proofs (e.g. Freedom Fighter)
--   * birth_certificate -> birth registry (children who COULD apply, but none
--                          have yet — there are zero applications in this DB)
-- Generated set-based (generate_series + name arrays) to keep the seed compact.
-- New NIDs use the 17-digit '1985…' band; new birth certs use 'BC4xxx' — both
-- disjoint from the curated demo rows in 01/04 so nothing collides.
-- ============================================================================

-- ---- National ID registry: 200 citizens (gender-coherent names) -------------
INSERT INTO nid (nid, name)
SELECT '1985' || lpad(g::TEXT, 13, '0'),
       CASE WHEN g % 2 = 0
            THEN male[1   + ((g / 2) % array_length(male, 1))]
            ELSE female[1 + ((g / 2) % array_length(female, 1))]
       END
FROM generate_series(1, 200) AS g,
     (SELECT
        ARRAY[
          'MD. ABDUL KARIM','MD. RAFIQUL ISLAM','MOHAMMAD ALI HOSSAIN','MD. JAHANGIR ALAM',
          'MD. SHAFIQUL ISLAM','MD. NURUL AMIN','MD. ABDUR RAZZAK','MD. HABIBUR RAHMAN',
          'MD. KAMRUL HASAN','MD. MIZANUR RAHMAN','MD. SHAHIDUL ISLAM','MD. ABUL KASHEM',
          'MD. DELWAR HOSSAIN','MD. ANWAR HOSSAIN','MD. MOSTAFA KAMAL','MD. GOLAM RABBANI',
          'MD. NAZRUL ISLAM','MD. FARUK AHMED','MD. SOHEL RANA','MD. JASIM UDDIN',
          'MD. BABUL AKTER','MD. ALAMGIR HOSSAIN','MD. SIRAJUL ISLAM','MD. MONIR HOSSAIN',
          'MD. RUHUL AMIN'
        ]::TEXT[] AS male,
        ARRAY[
          'MST. RAHIMA KHATUN','MOST. NASRIN AKTER','SHIRIN BEGUM','MST. AYESHA SIDDIKA',
          'MOST. FATEMA KHATUN','SALMA BEGUM','MST. NAZMA AKTER','MOST. RABEYA BASRI',
          'HALIMA KHATUN','MST. SULTANA RAZIA','MOST. PARVIN AKTER','JAHANARA BEGUM',
          'MST. MORIUM BEGUM','MOST. SHAHANARA KHATUN','ROKEYA BEGUM','MST. TASLIMA AKTER',
          'MOST. KULSUM BEGUM','AMENA KHATUN','MST. NILUFA YASMIN','MOST. DILRUBA AKTER',
          'HASINA BEGUM','MST. MAHMUDA KHATUN','MOST. SHEFALI BEGUM','RAZIA SULTANA',
          'MST. SADIA AFRIN'
        ]::TEXT[] AS female
     ) names
ON CONFLICT (nid) DO NOTHING;

-- ---- Freedom-Fighter references for the first dozen registered citizens ------
INSERT INTO quota_reference (ref_id, nid, quota_code)
SELECT 'FF-' || (2000 + g), '1985' || lpad(g::TEXT, 13, '0'), 'FREEDOM_FIGHTER'
FROM generate_series(1, 12) AS g
ON CONFLICT (ref_id) DO NOTHING;

-- ---- National birth registry: one registered child per district Sadar --------
-- DOBs spread across 2011-2019 so different children map to different classes.
-- These are registry rows only; nobody has applied (zero rows in application).
INSERT INTO birth_certificate (bc_no, name, dob, father_name, mother_name, gender, postcode)
SELECT
    'BC4' || lpad(d.rn::TEXT, 3, '0'),
    n.children[1 + (d.rn % array_length(n.children, 1))],
    make_date((2011 + (d.rn % 9))::INT, (1 + (d.rn % 12))::INT, (1 + (d.rn % 28))::INT),
    n.fathers[1  + (d.rn % array_length(n.fathers, 1))],
    n.mothers[1  + (d.rn % array_length(n.mothers, 1))],
    (CASE WHEN d.rn % 2 = 0 THEN 'MALE' ELSE 'FEMALE' END)::gender_t,
    d.postcode
FROM (
    SELECT (row_number() OVER (ORDER BY postcode))::INT AS rn, postcode
    FROM postcode
    WHERE thana LIKE '% SADAR'
) d
CROSS JOIN (
    SELECT
      ARRAY['RAHIM HASAN','TASNIM AKTER','SAMIUL ISLAM','NUSRAT JAHAN','ARIF HOSSAIN',
            'SADIA ISLAM','TANVIR AHMED','MAHIYA RAHMAN','RIDOY MIA','LAMIA AKTER',
            'NABIL AHMED','MARIA ISLAM','FAHIM SHAHRIAR','ZARIN TASNIA']::TEXT[] AS children,
      ARRAY['MD. ABDUL KARIM','MD. RAFIQUL ISLAM','MD. JAHANGIR ALAM','MD. NURUL AMIN',
            'MD. HABIBUR RAHMAN','MD. DELWAR HOSSAIN','MD. ANWAR HOSSAIN','MD. SIRAJUL ISLAM']::TEXT[] AS fathers,
      ARRAY['RAHIMA KHATUN','NASRIN AKTER','SHIRIN BEGUM','AYESHA SIDDIKA',
            'FATEMA KHATUN','SALMA BEGUM','JAHANARA BEGUM','ROKEYA BEGUM']::TEXT[] AS mothers
) n
ON CONFLICT (bc_no) DO NOTHING;
