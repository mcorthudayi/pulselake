CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS security;
REVOKE ALL ON SCHEMA security FROM PUBLIC;

CREATE TABLE IF NOT EXISTS security.deid_config (
    singleton  BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    salt       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO security.deid_config (salt)
VALUES (encode(gen_random_bytes(32), 'hex'))
ON CONFLICT (singleton) DO NOTHING;
