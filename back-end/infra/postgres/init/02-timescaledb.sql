DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_available_extensions
        WHERE name = 'timescaledb'
    ) THEN
        EXECUTE 'CREATE EXTENSION IF NOT EXISTS timescaledb';
    END IF;
END
$$;
