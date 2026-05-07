USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

IF OBJECT_ID('tempdb..#source_client_ref') IS NOT NULL DROP TABLE #source_client_ref;
IF OBJECT_ID('tempdb..#email_column_counts') IS NOT NULL DROP TABLE #email_column_counts;
IF OBJECT_ID('tempdb..#email_client_counts') IS NOT NULL DROP TABLE #email_client_counts;
IF OBJECT_ID('tempdb..#binary_client_matches') IS NOT NULL DROP TABLE #binary_client_matches;

CREATE TABLE #source_client_ref (
    table_name nvarchar(128) NOT NULL,
    rt_column nvarchar(128) NULL,
    rr_column nvarchar(128) NULL,
    note nvarchar(200) NOT NULL
);

INSERT INTO #source_client_ref (table_name, rt_column, rr_column, note)
VALUES
    (N'_Reference64', NULL, NULL, N'client master itself'),
    (N'_InfoRg5233', N'_Fld5252_RTRef', N'_Fld5252_RRRef', N'direct client composite ref'),
    (N'_InfoRg7156', N'_Fld7160_RTRef', N'_Fld7160_RRRef', N'direct client composite ref'),
    (N'_InfoRg6941', N'_Fld6942_RTRef', N'_Fld6942_RRRef', N'direct client composite ref'),
    (N'_InfoRg2188', N'_Fld2190_RTRef', N'_Fld2190_RRRef', N'direct client composite ref'),
    (N'_InfoRg5867', N'_Fld5870_RTRef', N'_Fld5870_RRRef', N'direct client composite ref'),
    (N'_InfoRg5226', N'_Fld5227_RTRef', N'_Fld5227_RRRef', N'direct client composite ref'),
    (N'_InfoRg5211', N'_Fld5213_RTRef', N'_Fld5213_RRRef', N'direct client composite ref'),
    (N'_InfoRg5199', N'_Fld5202_RTRef', N'_Fld5202_RRRef', N'direct client composite ref'),
    (N'_InfoRg5255', NULL, NULL, N'has email-like values and phones, direct client ref unknown');

CREATE TABLE #email_column_counts (
    table_name nvarchar(128) NOT NULL,
    column_name nvarchar(128) NOT NULL,
    approx_rows bigint NOT NULL,
    at_rows bigint NOT NULL,
    plausible_email_rows bigint NOT NULL,
    nonempty_rows bigint NOT NULL
);

CREATE TABLE #email_client_counts (
    table_name nvarchar(128) NOT NULL,
    column_name nvarchar(128) NOT NULL,
    client_ref_note nvarchar(200) NOT NULL,
    rows_with_email_and_client bigint NOT NULL,
    distinct_clients_with_email bigint NOT NULL
);

CREATE TABLE #binary_client_matches (
    table_name nvarchar(128) NOT NULL,
    binary_column_name nvarchar(128) NOT NULL,
    rows_matching_reference64 bigint NOT NULL,
    distinct_clients bigint NOT NULL
);

DECLARE
    @table_name nvarchar(128),
    @column_name nvarchar(128),
    @approx_rows bigint,
    @rt_column nvarchar(128),
    @rr_column nvarchar(128),
    @note nvarchar(200),
    @sql nvarchar(max),
    @binary_column_name nvarchar(128);

DECLARE text_cursor CURSOR LOCAL FAST_FORWARD FOR
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
    t.name,
    c.name,
    rc.approx_rows
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
JOIN row_counts rc ON rc.object_id = t.object_id
JOIN #source_client_ref src ON src.table_name COLLATE DATABASE_DEFAULT = t.name COLLATE DATABASE_DEFAULT
WHERE ty.name IN (N'nvarchar', N'nchar', N'varchar', N'char')
ORDER BY t.name, c.column_id;

