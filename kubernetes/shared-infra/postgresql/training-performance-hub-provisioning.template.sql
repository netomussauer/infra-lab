-- TEMPLATE ONLY — run once by an authorized PostgreSQL administrator after
-- supplying training_hub_password through psql -v. Do not store that value here.
-- This follows the existing dedicated-database and dedicated-role convention.
-- This script is intentionally not idempotent: it fails if the role or database
-- already exists. The operator must verify absence before the one authorized run.
\set ON_ERROR_STOP on

CREATE ROLE training_hub LOGIN PASSWORD :'training_hub_password';
CREATE DATABASE training_hub OWNER training_hub;

\connect training_hub

CREATE EXTENSION IF NOT EXISTS pgcrypto;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO training_hub;
