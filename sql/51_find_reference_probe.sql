SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @target binary(16) = 0xBE0CA956933110A046DC22070C41C1CE;
DECLARE @sql nvarchar(max) = N'';

SELECT @sql = STRING_AGG(
    CAST(
        N'IF EXISTS (SELECT 1 FROM '
        + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
        + N' WHERE _IDRRef = @target) SELECT N'''
        + REPLACE(SCHEMA_NAME(t.schema_id) + N'.' + t.name, '''', '''''')
        + N''' AS table_name, COUNT(*) AS rows_count FROM '
        + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
        + N' WHERE _IDRRef = @target;'
        AS nvarchar(max)
    ),
    CHAR(10)
)
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
 AND c.name = N'_IDRRef';

EXEC sp_executesql @sql, N'@target binary(16)', @target = @target;

