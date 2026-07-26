-- ============================================================================
-- 005_application.sql
-- The application core: a reusable student profile, the applications a student
-- submits, and up to 5 ordered seat choices per application.
-- ============================================================================

-- Sequence backing the human-readable application id (APP-YYYY-000123).
CREATE SEQUENCE IF NOT EXISTS seq_application START WITH 1;

-- Reusable per-student profile (keyed by birth certificate). A student can file
-- several applications; their profile is filled once.
CREATE TABLE IF NOT EXISTS student (
    bc_no               VARCHAR(20) PRIMARY KEY REFERENCES birth_certificate(bc_no),
    religion            religion_t  NOT NULL,
    mobile              VARCHAR(11) NOT NULL CHECK (mobile ~ '^01[3-9][0-9]{8}$'),
    father_nid          VARCHAR(20) REFERENCES nid(nid),
    mother_nid          VARCHAR(20) REFERENCES nid(nid),
    local_guardian_nid  VARCHAR(20) REFERENCES nid(nid),
    present_postcode    CHAR(4)     NOT NULL REFERENCES postcode(postcode),
    present_detail      VARCHAR(200) NOT NULL,
    permanent_postcode  CHAR(4)     NOT NULL REFERENCES postcode(postcode),
    permanent_detail    VARCHAR(200) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- At least one guardian (parent or local) must be present.
    CONSTRAINT chk_student_has_guardian CHECK (
        father_nid IS NOT NULL OR mother_nid IS NOT NULL OR local_guardian_nid IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS application (
    application_id    VARCHAR(20) PRIMARY KEY,
    bc_no             VARCHAR(20) NOT NULL REFERENCES student(bc_no),
    applying_postcode CHAR(4)     NOT NULL REFERENCES postcode(postcode),
    desired_class     INT         NOT NULL REFERENCES class_eligibility(class_level),
    prev_school_name  VARCHAR(120),
    status            application_status_t NOT NULL DEFAULT 'SUBMITTED',
    round             INT         NOT NULL DEFAULT 1,
    submitted_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Up to 5 ordered choices, each pointing at a concrete seat row.
CREATE TABLE IF NOT EXISTS application_choice (
    choice_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id VARCHAR(20) NOT NULL REFERENCES application(application_id) ON DELETE CASCADE,
    seat_id        VARCHAR(20) NOT NULL REFERENCES seat(seat_id),
    preference     INT         NOT NULL CHECK (preference BETWEEN 1 AND 5),
    UNIQUE (application_id, preference),
    UNIQUE (application_id, seat_id)
);

-- A choice may claim MULTIPLE quotas (e.g. both Area and Freedom Fighter). The
-- lottery considers the applicant for that seat under each claimed quota in
-- priority order. This makes "multiple quota per choice" data-driven.
CREATE TABLE IF NOT EXISTS choice_quota (
    choice_id  BIGINT      NOT NULL REFERENCES application_choice(choice_id) ON DELETE CASCADE,
    quota_code VARCHAR(20) NOT NULL REFERENCES quota_type(code),
    ref_id     VARCHAR(20) REFERENCES quota_reference(ref_id),
    PRIMARY KEY (choice_id, quota_code)
);

CREATE INDEX IF NOT EXISTS idx_application_bc       ON application(bc_no);
CREATE INDEX IF NOT EXISTS idx_application_status   ON application(status);
CREATE INDEX IF NOT EXISTS idx_choice_application   ON application_choice(application_id);
CREATE INDEX IF NOT EXISTS idx_choice_seat          ON application_choice(seat_id);
CREATE INDEX IF NOT EXISTS idx_choice_quota_code    ON choice_quota(quota_code);
