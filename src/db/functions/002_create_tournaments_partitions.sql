-- Create a function to automatically create tournament partitions
CREATE OR REPLACE FUNCTION create_tournaments_partition()
RETURNS void AS $$
DECLARE
    next_year DATE;
    partition_name TEXT;
    partition_sql TEXT;
BEGIN
    -- Calculate the start of next year
    next_year := DATE_TRUNC('year', NOW()) + INTERVAL '1 year';
    
    -- Generate partition name
    partition_name := 'tournaments_' || TO_CHAR(next_year, 'YYYY');
    
    -- Check if partition exists
    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
    ) THEN
        -- Create the partition
        partition_sql := FORMAT(
            'CREATE TABLE %I PARTITION OF tournaments
            FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            next_year,
            next_year + INTERVAL '1 year'
        );
        
        EXECUTE partition_sql;
        
        RAISE NOTICE 'Created tournament partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;
