-- ============================================================================
-- Dev Job and Skill-Matching Platform
-- Script: 04_triggers.sql
-- Description: PostgreSQL trigger functions and triggers for business rule
--              enforcement, status audit logging, and automated match score
--              re-computation.
-- Engine: PostgreSQL 12+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Teardown triggers and functions for clean re-runnability
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_check_opening_status_before_apply ON application;
DROP TRIGGER IF EXISTS trg_audit_application_status ON application;
DROP TRIGGER IF EXISTS trg_candidate_skill_match_sync ON candidate_skill;
DROP TRIGGER IF EXISTS trg_opening_skill_match_sync ON opening_skill;

DROP FUNCTION IF EXISTS trg_prevent_application_closed_opening() CASCADE;
DROP FUNCTION IF EXISTS trg_log_application_status_change() CASCADE;
DROP FUNCTION IF EXISTS trg_candidate_skill_refresh_match() CASCADE;
DROP FUNCTION IF EXISTS trg_opening_skill_refresh_match() CASCADE;


-- ============================================================================
-- 1. TRIGGER: Block application if opening status is CLOSED
-- Purpose:
--   Ensures business integrity by preventing candidates from applying to job
--   openings that are CLOSED. Raises an exception before insert or update.
-- ============================================================================
CREATE OR REPLACE FUNCTION trg_prevent_application_closed_opening()
RETURNS TRIGGER AS $$
DECLARE
    v_opening_status VARCHAR(10);
BEGIN
    -- Query current status of target opening
    SELECT status INTO v_opening_status
    FROM opening
    WHERE opening_id = NEW.opening_id;

    -- If opening doesn't exist, let foreign key constraint handle it
    IF v_opening_status IS NULL THEN
        RETURN NEW;
    END IF;

    -- Enforce business rule: cannot apply to CLOSED openings
    IF v_opening_status = 'CLOSED' THEN
        RAISE EXCEPTION 'Application rejected: Job opening % is CLOSED.', NEW.opening_id
            USING ERRCODE = 'check_violation',
                  HINT = 'Candidates may only apply to openings with status OPEN.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_opening_status_before_apply
BEFORE INSERT OR UPDATE OF opening_id ON application
FOR EACH ROW
EXECUTE FUNCTION trg_prevent_application_closed_opening();

/*
-------------------------------------------------------------------------------
-- TEST SNIPPET 1: Block application for CLOSED opening
-------------------------------------------------------------------------------
-- Opening 14 ('Cloud Security & Compliance Engineer') is CLOSED in sample data.
-- The following insert MUST fail with an exception:

INSERT INTO application (candidate_id, opening_id, status)
VALUES (1, 14, 'APPLIED');

-- Expected output:
-- ERROR: Application rejected: Job opening 14 is CLOSED.
-- HINT: Candidates may only apply to openings with status OPEN.
-------------------------------------------------------------------------------
*/


-- ============================================================================
-- 2. TRIGGER: Log every application status change into application_audit
-- Purpose:
--   Monitors the candidate application lifecycle by capturing historical
--   transitions (e.g. APPLIED -> SHORTLISTED -> ACCEPTED) in application_audit.
-- ============================================================================
CREATE OR REPLACE FUNCTION trg_log_application_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Record audit entry whenever status changes
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO application_audit (application_id, old_status, new_status, changed_at)
        VALUES (NEW.application_id, OLD.status, NEW.status, CURRENT_TIMESTAMP);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_application_status
AFTER UPDATE OF status ON application
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION trg_log_application_status_change();

/*
-------------------------------------------------------------------------------
-- TEST SNIPPET 2: Audit log on application status change
-------------------------------------------------------------------------------
-- Step 1: Update status of application 2 from 'UNDER_REVIEW' to 'SHORTLISTED'
UPDATE application
SET status = 'SHORTLISTED'
WHERE application_id = 2;

-- Step 2: Verify audit record creation
SELECT audit_id, application_id, old_status, new_status, changed_at
FROM application_audit
WHERE application_id = 2
ORDER BY changed_at DESC;

-- Expected output:
-- Row showing application_id=2, old_status='UNDER_REVIEW', new_status='SHORTLISTED'
-------------------------------------------------------------------------------
*/


