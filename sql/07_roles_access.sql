-- ============================================================================
-- Dev Job and Skill-Matching Platform
-- Script: 07_roles_access.sql
-- Description: Role-Based Access Control (RBAC) security configuration.
--              Defines roles (admin_role, recruiter_role, candidate_role)
--              with granular table, view, sequence, and routine privileges.
-- Engine: PostgreSQL 12+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ROLE INITIALIZATION
-- Safely create database roles if they do not already exist.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_role') THEN
        CREATE ROLE admin_role WITH NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'recruiter_role') THEN
        CREATE ROLE recruiter_role WITH NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'candidate_role') THEN
        CREATE ROLE candidate_role WITH NOLOGIN;
    END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 2. PRIVILEGE RESET (Idempotency)
-- Revoke existing permissions to ensure a clean, deterministic baseline.
-- ----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM admin_role, recruiter_role, candidate_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM admin_role, recruiter_role, candidate_role;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM admin_role, recruiter_role, candidate_role;

-- Ensure schema usage is permitted for all three roles
GRANT USAGE ON SCHEMA public TO admin_role, recruiter_role, candidate_role;


-- ============================================================================
-- 3. ADMIN ROLE (admin_role)
-- Privileges:
--   Full administrative access across all tables, views, sequences,
--   and functions/procedures in the database.
-- ============================================================================
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin_role;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO admin_role;

-- Automatically grant privileges on future objects created in schema public
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO admin_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO admin_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO admin_role;


-- ============================================================================
-- 4. RECRUITER ROLE (recruiter_role)
-- Privileges:
--   - Read-only (SELECT) access to developer profiles and analytics:
--       candidate, candidate_skill, skill, match_score, and all views.
--   - Full read/write (SELECT, INSERT, UPDATE, DELETE) access on recruitment
--     management entities: opening, opening_skill, and application.
--   - USAGE on sequences associated with job openings and applications.
--   - EXECUTE permissions on recruiter workflows (get_top_candidates, hire_candidate).
-- ============================================================================

-- A. Read-only permissions on candidate profiles and taxonomy
GRANT SELECT ON candidate, candidate_skill, skill, match_score TO recruiter_role;

-- B. Read-only permissions on reporting and analytical views
GRANT SELECT ON 
    v_match_scores, 
    v_top_candidates, 
    v_skill_demand, 
    v_open_positions_summary 
TO recruiter_role;

-- C. Full CRUD permissions on job openings and candidate applications
GRANT SELECT, INSERT, UPDATE, DELETE ON 
    opening, 
    opening_skill, 
    application 
TO recruiter_role;

-- D. Sequence permissions for auto-incrementing surrogate keys
GRANT USAGE, SELECT ON SEQUENCE 
    opening_opening_id_seq, 
    application_application_id_seq 
TO recruiter_role;

-- E. Routine execution permissions
GRANT EXECUTE ON FUNCTION get_top_candidates(INT, INT) TO recruiter_role;
GRANT EXECUTE ON PROCEDURE hire_candidate(INT) TO recruiter_role;
GRANT EXECUTE ON FUNCTION recompute_all_match_scores() TO recruiter_role;


-- ============================================================================
-- 5. CANDIDATE ROLE (candidate_role)
-- Privileges:
--   - Read-only (SELECT) access to explore job opportunities:
--       opening, opening_skill, skill, company.
--   - Read, insert, and update access for managing own skills and applications:
--       candidate_skill, application.
--   - Read and update access on candidate table (for developer profile updates).
--   - USAGE on sequence application_application_id_seq to submit applications.
-- ============================================================================

-- A. Read-only permissions to search openings, companies, and skill catalogs
GRANT SELECT ON 
    opening, 
    opening_skill, 
    skill, 
    company 
TO candidate_role;

-- B. Permissions to submit and maintain skills and job applications
--    (SELECT is included so UPDATE/WHERE conditions can be evaluated)
GRANT SELECT, INSERT, UPDATE ON 
    candidate_skill, 
    application 
TO candidate_role;

-- C. Permissions for candidates to inspect and update their own developer profile
GRANT SELECT, UPDATE ON 
    candidate 
TO candidate_role;

-- D. Sequence permissions to generate new application records
GRANT USAGE, SELECT ON SEQUENCE 
    application_application_id_seq 
TO candidate_role;

-- E. View access: Candidates can review skill demand trends and active position summaries
GRANT SELECT ON 
    v_skill_demand, 
    v_open_positions_summary 
TO candidate_role;


-- ============================================================================
-- 6. SECURITY AUDIT RESTRICTIONS
-- Explicitly ensure application_audit and system internals are not modifiable
-- by recruiter or candidate roles.
-- ============================================================================
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON application_audit FROM recruiter_role, candidate_role;
REVOKE ALL ON match_score FROM candidate_role;

-- Recruiter can only read audit logs (compliance/monitoring)
GRANT SELECT ON application_audit TO recruiter_role;


-- ============================================================================
-- 7. ROLE VERIFICATION & TESTING SNIPPETS (Run as superuser)
-- ============================================================================
/*
-------------------------------------------------------------------------------
-- TEST 1: Recruiter Permissions
-------------------------------------------------------------------------------
SET ROLE recruiter_role;

-- Permitted: Query candidate matches and views
SELECT * FROM v_top_candidates LIMIT 3;

-- Permitted: Post a new job opening
INSERT INTO opening (company_id, title, min_experience_yrs, salary_min, salary_max, status)
VALUES (1, 'Site Reliability Architect', 6.0, 140000, 175000, 'OPEN');

-- Denied: Attempting to delete a candidate profile
DELETE FROM candidate WHERE candidate_id = 1;
-- Expected Error: ERROR: permission denied for table candidate

RESET ROLE;

-------------------------------------------------------------------------------
-- TEST 2: Candidate Permissions
-------------------------------------------------------------------------------
SET ROLE candidate_role;

-- Permitted: Search active openings and companies
SELECT o.opening_id, o.title, c.company_name, o.salary_max
FROM opening o
JOIN company c ON o.company_id = c.company_id
WHERE o.status = 'OPEN';

-- Permitted: Submit an application
INSERT INTO application (candidate_id, opening_id, status)
VALUES (4, 3, 'APPLIED');

-- Denied: Attempting to modify job opening requirements or inspect audit logs
UPDATE opening SET salary_max = 250000 WHERE opening_id = 1;
-- Expected Error: ERROR: permission denied for table opening

SELECT * FROM application_audit;
-- Expected Error: ERROR: permission denied for table application_audit

RESET ROLE;
-------------------------------------------------------------------------------
*/
