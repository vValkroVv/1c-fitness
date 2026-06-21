SELECT
    name,
    state_desc,
    recovery_model_desc,
    compatibility_level
FROM sys.databases
WHERE name = N'FitnessRestored_20260523_macos';
GO

USE [FitnessRestored_20260523_macos];
GO

SELECT COUNT(*) AS user_tables
FROM sys.tables
WHERE is_ms_shipped = 0;
GO

SELECT COUNT(*) AS user_columns
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
WHERE t.is_ms_shipped = 0;
GO
