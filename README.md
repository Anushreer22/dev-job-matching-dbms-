# Dev Job and Skill-Matching Platform

A comprehensive PostgreSQL-based Database Management System (DBMS) college project designed to model, manage, and automate the matching of software developers with relevant job openings based on skill proficiency, experience, and requirement weightings.

---

## 📌 Project Overview

Recruitment platforms often struggle with accurately matching candidates to job requirements. This project implements a relational database system that quantifies skill alignment between job seekers (candidates) and job vacancies (openings), incorporating granular attributes like skill proficiency levels, years of experience, and requirement weights.

---

## 🗄️ Core Entities & Schema Architecture

The database model revolves around the following primary entities and relationships:

1. **`candidate`**: Stores software developer profile data, contact information, total experience, and status.
2. **`skill`**: Master catalog of technical skills, technologies, frameworks, and tools.
3. **`candidate_skill`** *(M:N Junction)*: Maps candidates to their acquired skills with attributes:
   - `proficiency`: Proficiency rating on a scale of `1` to `5`.
   - `years_used`: Number of years the candidate has worked with the skill.
4. **`company`**: Details about hiring companies, industry sectors, and location.
5. **`opening`**: Job vacancies posted by companies with salary range, role type, and deadline.
6. **`opening_skill`** *(M:N Junction)*: Defines required skills for a job opening with attributes:
   - `required_level`: Minimum expected proficiency on a scale of `1` to `5`.
   - `weight`: Relative importance/weight of the skill for the position.
7. **`application`**: Records candidate submissions for specific job openings, tracking application dates and statuses (e.g., *Applied*, *Reviewing*, *Shortlisted*, *Rejected*).
8. **`match_score`**: Stores computed compatibility scores between candidates and job openings based on skill overlap, proficiency matching, and weights.

---

## 📁 Repository Structure

```text
dev-job-matching-dbms/
├── docs/                      # Documentation, ER diagrams, and project reports
├── screenshots/               # Query execution results and psql/pgAdmin screenshots
├── sql/                       # Modular SQL scripts
│   ├── 01_schema.sql          # DDL: Table definitions, constraints, primary & foreign keys
│   ├── 02_sample_data.sql     # DML: Realistic seed data for all entities
│   ├── 03_views.sql           # Views for reporting, candidate profiles, and job listings
│   ├── 04_triggers.sql        # Triggers for automated validation, timestamps, and match updates
│   ├── 05_procedures.sql      # Stored procedures and functions (e.g., match score calculation)
│   ├── 06_queries.sql         # Complex analytical, aggregation, and join queries
│   ├── 07_roles_access.sql    # Role-based access control (RBAC), grants, and security
│   └── 08_run_all.sql         # Master orchestration script to execute all scripts in sequence
├── .gitignore                 # Ignored OS, editor, and temporary files
└── README.md                  # Project documentation and guide
```

---

## ⚙️ Prerequisites & Setup

- **Database Engine**: PostgreSQL (v14+)
- **Client Tools**: `psql` command-line utility, pgAdmin 4, or DBeaver

### Execution Guide

SQL scripts in the `sql/` directory are designed to be executed sequentially from `01` to `07`, or orchestrated automatically via `08_run_all.sql`:

```bash
# Connect and execute master runner in PostgreSQL
psql -U postgres -d dev_job_matching -f sql/08_run_all.sql
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
