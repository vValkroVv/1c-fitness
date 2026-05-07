SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

IF OBJECT_ID('tempdb..#contact_text_hits') IS NOT NULL
    DROP TABLE #contact_text_hits;

CREATE TABLE #contact_text_hits (
    pattern_name nvarchar(64) NOT NULL,
    schema_name nvarchar(128) NOT NULL,
    table_name nvarchar(128) NOT NULL,
    column_name nvarchar(128) NOT NULL,
    approx_rows bigint NOT NULL,
    sample_value nvarchar(500) NULL
);

DECLARE
    @schema_name nvarchar(128),
    @table_name nvarchar(128),
    @column_name nvarchar(128),
    @approx_rows bigint,
    @sql nvarchar(max);

DECLARE text_column_cursor CURSOR LOCAL FAST_FORWARD FOR
WITH row_counts AS (
    SELECT
        t.object_id,
        SUM(CASE WHEN p.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS approx_rows
    FROM sys.tables t
    LEFT JOIN sys.partitions p ON p.object_id = t.object_id
    WHERE t.is_ms_shipped = 0
    GROUP BY t.object_id
)
SELECT
    s.name,
    t.name,
    c.name,
    rc.approx_rows
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
JOIN row_counts rc ON rc.object_id = t.object_id
WHERE
    t.is_ms_shipped = 0
    AND rc.approx_rows BETWEEN 1 AND 1000000
    AND ty.name IN (N'nvarchar', N'nchar', N'varchar', N'char')
    AND (
        t.name LIKE N'_Reference%'
        OR t.name LIKE N'_Document%'
        OR t.name LIKE N'_InfoRg%'
        OR t.name LIKE N'_AccumRg%'
    )
ORDER BY rc.approx_rows DESC, t.name, c.column_id;

OPEN text_column_cursor;
FETCH NEXT FROM text_column_cursor INTO @schema_name, @table_name, @column_name, @approx_rows;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #contact_text_hits (pattern_name, schema_name, table_name, column_name, approx_rows, sample_value)
SELECT TOP (1)
    N''email_at'',
    @schema_name,
    @table_name,
    @column_name,
    @approx_rows,
    LEFT(CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N'), 500)
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N'
WHERE CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%@%''
OPTION (MAXDOP 2);

INSERT INTO #contact_text_hits (pattern_name, schema_name, table_name, column_name, approx_rows, sample_value)
SELECT TOP (1)
    N''phone_plus7'',
    @schema_name,
    @table_name,
    @column_name,
    @approx_rows,
    LEFT(CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N'), 500)
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N'
WHERE CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%+7%''
OPTION (MAXDOP 2);

INSERT INTO #contact_text_hits (pattern_name, schema_name, table_name, column_name, approx_rows, sample_value)
SELECT TOP (1)
    N''phone_parentheses'',
    @schema_name,
    @table_name,
    @column_name,
    @approx_rows,
    LEFT(CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N'), 500)
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N'
WHERE CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%([0-9][0-9][0-9])%''
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@schema_name nvarchar(128), @table_name nvarchar(128), @column_name nvarchar(128), @approx_rows bigint',
        @schema_name = @schema_name,
        @table_name = @table_name,
        @column_name = @column_name,
        @approx_rows = @approx_rows;

    FETCH NEXT FROM text_column_cursor INTO @schema_name, @table_name, @column_name, @approx_rows;
END

CLOSE text_column_cursor;
DEALLOCATE text_column_cursor;

SELECT
    pattern_name,
    schema_name,
    table_name,
    column_name,
    approx_rows,
    sample_value
FROM #contact_text_hits
ORDER BY pattern_name, approx_rows DESC, table_name, column_name;
GO
