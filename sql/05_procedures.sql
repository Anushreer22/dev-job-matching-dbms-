-- ============================================================================
-- Dev Job and Skill-Matching Platform
-- Script: 05_procedures.sql
-- Description: Stored functions and procedures for candidate ranking queries,
--              atomic transactional hiring workflows, and batch match score
--              re-computations.
-- Engine: PostgreSQL 12+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Teardown routines for clean re-runnability
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_top_candidates(INT, INT);
DROP PROCEDURE IF EXISTS hire_candidate(INT);
DROP FUNCTION IF EXISTS recompute_all_match_scores();


-- ============================================================================
-- 1. FUNCTION: get_top_candidates
-- Purpose:
--   Returns the top N candidate matches for a given job opening, ordered by
--   highest match score and rank.
-- Parameters:
--   - p_opening_id (INT): Identifier of the target job opening.
--   - p_n (INT): Maximum number of ranked candidates to return (default 5).
-- Returns:
--   TABLE containing candidate_id, candidate_name, score, and candidate_rank.
-- ============================================================================
CREATE OR REPLACE FUNCTION get_top_candidates(
    p_opening_id INT,
    p_n INT DEFAULT 5
)
RETURNS TABLE (
    candidate_id    INT,
    candidate_name  VARCHAR(100),
    score           NUMERIC(5, 2),
    candidate_rank  BIGINT
) AS $$
BEGIN
    -- 1. Validate opening exists
    IF NOT EXISTS (SELECT 1 FROM opening WHERE opening.opening_id = p_opening_id) THEN
        RAISE EXCEPTION 'Opening ID % does not exist.', p_opening_id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 2. Validate p_n is positive
    IF p_n <= 0 THEN
        RAISE EXCEPTION 'Result limit parameter p_n must be greater than 0, got %.', p_n
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 3. Return ranked candidates for the specified opening
    RETURN QUERY
    SELECT 
        tc.candidate_id,
        tc.candidate_name,
        tc.score,
        tc.candidate_rank
    FROM v_top_candidates tc
    WHERE tc.opening_id = p_opening_id
      AND tc.candidate_rank <= p_n
    ORDER BY tc.candidate_rank ASC, tc.score DESC, tc.candidate_id ASC;
END;
$$ LANGUAGE plpgsql;

/*
-------------------------------------------------------------------------------
-- EXAMPLE CALL / SELECT: get_top_candidates
-------------------------------------------------------------------------------
-- Retrieve the top 5 developer matches for Opening 1 (Senior Backend Engineer):
SELECT candidate_name, score, candidate_rank
FROM get_top_candidates(1, 5);

-- Retrieve top 3 matches for Opening 2:
SELECT candidate_name, score, candidate_rank
FROM get_top_candidates(2, 3);
-------------------------------------------------------------------------------
*/


