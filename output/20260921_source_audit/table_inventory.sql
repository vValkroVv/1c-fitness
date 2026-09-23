SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT * FROM (SELECT 'june' snapshot,t.name table_name,SUM(p.row_count) rows_metadata
            FROM [FitnessRestored_20260630_original].sys.tables t JOIN [FitnessRestored_20260630_original].sys.schemas s ON s.schema_id=t.schema_id
            JOIN [FitnessRestored_20260630_original].sys.dm_db_partition_stats p ON p.object_id=t.object_id AND p.index_id IN (0,1)
            WHERE s.name='dbo' GROUP BY t.name UNION ALL SELECT 'september' snapshot,t.name table_name,SUM(p.row_count) rows_metadata
            FROM [FitnessRestored_20260630_macos].sys.tables t JOIN [FitnessRestored_20260630_macos].sys.schemas s ON s.schema_id=t.schema_id
            JOIN [FitnessRestored_20260630_macos].sys.dm_db_partition_stats p ON p.object_id=t.object_id AND p.index_id IN (0,1)
            WHERE s.name='dbo' GROUP BY t.name) q ORDER BY table_name,snapshot FOR JSON PATH, INCLUDE_NULL_VALUES;
