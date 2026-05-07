SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';
DECLARE @cutoff_plus_90 datetime2 = DATEADD(day, 90, @cutoff);

IF OBJECT_ID('tempdb..#client_links') IS NOT NULL
    DROP TABLE #client_links;

CREATE TABLE #client_links (
    table_name nvarchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
    rt_column nvarchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
    rr_column nvarchar(128) COLLATE DATABASE_DEFAULT NOT NULL
);

INSERT INTO #client_links (table_name, rt_column, rr_column)
VALUES
    (N'_Document150', N'_Fld989_RTRef', N'_Fld989_RRRef'),
    (N'_AccumRg3305', N'_Fld3307_RTRef', N'_Fld3307_RRRef'),
    (N'_InfoRg2878', N'_Fld2880_RTRef', N'_Fld2880_RRRef'),
    (N'_Document152', N'_Fld1057_RTRef', N'_Fld1057_RRRef'),
    (N'_Document137_VT724', N'_Fld727_RTRef', N'_Fld727_RRRef'),
    (N'_AccumRgT3318', N'_Fld3307_RTRef', N'_Fld3307_RRRef'),
    (N'_InfoRg5233', N'_Fld5252_RTRef', N'_Fld5252_RRRef'),
    (N'_Document163', N'_Fld1447_RTRef', N'_Fld1447_RRRef'),
    (N'_Reference59', N'_Fld3750_RTRef', N'_Fld3750_RRRef'),
    (N'_InfoRg7156', N'_Fld7160_RTRef', N'_Fld7160_RRRef'),
    (N'_Reference115', N'_Fld4588_RTRef', N'_Fld4588_RRRef'),
    (N'_InfoRg6941', N'_Fld6942_RTRef', N'_Fld6942_RRRef'),
    (N'_Document9230', N'_Fld9234_RTRef', N'_Fld9234_RRRef'),
    (N'_InfoRg2188', N'_Fld2190_RTRef', N'_Fld2190_RRRef'),
    (N'_InfoRg2436', N'_Fld2437_RTRef', N'_Fld2437_RRRef'),
    (N'_InfoRg5226', N'_Fld5227_RTRef', N'_Fld5227_RRRef'),
    (N'_InfoRg5867', N'_Fld5870_RTRef', N'_Fld5870_RRRef'),
    (N'_InfoRg2944', N'_Fld2952_RTRef', N'_Fld2952_RRRef'),
    (N'_Document126_VT347', N'_Fld350_RTRef', N'_Fld350_RRRef'),
    (N'_Document158', N'_Fld1279_RTRef', N'_Fld1279_RRRef');

IF OBJECT_ID('tempdb..#date_window_hits') IS NOT NULL
    DROP TABLE #date_window_hits;

CREATE TABLE #date_window_hits (
    table_name nvarchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
    date_column nvarchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
    total_client_rows bigint NOT NULL,
    rows_on_or_after_cutoff bigint NOT NULL,
    rows_cutoff_to_90_days bigint NOT NULL,
    distinct_clients_cutoff_to_90_days bigint NOT NULL,
    min_date datetime2 NULL,
    max_date datetime2 NULL
);

DECLARE
    @table_name nvarchar(128),
    @rt_column nvarchar(128),
    @rr_column nvarchar(128),
    @date_column nvarchar(128),
    @sql nvarchar(max);

DECLARE date_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    l.table_name,
    l.rt_column,
    l.rr_column,
    c.name AS date_column
FROM #client_links l
JOIN sys.tables t ON t.name = l.table_name
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE ty.name IN (N'datetime', N'datetime2', N'date', N'smalldatetime')
ORDER BY l.table_name, c.column_id;

OPEN date_cursor;
FETCH NEXT FROM date_cursor INTO @table_name, @rt_column, @rr_column, @date_column;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #date_window_hits (
    table_name,
    date_column,
    total_client_rows,
    rows_on_or_after_cutoff,
    rows_cutoff_to_90_days,
    distinct_clients_cutoff_to_90_days,
    min_date,
    max_date
)
SELECT
    @table_name,
    @date_column,
    COUNT_BIG(*) AS total_client_rows,
    SUM(CASE WHEN ' + QUOTENAME(@date_column) + N' >= @cutoff THEN 1 ELSE 0 END) AS rows_on_or_after_cutoff,
    SUM(CASE WHEN ' + QUOTENAME(@date_column) + N' >= @cutoff AND ' + QUOTENAME(@date_column) + N' <= @cutoff_plus_90 THEN 1 ELSE 0 END) AS rows_cutoff_to_90_days,
    COUNT(DISTINCT CASE WHEN ' + QUOTENAME(@date_column) + N' >= @cutoff AND ' + QUOTENAME(@date_column) + N' <= @cutoff_plus_90 THEN CONVERT(varchar(32), ' + QUOTENAME(@rr_column) + N', 2) END) AS distinct_clients_cutoff_to_90_days,
    MIN(' + QUOTENAME(@date_column) + N') AS min_date,
    MAX(' + QUOTENAME(@date_column) + N') AS max_date
FROM dbo.' + QUOTENAME(@table_name) + N'
WHERE ' + QUOTENAME(@rt_column) + N' = 0x00000040
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@table_name nvarchar(128), @date_column nvarchar(128), @cutoff datetime2, @cutoff_plus_90 datetime2',
        @table_name = @table_name,
        @date_column = @date_column,
        @cutoff = @cutoff,
        @cutoff_plus_90 = @cutoff_plus_90;

    FETCH NEXT FROM date_cursor INTO @table_name, @rt_column, @rr_column, @date_column;
END

CLOSE date_cursor;
DEALLOCATE date_cursor;

SELECT
    table_name,
    date_column,
    total_client_rows,
    rows_on_or_after_cutoff,
    rows_cutoff_to_90_days,
    distinct_clients_cutoff_to_90_days,
    min_date,
    max_date
FROM #date_window_hits
WHERE rows_cutoff_to_90_days > 0 OR rows_on_or_after_cutoff > 0
ORDER BY rows_cutoff_to_90_days DESC, rows_on_or_after_cutoff DESC, table_name, date_column;
GO
