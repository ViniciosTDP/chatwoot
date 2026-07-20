-- Creates Evolution API database/user on the shared Postgres instance.
-- Runs only on first volume init (docker-entrypoint-initdb.d).
CREATE USER evolution WITH PASSWORD 'evolution_change_me';
CREATE DATABASE evolution OWNER evolution;
GRANT ALL PRIVILEGES ON DATABASE evolution TO evolution;
\c evolution
GRANT ALL ON SCHEMA public TO evolution;
ALTER SCHEMA public OWNER TO evolution;
