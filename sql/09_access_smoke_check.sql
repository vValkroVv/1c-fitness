USE [FitnessRestored];
GO

SELECT
    COUNT(*) AS user_tables_count
FROM sys.tables
WHERE is_ms_shipped = 0;
GO

SELECT
    COUNT(*) AS user_columns_count
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
WHERE t.is_ms_shipped = 0;
GO

SELECT TOP (20)
    s.name AS schema_name,
    t.name AS table_name,
    SUM(CASE WHEN p.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS approx_rows
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
LEFT JOIN sys.partitions p ON p.object_id = t.object_id
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name
ORDER BY approx_rows DESC, t.name;
GO

SELECT
    SUM(CASE WHEN t.name = N'Config' THEN 1 ELSE 0 END) AS has_config_table,
    SUM(CASE WHEN t.name LIKE N'_Reference%' THEN 1 ELSE 0 END) AS reference_tables,
    SUM(CASE WHEN t.name LIKE N'_Document%' THEN 1 ELSE 0 END) AS document_tables,
    SUM(CASE WHEN t.name LIKE N'_InfoRg%' THEN 1 ELSE 0 END) AS info_register_tables,
    SUM(CASE WHEN t.name LIKE N'_AccumRg%' THEN 1 ELSE 0 END) AS accumulation_register_tables,
    SUM(CASE WHEN t.name LIKE N'_Enum%' THEN 1 ELSE 0 END) AS enum_tables
FROM sys.tables t
WHERE t.is_ms_shipped = 0;
GO
