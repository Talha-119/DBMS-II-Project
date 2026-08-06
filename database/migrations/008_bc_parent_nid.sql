-- ============================================================================
-- 008_bc_parent_nid.sql
-- BUG-002: records birth-certificate parentage as a NID reference instead of a
-- name, so fn_check_guardian can compare identities rather than strings.
--
-- Rationale is in 002_reference_tables.sql. 002 already declares the new shape,
-- so on a freshly built database this file is a no-op. It exists for databases
-- created before the change; every step is guarded, so running it repeatedly
-- (as migrate.js does) is safe.
--
-- RETROFIT CAVEAT, stated plainly because it cannot be engineered away: the old
-- schema recorded only a name, and names in this registry are not unique (up to
-- 8 citizens share one). Choosing *which* of several same-named NIDs is the real
-- parent is therefore a guess. The rule below is deterministic and defensible,
-- but it is a guess. Data seeded after this migration carries the NID directly
-- and needs no guessing.
-- ============================================================================

ALTER TABLE birth_certificate ADD COLUMN IF NOT EXISTS father_nid VARCHAR(20);
ALTER TABLE birth_certificate ADD COLUMN IF NOT EXISTS mother_nid VARCHAR(20);

DO $$
DECLARE
    v_unresolved INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'birth_certificate' AND column_name = 'father_name'
    ) THEN
        RETURN;                                    -- already migrated / fresh build
    END IF;

    -- birth_certificate is a read-only registry (trg_protect_registry blocks
    -- UPDATE). This migration is the one legitimate writer, so the guard is
    -- lifted for the backfill and restored immediately afterwards.
    ALTER TABLE birth_certificate DISABLE TRIGGER trg_protect_birth_certificate;

    -- Resolution order, most trustworthy first:
    --   1. a NID an existing student already submitted for this certificate and
    --      that passed the old name check — the closest thing to evidence we
    --      have, and it keeps already-filed applications valid;
    --   2. an exact name match, lowest NID first for determinism;
    --   3. a name match ignoring the honorific prefix (MD./MST./MOST.), which
    --      the seed data applies inconsistently — 16 mothers are recorded as
    --      'NASRIN AKTER' on the certificate but 'MOST. NASRIN AKTER' in the NID
    --      registry. Those are the same people, and their failure to match is
    --      itself a demonstration of why string comparison is the wrong tool.
    WITH strip AS (
        SELECT nid, upper(btrim(regexp_replace(name, '^(MD\.|MST\.|MOST\.|MRS\.|MR\.)\s*', '', 'i'))) AS bare
        FROM nid
    ),
    resolved AS (
        SELECT b.bc_no,
            COALESCE(
              (SELECT s.father_nid FROM student s
                WHERE s.bc_no = b.bc_no AND s.father_nid IS NOT NULL
                  AND EXISTS (SELECT 1 FROM nid n WHERE n.nid = s.father_nid
                               AND upper(btrim(n.name)) = upper(btrim(b.father_name)))),
              (SELECT min(n.nid) FROM nid n WHERE upper(btrim(n.name)) = upper(btrim(b.father_name))),
              (SELECT min(x.nid) FROM strip x WHERE x.bare = upper(btrim(b.father_name)))
            ) AS f_nid,
            COALESCE(
              (SELECT s.mother_nid FROM student s
                WHERE s.bc_no = b.bc_no AND s.mother_nid IS NOT NULL
                  AND EXISTS (SELECT 1 FROM nid n WHERE n.nid = s.mother_nid
                               AND upper(btrim(n.name)) = upper(btrim(b.mother_name)))),
              (SELECT min(n.nid) FROM nid n WHERE upper(btrim(n.name)) = upper(btrim(b.mother_name))),
              (SELECT min(x.nid) FROM strip x WHERE x.bare = upper(btrim(b.mother_name)))
            ) AS m_nid
        FROM birth_certificate b
    )
    UPDATE birth_certificate b
       SET father_nid = r.f_nid, mother_nid = r.m_nid
      FROM resolved r
     WHERE r.bc_no = b.bc_no;

    ALTER TABLE birth_certificate ENABLE TRIGGER trg_protect_birth_certificate;

    SELECT count(*) INTO v_unresolved
      FROM birth_certificate WHERE father_nid IS NULL OR mother_nid IS NULL;
    IF v_unresolved > 0 THEN
        RAISE EXCEPTION 'Cannot migrate: % birth certificate(s) name a parent with no NID in the registry. '
                        'Add those citizens to `nid` first, then re-run.', v_unresolved;
    END IF;

    ALTER TABLE birth_certificate DROP COLUMN father_name;
    ALTER TABLE birth_certificate DROP COLUMN mother_name;

    RAISE NOTICE 'birth_certificate parentage moved from names to NID references.';
END $$;

-- Constraints last, so the backfill above had room to work. Guarded individually
-- so a re-run is a no-op.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM birth_certificate WHERE father_nid IS NULL OR mother_nid IS NULL) THEN
        RAISE WARNING 'NULL parent NIDs remain; NOT NULL not applied.';
    ELSE
        ALTER TABLE birth_certificate ALTER COLUMN father_nid SET NOT NULL;
        ALTER TABLE birth_certificate ALTER COLUMN mother_nid SET NOT NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'birth_certificate'::regclass
                      AND conname = 'birth_certificate_father_nid_fkey') THEN
        ALTER TABLE birth_certificate
            ADD CONSTRAINT birth_certificate_father_nid_fkey
            FOREIGN KEY (father_nid) REFERENCES nid(nid);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'birth_certificate'::regclass
                      AND conname = 'birth_certificate_mother_nid_fkey') THEN
        ALTER TABLE birth_certificate
            ADD CONSTRAINT birth_certificate_mother_nid_fkey
            FOREIGN KEY (mother_nid) REFERENCES nid(nid);
    END IF;
END $$;

-- Any student row whose submitted guardian NID disagrees with the (now
-- authoritative) birth certificate was accepted under the old string rule.
-- Report rather than delete: this is the pre-existing data BUG-002 allowed in,
-- and it needs a human decision, not a silent rewrite.
DO $$
DECLARE v_bad INT;
BEGIN
    SELECT count(*) INTO v_bad FROM student s JOIN birth_certificate b ON b.bc_no = s.bc_no
     WHERE (s.father_nid IS NOT NULL AND s.father_nid <> b.father_nid)
        OR (s.mother_nid IS NOT NULL AND s.mother_nid <> b.mother_nid);
    IF v_bad > 0 THEN
        RAISE WARNING 'BUG-002 legacy: % existing student row(s) hold a guardian NID that is not the one '
                      'on the birth certificate. They were accepted by the old name check. Review them.', v_bad;
    END IF;
END $$;
