SELECT
    name,
    state_desc,
    recovery_model_desc,
    compatibility_level,
    create_date
FROM sys.databases
WHERE name = N'FitnessRestored';
GO

SELECT
    DB_NAME(database_id) AS database_name,
    name AS logical_name,
    type_desc,
    size * 8.0 / 1024 AS size_mb,
    physical_name
FROM sys.master_files
WHERE database_id = DB_ID(N'FitnessRestored')
ORDER BY type_desc, logical_name;
GO

USE [FitnessRestored];
GO

SELECT COUNT(*) AS user_tables_count
FROM sys.tables
WHERE is_ms_shipped = 0;
GO