OPEN text_cursor;
FETCH NEXT FROM text_cursor INTO @table_name, @column_name, @approx_rows;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #email_column_counts (
    table_name,
    column_name,
    approx_rows,
    at_rows,
    plausible_email_rows,
    nonempty_rows
)
SELECT
    @table_name,
    @column_name,
    @approx_rows,
    SUM(CASE WHEN CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%@%'' THEN CONVERT(bigint, 1) ELSE 0 END),
    SUM(CASE WHEN CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%'' THEN CONVERT(bigint, 1) ELSE 0 END),
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N'))), N'''') IS NOT NULL THEN CONVERT(bigint, 1) ELSE 0 END)
FROM dbo.' + QUOTENAME(@table_name) + N'
HAVING SUM(CASE WHEN CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%@%'' THEN CONVERT(bigint, 1) ELSE 0 END) > 0
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@table_name nvarchar(128), @column_name nvarchar(128), @approx_rows bigint',
        @table_name = @table_name,
        @column_name = @column_name,
        @approx_rows = @approx_rows;

    FETCH NEXT FROM text_cursor INTO @table_name, @column_name, @approx_rows;
END

CLOSE text_cursor;
DEALLOCATE text_cursor;

DECLARE client_text_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    ecc.table_name,
    ecc.column_name,
    src.rt_column,
    src.rr_column,
    src.note
FROM #email_column_counts ecc
JOIN #source_client_ref src ON src.table_name COLLATE DATABASE_DEFAULT = ecc.table_name COLLATE DATABASE_DEFAULT
WHERE ecc.plausible_email_rows > 0
  AND src.rr_column IS NOT NULL
ORDER BY ecc.plausible_email_rows DESC, ecc.table_name, ecc.column_name;

OPEN client_text_cursor;
FETCH NEXT FROM client_text_cursor INTO @table_name, @column_name, @rt_column, @rr_column, @note;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #email_client_counts (
    table_name,
    column_name,
    client_ref_note,
    rows_with_email_and_client,
    distinct_clients_with_email
)
SELECT
    @table_name,
    @column_name,
    @note,
    COUNT_BIG(*),
    COUNT(DISTINCT CONVERT(varchar(32), ' + QUOTENAME(@rr_column) + N', 2))
FROM dbo.' + QUOTENAME(@table_name) + N'
WHERE ' + QUOTENAME(@rt_column) + N' = 0x00000040
  AND CONVERT(nvarchar(max), ' + QUOTENAME(@column_name) + N') LIKE N''%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%''
HAVING COUNT_BIG(*) > 0
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@table_name nvarchar(128), @column_name nvarchar(128), @note nvarchar(200)',
        @table_name = @table_name,
        @column_name = @column_name,
        @note = @note;

    FETCH NEXT FROM client_text_cursor INTO @table_name, @column_name, @rt_column, @rr_column, @note;
END

CLOSE client_text_cursor;
DEALLOCATE client_text_cursor;

DECLARE binary_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    t.name,
    c.name
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
JOIN #source_client_ref src ON src.table_name COLLATE DATABASE_DEFAULT = t.name COLLATE DATABASE_DEFAULT
WHERE ty.name = N'binary'
  AND c.max_length = 16
ORDER BY t.name, c.column_id;

OPEN binary_cursor;
FETCH NEXT FROM binary_cursor INTO @table_name, @binary_column_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #binary_client_matches (
    table_name,
    binary_column_name,
    rows_matching_reference64,
    distinct_clients
)
SELECT
    @table_name,
    @binary_column_name,
    COUNT_BIG(*),
    COUNT(DISTINCT CONVERT(varchar(32), src.' + QUOTENAME(@binary_column_name) + N', 2))
FROM dbo.' + QUOTENAME(@table_name) + N' AS src
JOIN dbo._Reference64 AS client
  ON client._IDRRef = src.' + QUOTENAME(@binary_column_name) + N'
HAVING COUNT_BIG(*) > 0
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@table_name nvarchar(128), @binary_column_name nvarchar(128)',
        @table_name = @table_name,
        @binary_column_name = @binary_column_name;

    FETCH NEXT FROM binary_cursor INTO @table_name, @binary_column_name;
END

CLOSE binary_cursor;
DEALLOCATE binary_cursor;

SELECT
    'targeted_email_columns' AS result_set,
    table_name,
    column_name,
    approx_rows,
    at_rows,
    plausible_email_rows,
    nonempty_rows
FROM #email_column_counts
ORDER BY plausible_email_rows DESC, at_rows DESC, table_name, column_name;

SELECT
    'targeted_email_with_direct_client_ref' AS result_set,
    table_name,
    column_name,
    client_ref_note,
    rows_with_email_and_client,
    distinct_clients_with_email
FROM #email_client_counts
ORDER BY distinct_clients_with_email DESC, rows_with_email_and_client DESC, table_name, column_name;

SELECT
    'targeted_binary_columns_matching_clients' AS result_set,
    table_name,
    binary_column_name,
    rows_matching_reference64,
    distinct_clients
FROM #binary_client_matches
ORDER BY table_name, distinct_clients DESC, binary_column_name;
GO
