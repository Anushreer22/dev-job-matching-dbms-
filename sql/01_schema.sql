-- ============================================================================
-- Dev Job and Skill-Matching Platform
-- Script: 01_schema.sql
-- Description: DDL definitions for tables, primary keys, foreign keys,
--              CHECK constraints, indexes, and table documentation comments.
-- Engine: PostgreSQL 12+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. TEARDOWN (Re-runnable script)
-- Drop existing tables in reverse dependency order
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS application_audit CASCADE;
DROP TABLE IF EXISTS match_score CASCADE;
DROP TABLE IF EXISTS application CASCADE;
DROP TABLE IF EXISTS opening_skill CASCADE;
DROP TABLE IF EXISTS opening CASCADE;
DROP TABLE IF EXISTS company CASCADE;
DROP TABLE IF EXISTS candidate_skill CASCADE;
DROP TABLE IF EXISTS skill CASCADE;
DROP TABLE IF EXISTS candidate CASCADE;

-- ----------------------------------------------------------------------------
-- 1. CANDIDATE
-- Stores developer profiles, contact info, total experience, and salary targets.
-- ----------------------------------------------------------------------------
CREATE TABLE candidate (
    candidate_id            SERIAL PRIMARY KEY,
    name                    VARCHAR(100) NOT NULL,
    email                   VARCHAR(150) NOT NULL UNIQUE,
    location                VARCHAR(100),
    total_experience_yrs    NUMERIC(4, 1) NOT NULL DEFAULT 0.0 CHECK (total_experience_yrs >= 0),
    expected_salary         NUMERIC(12, 2) CHECK (expected_salary >= 0),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_candidate_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

COMMENT ON TABLE candidate IS 'Stores software developer profiles, contact information, experience, and salary expectations.';
COMMENT ON COLUMN candidate.candidate_id IS 'Surrogate primary key for the candidate.';
COMMENT ON COLUMN candidate.email IS 'Unique contact email address for candidate communication and authentication.';
COMMENT ON COLUMN candidate.total_experience_yrs IS 'Cumulative professional software development experience in years (non-negative).';
COMMENT ON COLUMN candidate.expected_salary IS 'Annual expected compensation requested by the candidate.';

-- ----------------------------------------------------------------------------
-- 2. SKILL
-- Master taxonomy of technical skills, technologies, frameworks, and tools.
-- ----------------------------------------------------------------------------
CREATE TABLE skill (
    skill_id    SERIAL PRIMARY KEY,
    skill_name  VARCHAR(100) NOT NULL UNIQUE,
    category    VARCHAR(50) NOT NULL,
    CONSTRAINT chk_skill_name_not_blank CHECK (LENGTH(TRIM(skill_name)) > 0),
    CONSTRAINT chk_skill_category_not_blank CHECK (LENGTH(TRIM(category)) > 0)
);

COMMENT ON TABLE skill IS 'Master catalog of technical competencies, programming languages, frameworks, and developer tools.';
COMMENT ON COLUMN skill.skill_id IS 'Unique identifier for the skill.';
COMMENT ON COLUMN skill.skill_name IS 'Unique standardized skill name (e.g., PostgreSQL, Python, Docker).';
COMMENT ON COLUMN skill.category IS 'Domain category (e.g., language, framework, database, cloud, tool).';

-- ----------------------------------------------------------------------------
-- 3. CANDIDATE_SKILL (M:N)
-- Junction table mapping candidates to skills with proficiency ratings and years used.
-- ----------------------------------------------------------------------------
CREATE TABLE candidate_skill (
    candidate_id    INT NOT NULL,
    skill_id        INT NOT NULL,
    proficiency     INT NOT NULL CHECK (proficiency BETWEEN 1 AND 5),
    years_used      NUMERIC(4, 1) NOT NULL DEFAULT 0.0 CHECK (years_used >= 0),
    PRIMARY KEY (candidate_id, skill_id),
    CONSTRAINT fk_candidate_skill_candidate 
        FOREIGN KEY (candidate_id) 
        REFERENCES candidate (candidate_id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_candidate_skill_skill 
        FOREIGN KEY (skill_id) 
        REFERENCES skill (skill_id) 
        ON DELETE CASCADE
);

COMMENT ON TABLE candidate_skill IS 'M:N relationship linking candidates with their acquired skills, rating proficiency (1-5) and experience duration.';
COMMENT ON COLUMN candidate_skill.proficiency IS 'Self-assessed or verified skill level from 1 (Beginner) to 5 (Expert).';
COMMENT ON COLUMN candidate_skill.years_used IS 'Number of active years working with this specific skill/technology.';

-- ----------------------------------------------------------------------------
-- 4. COMPANY
-- Profiles hiring organizations, employer industry, and primary headquarters city.
-- ----------------------------------------------------------------------------
CREATE TABLE company (
    company_id      SERIAL PRIMARY KEY,
    company_name    VARCHAR(150) NOT NULL UNIQUE,
    industry        VARCHAR(100),
    city            VARCHAR(100),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE company IS 'Details of recruiting organizations, tech enterprises, and startups listing job openings.';
COMMENT ON COLUMN company.company_id IS 'Surrogate primary key for the employer company.';
COMMENT ON COLUMN company.company_name IS 'Official registered organization name.';

-- ----------------------------------------------------------------------------
-- 5. OPENING
-- Job postings advertised by companies, specifying compensation and experience baselines.
-- ----------------------------------------------------------------------------
CREATE TABLE opening (
    opening_id          SERIAL PRIMARY KEY,
    company_id          INT NOT NULL,
    title               VARCHAR(150) NOT NULL,
    min_experience_yrs  NUMERIC(4, 1) NOT NULL DEFAULT 0.0 CHECK (min_experience_yrs >= 0),
    salary_min          NUMERIC(12, 2) CHECK (salary_min >= 0),
    salary_max          NUMERIC(12, 2) CHECK (salary_max >= 0),
    status              VARCHAR(10) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'CLOSED')),
    posted_on           DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT fk_opening_company 
        FOREIGN KEY (company_id) 
        REFERENCES company (company_id) 
        ON DELETE CASCADE,
    CONSTRAINT chk_opening_salary_range 
        CHECK (salary_max IS NULL OR salary_min IS NULL OR salary_max >= salary_min)
);

COMMENT ON TABLE opening IS 'Individual developer job vacancies posted by companies with salary ranges and status.';
COMMENT ON COLUMN opening.opening_id IS 'Primary key identifying the job vacancy.';
COMMENT ON COLUMN opening.company_id IS 'Foreign key reference to the posting company.';
COMMENT ON COLUMN opening.status IS 'Availability status of the opening; restricted to OPEN or CLOSED.';
COMMENT ON COLUMN opening.posted_on IS 'Date the opening was formally advertised on the platform.';

-- ----------------------------------------------------------------------------
-- 6. OPENING_SKILL (M:N)
-- Junction table mapping job openings to required skills, proficiency levels, and weights.
-- ----------------------------------------------------------------------------
CREATE TABLE opening_skill (
    opening_id      INT NOT NULL,
    skill_id        INT NOT NULL,
    required_level  INT NOT NULL CHECK (required_level BETWEEN 1 AND 5),
    weight          NUMERIC(4, 2) NOT NULL DEFAULT 1.00 CHECK (weight > 0),
    PRIMARY KEY (opening_id, skill_id),
    CONSTRAINT fk_opening_skill_opening 
        FOREIGN KEY (opening_id) 
        REFERENCES opening (opening_id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_opening_skill_skill 
        FOREIGN KEY (skill_id) 
        REFERENCES skill (skill_id) 
        ON DELETE CASCADE
);

COMMENT ON TABLE opening_skill IS 'M:N relationship defining prerequisite skills for job openings with required proficiency (1-5) and weight.';
COMMENT ON COLUMN opening_skill.required_level IS 'Minimum required skill level on a scale from 1 (Novice) to 5 (Master).';
COMMENT ON COLUMN opening_skill.weight IS 'Relative importance/multiplier used in matching algorithms (must be > 0).';

-- ----------------------------------------------------------------------------
-- 7. APPLICATION
-- Tracks candidate applications for job openings, enforcing uniqueness per opening.
-- ----------------------------------------------------------------------------
CREATE TABLE application (
    application_id  SERIAL PRIMARY KEY,
    candidate_id    INT NOT NULL,
    opening_id      INT NOT NULL,
    applied_on      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status          VARCHAR(30) NOT NULL DEFAULT 'APPLIED' 
                    CHECK (status IN ('APPLIED', 'UNDER_REVIEW', 'SHORTLISTED', 'INTERVIEW_SCHEDULED', 'ACCEPTED', 'HIRED', 'REJECTED', 'WITHDRAWN')),
    CONSTRAINT uq_candidate_opening UNIQUE (candidate_id, opening_id),
    CONSTRAINT fk_application_candidate 
        FOREIGN KEY (candidate_id) 
        REFERENCES candidate (candidate_id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_application_opening 
        FOREIGN KEY (opening_id) 
        REFERENCES opening (opening_id) 
        ON DELETE CASCADE
);

COMMENT ON TABLE application IS 'Candidate job applications submitted for specific openings with lifecycle tracking.';
COMMENT ON COLUMN application.application_id IS 'Unique application identifier.';
COMMENT ON COLUMN application.status IS 'Current processing state of the candidate application.';

-- ----------------------------------------------------------------------------
-- 8. MATCH_SCORE
-- Computed algorithmic matching score between candidates and job openings.
-- ----------------------------------------------------------------------------
CREATE TABLE match_score (
    candidate_id    INT NOT NULL,
    opening_id      INT NOT NULL,
    score           NUMERIC(5, 2) NOT NULL CHECK (score >= 0 AND score <= 100),
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (candidate_id, opening_id),
    CONSTRAINT fk_match_score_candidate 
        FOREIGN KEY (candidate_id) 
        REFERENCES candidate (candidate_id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_match_score_opening 
        FOREIGN KEY (opening_id) 
        REFERENCES opening (opening_id) 
        ON DELETE CASCADE
);

COMMENT ON TABLE match_score IS 'Precomputed/cached skill-match compatibility percentage (0.00-100.00%) between candidates and openings.';
COMMENT ON COLUMN match_score.score IS 'Normalized match percentage score between 0 and 100.';
COMMENT ON COLUMN match_score.computed_at IS 'Timestamp of when the score was evaluated or refreshed.';

-- ----------------------------------------------------------------------------
-- 9. APPLICATION_AUDIT
-- Historical audit trail tracking application status transitions for compliance and analytics.
-- ----------------------------------------------------------------------------
CREATE TABLE application_audit (
    audit_id        SERIAL PRIMARY KEY,
    application_id  INT,
    old_status      VARCHAR(30),
    new_status      VARCHAR(30) NOT NULL,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_application_audit_application 
        FOREIGN KEY (application_id) 
        REFERENCES application (application_id) 
        ON DELETE SET NULL
);

COMMENT ON TABLE application_audit IS 'Audit log of application status changes triggered automatically upon status modifications.';
COMMENT ON COLUMN application_audit.audit_id IS 'Unique sequential audit entry ID.';
COMMENT ON COLUMN application_audit.old_status IS 'Previous application status prior to modification.';
COMMENT ON COLUMN application_audit.new_status IS 'New application status updated in the application record.';
COMMENT ON COLUMN application_audit.changed_at IS 'Timestamp when the status transition occurred.';

-- ----------------------------------------------------------------------------
-- 10. FOREIGN KEY & PERFORMANCE INDEXES
-- Indexing foreign keys and query filters to optimize join and search performance.
-- ----------------------------------------------------------------------------
CREATE INDEX idx_candidate_skill_skill_id ON candidate_skill (skill_id);
CREATE INDEX idx_opening_company_id ON opening (company_id);
CREATE INDEX idx_opening_status ON opening (status);
CREATE INDEX idx_opening_skill_skill_id ON opening_skill (skill_id);
CREATE INDEX idx_application_candidate_id ON application (candidate_id);
CREATE INDEX idx_application_opening_id ON application (opening_id);
CREATE INDEX idx_application_status ON application (status);
CREATE INDEX idx_match_score_opening_score ON match_score (opening_id, score DESC);
CREATE INDEX idx_application_audit_app_id ON application_audit (application_id);

