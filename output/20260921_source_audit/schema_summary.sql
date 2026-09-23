SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT 'june' snapshot,COUNT(DISTINCT table_name) tables_count,COUNT_BIG(*) columns_count FROM (SELECT t.name table_name,c.name column_name,c.column_id,c.system_type_id,
        c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name
        FROM [FitnessRestored_20260630_original].sys.tables t JOIN [FitnessRestored_20260630_original].sys.columns c ON c.object_id=t.object_id
        JOIN [FitnessRestored_20260630_original].sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='dbo') j
        UNION ALL SELECT 'september' snapshot,COUNT(DISTINCT table_name),COUNT_BIG(*) FROM (SELECT t.name table_name,c.name column_name,c.column_id,c.system_type_id,
        c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name
        FROM [FitnessRestored_20260630_macos].sys.tables t JOIN [FitnessRestored_20260630_macos].sys.columns c ON c.object_id=t.object_id
        JOIN [FitnessRestored_20260630_macos].sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='dbo') s FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);
