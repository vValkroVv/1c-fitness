SELECT
    name,
    state_desc,
    recovery_model_desc,
    compatibility_level
FROM sys.databases
WHERE name = N'FitnessRestored_20260630_macos';
GO

USE [FitnessRestored_20260630_macos];
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

SELECT TOP (5)
    s.name AS schema_name,
    t.name AS table_name,
    SUM(p.rows) AS row_count
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name
ORDER BY SUM(p.rows) DESC, s.name, t.name;
GO
