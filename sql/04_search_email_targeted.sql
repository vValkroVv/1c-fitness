SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

IF OBJECT_ID('tempdb..#email_hits') IS NOT NULL
    DROP TABLE #email_hits;

CREATE TABLE #email_hits (
    table_name nvarchar(128) NOT NULL,
    column_name nvarchar(128) NOT NULL,
    email_like_rows bigint NOT NULL,
    sample_value nvarchar(500) NULL
);

DECLARE
    @table_name nvarchar(128),
    @column_name nvarchar(128),
    @sql nvarchar(max);

DECLARE email_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT t.name, c.name
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN (
    N'_Reference64',
    N'_Reference59',
    N'_Reference46',
    N'_Reference5060',
    N'_Reference5056',
    N'_InfoRg5233',
    N'_InfoRg5843',
    N'_InfoRg7361',
    N'_InfoRg5255',
    N'_InfoRg5199',
    N'_InfoRg5867',
    N'_InfoRg2188',
    N'_InfoRg5226',
    N'_InfoRg3073',
    N'_Document152',
    N'_Document163'
)
  AND ty.name IN (N'nvarchar', N'nchar', N'varchar', N'char')
ORDER BY t.name, c.column_id;

OPEN email_cursor;
FETCH NEXT FROM email_cursor INTO @table_name, @column_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
IF EXISTS (
    SELECT 1
    FROM dbo.' + QUOTENAME(@table_name) + N'
    WHERE CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%@%''
)
BEGIN
    INSERT INTO #email_hits (table_name, column_name, email_like_rows, sample_value)
    SELECT
        @table_name,
        @column_name,
        COUNT_BIG(*) AS email_like_rows,
        MIN(LEFT(CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N'), 500)) AS sample_value
    FROM dbo.' + QUOTENAME(@table_name) + N'
    WHERE CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%@%'';
END';

    EXEC sp_executesql
        @sql,
        N'@table_name nvarchar(128), @column_name nvarchar(128)',
        @table_name = @table_name,
        @column_name = @column_name;

    FETCH NEXT FROM email_cursor INTO @table_name, @column_name;
END

CLOSE email_cursor;
DEALLOCATE email_cursor;

SELECT
    table_name,
    column_name,
    email_like_rows,
    sample_value
FROM #email_hits
ORDER BY email_like_rows DESC, table_name, column_name;
GO
