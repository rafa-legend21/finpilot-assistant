CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS app_bootstrap (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schema_version TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app_bootstrap (schema_version)
SELECT '0.1.0'
WHERE NOT EXISTS (SELECT 1 FROM app_bootstrap);
