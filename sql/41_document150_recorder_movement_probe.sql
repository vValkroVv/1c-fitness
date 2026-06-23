SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_date date = CONVERT(date, @cutoff_at);

IF OBJECT_ID('tempdb..#final_active_contracts') IS NOT NULL
    DROP TABLE #final_active_contracts;

CREATE TABLE #final_active_contracts (
    document_number nvarchar(20) COLLATE Cyrillic_General_CI_AS NOT NULL PRIMARY KEY
);

INSERT INTO #final_active_contracts(document_number)
VALUES
    (N'00000149952'),
    (N'00000149697'),
    (N'00000150143'),
    (N'00000149696'),
    (N'00000150128'),
    (N'00000150231'),
    (N'00000150029'),
    (N'00000149630'),
    (N'00000149628'),
    (N'00000149980'),
    (N'00000150031'),
    (N'00000149921');

IF OBJECT_ID('tempdb..#active_subrent') IS NOT NULL
    DROP TABLE #active_subrent;

SELECT
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.start_date,
    f.end_date,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin
INTO #active_subrent
FROM fitbase_part2.membership_import_facts AS f
JOIN #final_active_contracts AS c
  ON c.document_number = f.document_number;

IF OBJECT_ID('tempdb..#active_doc150') IS NOT NULL
    DROP TABLE #active_doc150;

SELECT
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.start_date,
    s.end_date,
    d._IDRRef AS doc150_ref_bin,
    CONVERT(varchar(32), d._IDRRef, 2) AS doc150_ref,
    d._Number AS doc150_number,
    DATEADD(year, -2000, d._Date_Time) AS visit_datetime,
    CONVERT(date, DATEADD(year, -2000, d._Date_Time)) AS visit_date,
    d._Fld995 AS duration_seconds
INTO #active_doc150
FROM #active_subrent AS s
JOIN dbo._Document150 AS d
  ON d._Fld991_RRRef = s.subscription_ref_bin
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
  AND DATEADD(year, -2000, d._Date_Time) <= @cutoff_at
  AND CONVERT(date, DATEADD(year, -2000, d._Date_Time)) BETWEEN s.start_date AND
      CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END;

CREATE INDEX IX_active_doc150_ref_bin ON #active_doc150(doc150_ref_bin);

IF OBJECT_ID('tempdb..#recorder_matches') IS NOT NULL
    DROP TABLE #recorder_matches;

CREATE TABLE #recorder_matches (
    table_name sysname NOT NULL,
    rows_count bigint NOT NULL,
    distinct_doc150 bigint NOT NULL,
    min_period datetime2(0) NULL,
    max_period datetime2(0) NULL
);

DECLARE
    @schema_name sysname,
    @table_name sysname,
    @full_name nvarchar(300),
    @has_period bit,
    @sql nvarchar(max);

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    CASE WHEN EXISTS (
        SELECT 1
        FROM sys.columns AS pc
        WHERE pc.object_id = t.object_id
          AND pc.name = N'_Period'
    ) THEN 1 ELSE 0 END AS has_period
FROM sys.tables AS t
JOIN sys.schemas AS s
  ON s.schema_id = t.schema_id
JOIN sys.columns AS c
  ON c.object_id = t.object_id
 AND c.name = N'_RecorderRRef'
WHERE t.name LIKE N'_AccumRg%'
   OR t.name LIKE N'_InfoRg%'
   OR t.name LIKE N'_Document%_VT%'
ORDER BY t.name;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @schema_name, @table_name, @has_period;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @full_name = QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name);

    SET @sql = N'
        INSERT INTO #recorder_matches(table_name, rows_count, distinct_doc150, min_period, max_period)
        SELECT
            N''' + REPLACE(@table_name, N'''', N'''''') + N''',
            COUNT_BIG(*),
            COUNT(DISTINCT d.doc150_ref),
            ' + CASE
                    WHEN @has_period = 1 THEN N'MIN(DATEADD(year, -2000, x._Period)), MAX(DATEADD(year, -2000, x._Period))'
                    ELSE N'NULL, NULL'
                END + N'
        FROM ' + @full_name + N' AS x
        JOIN #active_doc150 AS d
          ON d.doc150_ref_bin = x._RecorderRRef;';

    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM table_cursor INTO @schema_name, @table_name, @has_period;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

SELECT
    'active_doc150_scope' AS probe,
    COUNT(*) AS doc150_events_inside_period_to_cutoff,
    COUNT(DISTINCT document_number) AS contracts_with_events,
    MIN(visit_datetime) AS min_visit_datetime,
    MAX(visit_datetime) AS max_visit_datetime
FROM #active_doc150;

SELECT
    'doc150_as_recorder_matches' AS probe,
    table_name,
    rows_count,
    distinct_doc150,
    min_period,
    max_period
FROM #recorder_matches
WHERE rows_count > 0
ORDER BY rows_count DESC, table_name;