-- ============================================================================
-- 2. PROCEDURE: hire_candidate
-- Purpose:
--   Executes an atomic hiring workflow within a single transaction:
--     1. Validates that the application exists and the job opening is OPEN.
--     2. Updates the target application's status to 'HIRED'.
--     3. Updates the associated opening's status to 'CLOSED'.
--     4. Updates all competing applications for that opening to 'REJECTED'.
--   Triggers on the application table will automatically log these status changes
--   into application_audit.
-- Parameters:
--   - p_application_id (INT): ID of the application selected for hire.
-- Error Handling:
--   Raises descriptive exceptions and rolls back changes if the application
--   is missing, already finalized, or the opening is already closed.
-- ============================================================================
CREATE OR REPLACE PROCEDURE hire_candidate(p_application_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_opening_id        INT;
    v_candidate_id      INT;
    v_app_status        VARCHAR(30);
    v_opening_status    VARCHAR(10);
    v_candidate_name    VARCHAR(100);
    v_opening_title     VARCHAR(150);
    v_rejected_count    INT := 0;
BEGIN
    -- 1. Fetch application details
    SELECT 
        a.opening_id, 
        a.candidate_id, 
        a.status,
        c.name,
        o.title,
        o.status
    INTO 
        v_opening_id, 
        v_candidate_id, 
        v_app_status,
        v_candidate_name,
        v_opening_title,
        v_opening_status
    FROM application a
    JOIN candidate c ON a.candidate_id = c.candidate_id
    JOIN opening o ON a.opening_id = o.opening_id
    WHERE a.application_id = p_application_id;

    -- Validate existence
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application ID % does not exist.', p_application_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Validate opening is OPEN
    IF v_opening_status = 'CLOSED' THEN
        RAISE EXCEPTION 'Cannot hire: Job opening % ("%") is already CLOSED.', 
            v_opening_id, v_opening_title
            USING ERRCODE = 'check_violation';
    END IF;

    -- Validate application is eligible for hire
    IF v_app_status = 'HIRED' THEN
        RAISE NOTICE 'Application % for "%" is already marked as HIRED.', 
            p_application_id, v_candidate_name;
        RETURN;
    END IF;

    IF v_app_status IN ('REJECTED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'Cannot hire: Application % is currently in "%" state.', 
            p_application_id, v_app_status
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2. Mark target application as 'HIRED'
    UPDATE application
    SET status = 'HIRED'
    WHERE application_id = p_application_id;

    -- 3. Close the opening
    UPDATE opening
    SET status = 'CLOSED'
    WHERE opening_id = v_opening_id;

    -- 4. Mark all other competing active applications for this opening as 'REJECTED'
    UPDATE application
    SET status = 'REJECTED'
    WHERE opening_id = v_opening_id
      AND application_id <> p_application_id
      AND status NOT IN ('REJECTED', 'WITHDRAWN');

    GET DIAGNOSTICS v_rejected_count = ROW_COUNT;

    RAISE NOTICE 'Hiring workflow completed successfully:';
    RAISE NOTICE ' - Application % ("%") marked as HIRED.', p_application_id, v_candidate_name;
    RAISE NOTICE ' - Opening % ("%") changed to CLOSED.', v_opening_id, v_opening_title;
    RAISE NOTICE ' - % competing application(s) updated to REJECTED.', v_rejected_count;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'hire_candidate transaction rolled back for application %: % (SQLSTATE %)', 
            p_application_id, SQLERRM, SQLSTATE;
END;
$$;

/*
-------------------------------------------------------------------------------
-- EXAMPLE CALL: hire_candidate
-------------------------------------------------------------------------------
-- Step 1: Execute hire procedure for application 1 (Alex Rivera for Opening 1)
CALL hire_candidate(1);

-- Step 2: Verify application 1 is HIRED and competing applications are REJECTED
SELECT application_id, candidate_id, opening_id, status
FROM application
WHERE opening_id = 1;

-- Step 3: Verify opening 1 is now CLOSED
SELECT opening_id, title, status
FROM opening
WHERE opening_id = 1;

-- Step 4: Verify automated audit log entries generated by triggers
SELECT audit_id, application_id, old_status, new_status, changed_at
FROM application_audit
WHERE application_id IN (SELECT application_id FROM application WHERE opening_id = 1)
ORDER BY changed_at DESC;
-------------------------------------------------------------------------------
*/


-- ============================================================================
-- 3. FUNCTION: recompute_all_match_scores
-- Purpose:
--   Full batch rebuild of the match_score table across all candidates and all
--   currently OPEN job openings. Uses the canonical weighted match formula:
--   score = 100 * SUM(weight * LEAST(COALESCE(proficiency,0)::numeric / required_level, 1)) / SUM(weight)
-- Returns:
--   INT: Number of match_score records computed and stored.
-- ============================================================================
CREATE OR REPLACE FUNCTION recompute_all_match_scores()
RETURNS INT AS $$
DECLARE
    v_total_rows INT := 0;
BEGIN
    -- 1. Wipe existing pre-computed match scores
    DELETE FROM match_score;

    -- 2. Bulk compute and populate match scores for all candidates against all OPEN openings
    INSERT INTO match_score (candidate_id, opening_id, score, computed_at)
    SELECT 
        c.candidate_id,
        o.opening_id,
        ROUND(
            100.0 * SUM(os.weight * LEAST(COALESCE(cs.proficiency, 0)::numeric / os.required_level, 1.0)) 
            / SUM(os.weight), 
            2
        ) AS score,
        CURRENT_TIMESTAMP
    FROM candidate c
    CROSS JOIN opening o
    JOIN opening_skill os ON o.opening_id = os.opening_id
    LEFT JOIN candidate_skill cs 
        ON c.candidate_id = cs.candidate_id 
        AND os.skill_id = cs.skill_id
    WHERE o.status = 'OPEN'
    GROUP BY c.candidate_id, o.opening_id
    HAVING SUM(os.weight) > 0;

    -- 3. Capture count of populated records
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;

    RETURN v_total_rows;
END;
$$ LANGUAGE plpgsql;

/*
-------------------------------------------------------------------------------
-- EXAMPLE CALL / SELECT: recompute_all_match_scores
-------------------------------------------------------------------------------
-- Rebuild and populate the entire match_score table:
SELECT recompute_all_match_scores() AS scores_computed;

-- Verify computed scores stored in match_score:
SELECT ms.candidate_id, c.name, ms.opening_id, o.title, ms.score, ms.computed_at
FROM match_score ms
JOIN candidate c ON ms.candidate_id = c.candidate_id
JOIN opening o ON ms.opening_id = o.opening_id
ORDER BY ms.score DESC
LIMIT 10;
-------------------------------------------------------------------------------
*/
