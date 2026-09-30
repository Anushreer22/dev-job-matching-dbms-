-- ============================================================================
-- Dev Job and Skill-Matching Platform
-- Script: 06_queries.sql
-- Description: 12 analytical, reporting, and operational queries demonstrating
--              complex joins, window functions, CTEs, aggregation with HAVING,
--              subqueries with EXISTS, and recruitment intelligence.
-- Engine: PostgreSQL 12+
-- ============================================================================


-- ============================================================================
-- 1. TOP 3 CANDIDATES PER OPENING (WINDOW FUNCTION)
-- Description: Ranks and filters the top 3 highest-matching candidates for every open job opening using DENSE_RANK().
-- ============================================================================
WITH ranked_matches AS (
    SELECT 
        o.opening_id,
        o.title AS opening_title,
        comp.company_name,
        c.candidate_id,
        c.name AS candidate_name,
        c.total_experience_yrs,
        ms.score,
        DENSE_RANK() OVER (
            PARTITION BY o.opening_id 
            ORDER BY ms.score DESC, c.total_experience_yrs DESC, c.candidate_id ASC
        ) AS rank_position
    FROM opening o
    JOIN company comp ON o.company_id = comp.company_id
    JOIN v_match_scores ms ON o.opening_id = ms.opening_id
    JOIN candidate c ON ms.candidate_id = c.candidate_id
    WHERE o.status = 'OPEN'
)
SELECT 
    opening_id,
    opening_title,
    company_name,
    rank_position,
    candidate_id,
    candidate_name,
    total_experience_yrs,
    score
FROM ranked_matches
WHERE rank_position <= 3
ORDER BY opening_id ASC, rank_position ASC;


-- ============================================================================
-- 2. MOST IN-DEMAND SKILLS
-- Description: Identifies the technical skills most frequently required across all job openings along with average required levels.
-- ============================================================================
SELECT 
    s.skill_id,
    s.skill_name,
    s.category,
    COUNT(os.opening_id) AS openings_requiring_skill,
    ROUND(AVG(os.required_level), 2) AS avg_required_proficiency,
    ROUND(AVG(os.weight), 2) AS avg_skill_weight
FROM skill s
JOIN opening_skill os ON s.skill_id = os.skill_id
GROUP BY s.skill_id, s.skill_name, s.category
ORDER BY openings_requiring_skill DESC, avg_skill_weight DESC, s.skill_name ASC
LIMIT 10;


-- ============================================================================
-- 3. SKILL GAP ANALYSIS
-- Description: Pinpoints market skill shortages where employer opening demand exceeds candidate talent supply.
-- ============================================================================
SELECT 
    s.skill_id,
    s.skill_name,
    s.category,
    COUNT(DISTINCT os.opening_id) AS openings_demanding_skill,
    COUNT(DISTINCT cs.candidate_id) AS candidates_possessing_skill,
    (COUNT(DISTINCT os.opening_id) - COUNT(DISTINCT cs.candidate_id)) AS supply_deficit
FROM skill s
JOIN opening_skill os ON s.skill_id = os.skill_id
LEFT JOIN candidate_skill cs ON s.skill_id = cs.skill_id
GROUP BY s.skill_id, s.skill_name, s.category
HAVING COUNT(DISTINCT os.opening_id) > COUNT(DISTINCT cs.candidate_id)
ORDER BY supply_deficit DESC, openings_demanding_skill DESC;


-- ============================================================================
-- 4. AVERAGE EXPECTED SALARY BY SKILL
-- Description: Computes the average expected compensation and average experience of candidates proficient in each skill.
-- ============================================================================
SELECT 
    s.skill_id,
    s.skill_name,
    s.category,
    COUNT(cs.candidate_id) AS qualified_developers_count,
    ROUND(AVG(c.expected_salary), 2) AS avg_expected_salary,
    ROUND(AVG(c.total_experience_yrs), 1) AS avg_experience_yrs
FROM skill s
JOIN candidate_skill cs ON s.skill_id = cs.skill_id
JOIN candidate c ON cs.candidate_id = c.candidate_id
GROUP BY s.skill_id, s.skill_name, s.category
HAVING COUNT(cs.candidate_id) >= 3
ORDER BY avg_expected_salary DESC;


-- ============================================================================
-- 5. CANDIDATES WITH NO APPLICATIONS
-- Description: Retrieves registered developers who currently have zero submitted job applications on the platform.
-- ============================================================================
SELECT 
    c.candidate_id,
    c.name AS candidate_name,
    c.email,
    c.location,
    c.total_experience_yrs,
    c.expected_salary
FROM candidate c
LEFT JOIN application a ON c.candidate_id = a.candidate_id
WHERE a.application_id IS NULL
ORDER BY c.total_experience_yrs DESC;


-- ============================================================================
-- 6. OPENINGS WITH NO APPLICANTS
-- Description: Lists active OPEN job positions that have received zero candidate applications.
-- ============================================================================
SELECT 
    o.opening_id,
    o.title AS opening_title,
    comp.company_name,
    comp.city,
    o.min_experience_yrs,
    o.salary_min,
    o.salary_max,
    o.posted_on
FROM opening o
JOIN company comp ON o.company_id = comp.company_id
LEFT JOIN application a ON o.opening_id = a.opening_id
WHERE o.status = 'OPEN' 
  AND a.application_id IS NULL
ORDER BY o.posted_on ASC;


-- ============================================================================
-- 7. COMPANIES RANKED BY NUMBER OF OPENINGS
-- Description: Ranks employer companies by total job postings using DENSE_RANK(), distinguishing active vs total positions.
-- ============================================================================
SELECT 
    c.company_id,
    c.company_name,
    c.industry,
    c.city,
    COUNT(o.opening_id) AS total_openings,
    COUNT(CASE WHEN o.status = 'OPEN' THEN 1 END) AS active_openings,
    DENSE_RANK() OVER (ORDER BY COUNT(o.opening_id) DESC) AS company_rank
