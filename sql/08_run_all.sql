-- ============================================================================
-- Dev Job and Skill-Matching Platform
-- Script: 08_run_all.sql
-- Description: Master deployment script running 01 to 07 in sequential order.
-- Usage:
--   psql -h localhost -p 5435 -U postgres -d devmatch -f sql/08_run_all.sql
-- Engine: PostgreSQL 12+
-- ============================================================================

\set ON_ERROR_STOP on

\echo '======================================================================'
\echo '  Dev Job and Skill-Matching Platform - Complete Database Deployment'
\echo '======================================================================'

\echo '\n>>> Step 1/7: Initializing schema (DDL)...'
\i sql/01_schema.sql

\echo '\n>>> Step 2/7: Populating realistic sample data (DML)...'
\i sql/02_sample_data.sql

\echo '\n>>> Step 3/7: Creating analytical and reporting views...'
\i sql/03_views.sql

\echo '\n>>> Step 4/7: Creating trigger functions and triggers...'
\i sql/04_triggers.sql

\echo '\n>>> Step 5/7: Creating stored functions, procedures & initializing match scores...'
\i sql/05_procedures.sql

-- Compute and populate match_score table initially
SELECT recompute_all_match_scores() AS match_scores_computed;

\echo '\n>>> Step 6/7: Executing analytical queries...'
\i sql/06_queries.sql

\echo '\n>>> Step 7/7: Configuring Role-Based Access Control (RBAC)...'
\i sql/07_roles_access.sql

\echo '\n======================================================================'
\echo '  All 7 SQL scripts executed successfully!'
\echo '======================================================================'
