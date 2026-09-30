-- ============================================================================
-- Dev Job and Skill-Matching Platform
-- Script: 03_views.sql
-- Description: Analytical, reporting, and ranking views for candidate matching,
--              skill demand analytics, and recruitment pipeline monitoring.
-- Engine: PostgreSQL 12+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Teardown views to ensure clean re-runnability
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS v_top_candidates CASCADE;
DROP VIEW IF EXISTS v_match_scores CASCADE;
DROP VIEW IF EXISTS v_skill_demand CASCADE;
DROP VIEW IF EXISTS v_open_positions_summary CASCADE;

-- ----------------------------------------------------------------------------
-- 1. VIEW: v_match_scores
-- Purpose:
--   Calculates the quantified skill-matching compatibility score (0.00 to 100.00)
--   for every candidate against all OPEN job openings.
--
-- Formula:
--   score = 100 * SUM(weight * LEAST(COALESCE(proficiency, 0)::numeric / required_level, 1)) / SUM(weight)
--
-- Logic:
--   - For each required skill in an opening, candidate proficiency is capped at
--     100% of the required level (using LEAST(..., 1)).
--   - Missing skills default to 0 proficiency via COALESCE.
--   - Contributions are scaled by skill weight and normalized against total weight.
--   - Rounded to 2 decimal places.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_match_scores AS
SELECT 
    c.candidate_id,
    c.name AS candidate_name,
    c.total_experience_yrs AS candidate_experience_yrs,
    c.expected_salary,
    o.opening_id,
    o.title AS opening_title,
    comp.company_id,
    comp.company_name,
    o.min_experience_yrs AS opening_min_experience_yrs,
    o.salary_min,
    o.salary_max,
    ROUND(
        100.0 * SUM(os.weight * LEAST(COALESCE(cs.proficiency, 0)::numeric / os.required_level, 1.0)) 
        / SUM(os.weight), 
        2
    ) AS score
FROM candidate c
CROSS JOIN opening o
JOIN company comp ON o.company_id = comp.company_id
JOIN opening_skill os ON o.opening_id = os.opening_id
LEFT JOIN candidate_skill cs ON c.candidate_id = cs.candidate_id AND os.skill_id = cs.skill_id
WHERE o.status = 'OPEN'
GROUP BY 
    c.candidate_id, 
    c.name, 
    c.total_experience_yrs, 
    c.expected_salary, 
    o.opening_id, 
    o.title, 
    comp.company_id, 
    comp.company_name, 
    o.min_experience_yrs, 
    o.salary_min, 
    o.salary_max;

-- ----------------------------------------------------------------------------
-- 2. VIEW: v_top_candidates
-- Purpose:
--   Ranks candidates for each active OPEN job opening using the SQL window
--   function RANK() OVER (PARTITION BY opening_id ORDER BY score DESC).
--   Enables recruiters to immediately surface top developer matches per position.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_top_candidates AS
SELECT 
    opening_id,
    opening_title,
    company_name,
    candidate_id,
    candidate_name,
    candidate_experience_yrs,
    expected_salary,
    score,
    RANK() OVER (
        PARTITION BY opening_id 
        ORDER BY score DESC
    ) AS candidate_rank
FROM v_match_scores;

-- ----------------------------------------------------------------------------
-- 3. VIEW: v_skill_demand
-- Purpose:
--   Analyzes tech industry hiring demand by computing the number of job
--   openings requiring each technical skill across all categories.
--   Aids in identifying high-demand technologies and skill market trends.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_skill_demand AS
SELECT 
    s.skill_id,
    s.skill_name,
    s.category,
    COUNT(os.opening_id) AS openings_count,
    COUNT(CASE WHEN o.status = 'OPEN' THEN 1 END) AS open_openings_count
FROM skill s
LEFT JOIN opening_skill os ON s.skill_id = os.skill_id
LEFT JOIN opening o ON os.opening_id = o.opening_id
GROUP BY s.skill_id, s.skill_name, s.category
ORDER BY openings_count DESC, s.skill_name ASC;

-- ----------------------------------------------------------------------------
-- 4. VIEW: v_open_positions_summary
-- Purpose:
--   Provides an executive recruitment summary of all currently active (OPEN)
--   job openings, including hiring company information, compensation package,
--   experience requirements, and the total count of submitted candidate applications.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_open_positions_summary AS
SELECT 
    o.opening_id,
    o.title AS opening_title,
    c.company_id,
    c.company_name,
    c.city AS company_city,
    o.min_experience_yrs,
    o.salary_min,
    o.salary_max,
    o.status,
    o.posted_on,
    COUNT(a.application_id) AS applicant_count
FROM opening o
JOIN company c ON o.company_id = c.company_id
LEFT JOIN application a ON o.opening_id = a.opening_id
WHERE o.status = 'OPEN'
GROUP BY 
    o.opening_id, 
    o.title, 
    c.company_id, 
    c.company_name, 
    c.city, 
    o.min_experience_yrs, 
    o.salary_min, 
    o.salary_max, 
    o.status,
    o.posted_on
ORDER BY applicant_count DESC, o.opening_id ASC;