-- ============================================================================
-- 3. TRIGGER: Real-time match_score sync on candidate_skill & opening_skill changes
-- Purpose:
--   Keeps pre-computed match scores in match_score synchronized with real-time
--   skill additions, edits, or removals using the identical weighted formula:
--   score = 100 * SUM(weight * LEAST(COALESCE(proficiency,0)::numeric / required_level, 1)) / SUM(weight)
-- ============================================================================

-- Function 3A: Refresh match scores when candidate skills change
CREATE OR REPLACE FUNCTION trg_candidate_skill_refresh_match()
RETURNS TRIGGER AS $$
DECLARE
    v_cand_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_cand_id := OLD.candidate_id;
    ELSE
        v_cand_id := NEW.candidate_id;
    END IF;

    -- Recalculate match scores for this candidate across all active OPEN openings
    INSERT INTO match_score (candidate_id, opening_id, score, computed_at)
    SELECT 
        v_cand_id,
        o.opening_id,
        ROUND(
            100.0 * SUM(os.weight * LEAST(COALESCE(cs.proficiency, 0)::numeric / os.required_level, 1.0)) 
            / SUM(os.weight), 
            2
        ) AS score,
        CURRENT_TIMESTAMP
    FROM opening o
    JOIN opening_skill os ON o.opening_id = os.opening_id
    LEFT JOIN candidate_skill cs 
        ON cs.candidate_id = v_cand_id 
        AND os.skill_id = cs.skill_id
    WHERE o.status = 'OPEN'
    GROUP BY o.opening_id
    HAVING SUM(os.weight) > 0
    ON CONFLICT (candidate_id, opening_id)
    DO UPDATE SET 
        score = EXCLUDED.score,
        computed_at = EXCLUDED.computed_at;

    -- Handle candidate_id reassignment on UPDATE
    IF TG_OP = 'UPDATE' AND OLD.candidate_id <> NEW.candidate_id THEN
        INSERT INTO match_score (candidate_id, opening_id, score, computed_at)
        SELECT 
            OLD.candidate_id,
            o.opening_id,
            ROUND(
                100.0 * SUM(os.weight * LEAST(COALESCE(cs.proficiency, 0)::numeric / os.required_level, 1.0)) 
                / SUM(os.weight), 
                2
            ) AS score,
            CURRENT_TIMESTAMP
        FROM opening o
        JOIN opening_skill os ON o.opening_id = os.opening_id
        LEFT JOIN candidate_skill cs 
            ON cs.candidate_id = OLD.candidate_id 
            AND os.skill_id = cs.skill_id
        WHERE o.status = 'OPEN'
        GROUP BY o.opening_id
        HAVING SUM(os.weight) > 0
        ON CONFLICT (candidate_id, opening_id)
        DO UPDATE SET 
            score = EXCLUDED.score,
            computed_at = EXCLUDED.computed_at;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_candidate_skill_match_sync
AFTER INSERT OR UPDATE OR DELETE ON candidate_skill
FOR EACH ROW
EXECUTE FUNCTION trg_candidate_skill_refresh_match();


