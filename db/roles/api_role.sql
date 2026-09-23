SELECT 'CREATE ROLE pulselake_api LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pulselake_api')
\gexec

ALTER ROLE pulselake_api WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'api_password';

GRANT CONNECT ON DATABASE pulselake TO pulselake_api;
GRANT USAGE ON SCHEMA raw, deid, audit TO pulselake_api;
GRANT SELECT ON raw.fhir_resources TO pulselake_api;
GRANT SELECT ON ALL TABLES IN SCHEMA deid TO pulselake_api;
ALTER DEFAULT PRIVILEGES FOR ROLE pulselake IN SCHEMA deid GRANT SELECT ON TABLES TO pulselake_api;
GRANT SELECT, INSERT ON audit.access_log TO pulselake_api;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA audit TO pulselake_api;
