CREATE OR REPLACE FUNCTION create_audit_log_partition()
RETURNS void AS $$
DECLARE
    next_quarter_start DATE;
    partition_name TEXT;
    partition_sql TEXT;
BEGIN
    -- Calculate the start of next quarter
    next_quarter_start := DATE_TRUNC('quarter', NOW()) + INTERVAL '1 quarter';
    
    -- Generate partition name
    partition_name := 'audit_logs_' || TO_CHAR(next_quarter_start, 'YYYY_"q"Q');
    
    -- Check if partition exists
    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
    ) THEN
        -- Create the partition
        partition_sql := FORMAT(
            'CREATE TABLE %I PARTITION OF audit_logs
            FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            next_quarter_start,
            next_quarter_start + INTERVAL '1 quarter'
        );
        
        EXECUTE partition_sql;
        
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;