-- Function 3B: Refresh match scores when opening skills change
CREATE OR REPLACE FUNCTION trg_opening_skill_refresh_match()
RETURNS TRIGGER AS $$
DECLARE
    v_open_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_open_id := OLD.opening_id;
    ELSE
        v_open_id := NEW.opening_id;
    END IF;

    -- Only compute for OPEN positions
    IF EXISTS (SELECT 1 FROM opening WHERE opening_id = v_open_id AND status = 'OPEN') THEN
        IF EXISTS (SELECT 1 FROM opening_skill WHERE opening_id = v_open_id) THEN
            -- Recompute for all candidates against this opening
            INSERT INTO match_score (candidate_id, opening_id, score, computed_at)
            SELECT 
                c.candidate_id,
                v_open_id,
                ROUND(
                    100.0 * SUM(os.weight * LEAST(COALESCE(cs.proficiency, 0)::numeric / os.required_level, 1.0)) 
                    / SUM(os.weight), 
                    2
                ) AS score,
                CURRENT_TIMESTAMP
            FROM candidate c
            CROSS JOIN opening_skill os
            LEFT JOIN candidate_skill cs 
                ON c.candidate_id = cs.candidate_id 
                AND os.skill_id = cs.skill_id
            WHERE os.opening_id = v_open_id
            GROUP BY c.candidate_id
            HAVING SUM(os.weight) > 0
            ON CONFLICT (candidate_id, opening_id)
            DO UPDATE SET 
                score = EXCLUDED.score,
                computed_at = EXCLUDED.computed_at;
        ELSE
            -- If all skills removed for opening, clear match_score entries
            DELETE FROM match_score WHERE opening_id = v_open_id;
        END IF;
    END IF;

    -- Handle opening_id reassignment on UPDATE
    IF TG_OP = 'UPDATE' AND OLD.opening_id <> NEW.opening_id THEN
        IF EXISTS (SELECT 1 FROM opening WHERE opening_id = OLD.opening_id AND status = 'OPEN') THEN
            IF EXISTS (SELECT 1 FROM opening_skill WHERE opening_id = OLD.opening_id) THEN
                INSERT INTO match_score (candidate_id, opening_id, score, computed_at)
                SELECT 
                    c.candidate_id,
                    OLD.opening_id,
                    ROUND(
                        100.0 * SUM(os.weight * LEAST(COALESCE(cs.proficiency, 0)::numeric / os.required_level, 1.0)) 
                        / SUM(os.weight), 
                        2
                    ) AS score,
                    CURRENT_TIMESTAMP
                FROM candidate c
                CROSS JOIN opening_skill os
                LEFT JOIN candidate_skill cs 
                    ON c.candidate_id = cs.candidate_id 
                    AND os.skill_id = cs.skill_id
                WHERE os.opening_id = OLD.opening_id
                GROUP BY c.candidate_id
                HAVING SUM(os.weight) > 0
                ON CONFLICT (candidate_id, opening_id)
                DO UPDATE SET 
                    score = EXCLUDED.score,
                    computed_at = EXCLUDED.computed_at;
            ELSE
                DELETE FROM match_score WHERE opening_id = OLD.opening_id;
            END IF;
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_opening_skill_match_sync
AFTER INSERT OR UPDATE OR DELETE ON opening_skill
FOR EACH ROW
EXECUTE FUNCTION trg_opening_skill_refresh_match();

/*
-------------------------------------------------------------------------------
-- TEST SNIPPET 3: Automatic match_score sync on skill modifications
-------------------------------------------------------------------------------
-- Case A: Candidate acquires a new skill needed for Opening 1
-- Candidate 2 (Priya Sharma) has partial match (41.67%) for Opening 1.
-- Let's give Candidate 2 skill 13 (FastAPI) at proficiency 4:
INSERT INTO candidate_skill (candidate_id, skill_id, proficiency, years_used)
VALUES (2, 13, 4, 2.5)
ON CONFLICT (candidate_id, skill_id) DO UPDATE 
SET proficiency = 4, years_used = 2.5;

-- Check refreshed match score for Candidate 2 on Opening 1:
SELECT candidate_id, opening_id, score, computed_at
FROM match_score
WHERE candidate_id = 2 AND opening_id = 1;
-- Expected score: rises from 41.67% to 69.44% automatically!

-- Case B: Opening skill requirement modified
-- Update Opening 1's Docker skill (skill_id 24) weight to 3.0:
UPDATE opening_skill
SET weight = 3.00
WHERE opening_id = 1 AND skill_id = 24;

-- Check refreshed scores across candidates for Opening 1:
SELECT ms.candidate_id, c.name, ms.score, ms.computed_at
FROM match_score ms
JOIN candidate c ON ms.candidate_id = c.candidate_id
WHERE ms.opening_id = 1
ORDER BY ms.score DESC
LIMIT 5;
-------------------------------------------------------------------------------
*/