FROM company c
LEFT JOIN opening o ON c.company_id = o.company_id
GROUP BY c.company_id, c.company_name, c.industry, c.city
ORDER BY company_rank ASC, total_openings DESC, c.company_name ASC;


-- ============================================================================
-- 8. CANDIDATES MATCHING AN OPENING ABOVE 80%
-- Description: Finds all developer and job opening pairs with a quantified skill match compatibility score of 80% or greater.
-- ============================================================================
SELECT 
    ms.opening_id,
    ms.opening_title,
    ms.company_name,
    ms.candidate_id,
    ms.candidate_name,
    ms.candidate_experience_yrs,
    ms.expected_salary,
    ms.score AS match_percentage
FROM v_match_scores ms
WHERE ms.score >= 80.00
ORDER BY ms.score DESC, ms.opening_id ASC, ms.candidate_name ASC;


-- ============================================================================
-- 9. CANDIDATE SHORTLIST CONVERSION RATES PER COMPANY (USING A CTE)
-- Description: Uses a Common Table Expression to aggregate application pipelines and shortlist/hire conversion rates per employer.
-- ============================================================================
WITH company_pipeline AS (
    SELECT 
        c.company_id,
        c.company_name,
        COUNT(a.application_id) AS total_applications_received,
        COUNT(CASE WHEN a.status IN ('SHORTLISTED', 'INTERVIEW_SCHEDULED', 'ACCEPTED', 'HIRED') THEN 1 END) AS candidates_advanced,
        COUNT(CASE WHEN a.status = 'REJECTED' THEN 1 END) AS candidates_rejected
    FROM company c
    JOIN opening o ON c.company_id = o.company_id
    JOIN application a ON o.opening_id = a.opening_id
    GROUP BY c.company_id, c.company_name
)
SELECT 
    company_name,
    total_applications_received,
    candidates_advanced,
    candidates_rejected,
    ROUND(
        (candidates_advanced::numeric / NULLIF(total_applications_received, 0)) * 100.0, 
        2
    ) AS advancement_rate_pct
FROM company_pipeline
ORDER BY advancement_rate_pct DESC, total_applications_received DESC;


-- ============================================================================
-- 10. CANDIDATES APPLYING FOR SENIOR/LEAD ROLES (USING SUBQUERY WITH EXISTS)
-- Description: Uses an EXISTS subquery to find candidates who have applied for at least one Senior or Lead engineering role.
-- ============================================================================
SELECT 
    c.candidate_id,
    c.name AS candidate_name,
    c.email,
    c.location,
    c.total_experience_yrs,
    c.expected_salary
FROM candidate c
WHERE EXISTS (
    SELECT 1 
    FROM application a
    JOIN opening o ON a.opening_id = o.opening_id
    WHERE a.candidate_id = c.candidate_id
      AND (o.title ILIKE '%Senior%' OR o.title ILIKE '%Lead%' OR o.title ILIKE '%Architect%')
)
ORDER BY c.total_experience_yrs DESC;


-- ============================================================================
-- 11. DIVERSE MULTI-DISCIPLINARY CANDIDATES (GROUP BY WITH HAVING)
-- Description: Uses GROUP BY with a compound HAVING clause to filter candidates holding 5+ skills across at least 3 categories.
-- ============================================================================
SELECT 
    c.candidate_id,
    c.name AS candidate_name,
    c.total_experience_yrs,
    c.expected_salary,
    COUNT(cs.skill_id) AS total_skills_held,
    COUNT(DISTINCT s.category) AS distinct_categories_count,
    ROUND(AVG(cs.proficiency), 2) AS avg_skill_proficiency
FROM candidate c
JOIN candidate_skill cs ON c.candidate_id = cs.candidate_id
JOIN skill s ON cs.skill_id = s.skill_id
GROUP BY c.candidate_id, c.name, c.total_experience_yrs, c.expected_salary
HAVING COUNT(cs.skill_id) >= 5 
   AND COUNT(DISTINCT s.category) >= 3
ORDER BY distinct_categories_count DESC, total_skills_held DESC, avg_skill_proficiency DESC;


-- ============================================================================
-- 12. APPLICATION SUBMISSION VELOCITY (USING ROW_NUMBER AND LAG)
-- Description: Uses ROW_NUMBER() and LAG() window functions to sequence applications chronologically and track submission intervals.
-- ============================================================================
WITH sequenced_applications AS (
    SELECT 
        a.application_id,
        o.opening_id,
        o.title AS opening_title,
        c.name AS candidate_name,
        a.applied_on,
        a.status AS current_status,
        ROW_NUMBER() OVER (
            PARTITION BY o.opening_id 
            ORDER BY a.applied_on ASC, a.application_id ASC
        ) AS applicant_order,
        LAG(a.applied_on) OVER (
            PARTITION BY o.opening_id 
            ORDER BY a.applied_on ASC, a.application_id ASC
        ) AS previous_application_timestamp
    FROM application a
    JOIN opening o ON a.opening_id = o.opening_id
    JOIN candidate c ON a.candidate_id = c.candidate_id
)
SELECT 
    opening_id,
    opening_title,
    applicant_order,
    candidate_name,
    applied_on,
    previous_application_timestamp,
    ROUND(
        EXTRACT(EPOCH FROM (applied_on - previous_application_timestamp)) / 3600.0, 
        1
    ) AS hours_since_last_application,
    current_status
FROM sequenced_applications
ORDER BY opening_id ASC, applicant_order ASC;
