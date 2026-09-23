SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
WITH j AS (SELECT t.name table_name,c.name column_name,c.column_id,c.system_type_id,
        c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name
        FROM [FitnessRestored_20260630_original].sys.tables t JOIN [FitnessRestored_20260630_original].sys.columns c ON c.object_id=t.object_id
        JOIN [FitnessRestored_20260630_original].sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='dbo'),s AS (SELECT t.name table_name,c.name column_name,c.column_id,c.system_type_id,
        c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name
        FROM [FitnessRestored_20260630_macos].sys.tables t JOIN [FitnessRestored_20260630_macos].sys.columns c ON c.object_id=t.object_id
        JOIN [FitnessRestored_20260630_macos].sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='dbo')
        SELECT COALESCE(j.table_name,s.table_name) table_name,COALESCE(j.column_name,s.column_name) column_name,
        CASE WHEN j.table_name IS NULL THEN 'added' WHEN s.table_name IS NULL THEN 'removed' ELSE 'changed' END kind
        FROM j FULL JOIN s ON j.table_name=s.table_name AND j.column_name=s.column_name
        WHERE j.table_name IS NULL OR s.table_name IS NULL
          OR EXISTS(SELECT j.column_id,j.system_type_id,j.max_length,j.precision,j.scale,j.is_nullable,j.collation_name
                    EXCEPT SELECT s.column_id,s.system_type_id,s.max_length,s.precision,s.scale,s.is_nullable,s.collation_name)
        ORDER BY table_name,column_name FOR JSON PATH, INCLUDE_NULL_VALUES;
