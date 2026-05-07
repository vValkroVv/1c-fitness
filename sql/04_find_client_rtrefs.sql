SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

IF OBJECT_ID('tempdb..#client_rtref_hits') IS NOT NULL
    DROP TABLE #client_rtref_hits;

CREATE TABLE #client_rtref_hits (
    schema_name nvarchar(128) NOT NULL,
    table_name nvarchar(128) NOT NULL,
    rt_column nvarchar(128) NOT NULL,
    rr_column nvarchar(128) NOT NULL,
    approx_rows bigint NOT NULL,
    client_rt_rows bigint NOT NULL,
    distinct_client_refs bigint NOT NULL
);

DECLARE
    @schema_name nvarchar(128),
    @table_name nvarchar(128),
    @rt_column nvarchar(128),
    @rr_column nvarchar(128),
    @approx_rows bigint,
    @sql nvarchar(max);

DECLARE rtref_cursor CURSOR LOCAL FAST_FORWARD FOR
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
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS rt_column,
    REPLACE(c.name, N'_RTRef', N'_RRRef') AS rr_column,
    rc.approx_rows
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
JOIN row_counts rc ON rc.object_id = t.object_id
WHERE
    t.is_ms_shipped = 0
    AND rc.approx_rows > 0
    AND c.name LIKE N'%[_]RTRef'
    AND ty.name = N'binary'
    AND c.max_length = 4
    AND EXISTS (
        SELECT 1
        FROM sys.columns rr
        WHERE rr.object_id = t.object_id
          AND rr.name = REPLACE(c.name, N'_RTRef', N'_RRRef')
    )
    AND (
        t.name LIKE N'_Reference%'
        OR t.name LIKE N'_Document%'
        OR t.name LIKE N'_InfoRg%'
        OR t.name LIKE N'_AccumRg%'
    )
ORDER BY rc.approx_rows DESC, t.name, c.column_id;

OPEN rtref_cursor;
FETCH NEXT FROM rtref_cursor INTO @schema_name, @table_name, @rt_column, @rr_column, @approx_rows;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #client_rtref_hits (
    schema_name, table_name, rt_column, rr_column,
    approx_rows, client_rt_rows, distinct_client_refs
)
SELECT
    @schema_name,
    @table_name,
    @rt_column,
    @rr_column,
    @approx_rows,
    COUNT_BIG(*) AS client_rt_rows,
    COUNT(DISTINCT CONVERT(varchar(32), ' + QUOTENAME(@rr_column) + N', 2)) AS distinct_client_refs
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N'
WHERE ' + QUOTENAME(@rt_column) + N' = 0x00000040
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@schema_name nvarchar(128), @table_name nvarchar(128), @rt_column nvarchar(128), @rr_column nvarchar(128), @approx_rows bigint',
        @schema_name = @schema_name,
        @table_name = @table_name,
        @rt_column = @rt_column,
        @rr_column = @rr_column,
        @approx_rows = @approx_rows;

    FETCH NEXT FROM rtref_cursor INTO @schema_name, @table_name, @rt_column, @rr_column, @approx_rows;
END

CLOSE rtref_cursor;
DEALLOCATE rtref_cursor;

SELECT
    schema_name,
    table_name,
    rt_column,
    rr_column,
    approx_rows,
    client_rt_rows,
    distinct_client_refs
FROM #client_rtref_hits
WHERE client_rt_rows > 0
ORDER BY client_rt_rows DESC, table_name, rt_column;
GO
