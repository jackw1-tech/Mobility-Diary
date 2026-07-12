from django.db import migrations


_ENABLE_TIMESCALE_SQL = """
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_available_extensions
        WHERE name = 'timescaledb'
    ) THEN
        EXECUTE 'CREATE EXTENSION IF NOT EXISTS timescaledb';

        PERFORM public.create_hypertable(
            'mobility_rawsensorreading',
            'timestamp',
            chunk_time_interval => INTERVAL '1 day',
            if_not_exists => TRUE,
            migrate_data => TRUE
        );
    ELSE
        RAISE NOTICE
            'timescaledb non disponibile: mobility_rawsensorreading resta tabella normale';
    END IF;
END
$$;
"""


class Migration(migrations.Migration):
    dependencies = [
        ("mobility", "0029_rawsensorreading_hypertable"),
    ]

    operations = [
        migrations.RunSQL(
            sql=_ENABLE_TIMESCALE_SQL,
            reverse_sql=migrations.RunSQL.noop,
        ),
    ]
