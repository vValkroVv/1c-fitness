USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';
DECLARE @cutoff_next_day datetime2 = DATEADD(day, 1, @cutoff);

SELECT
    'Document9230_summary' AS probe,
    COUNT_BIG(*) AS total_rows,
    SUM(CASE WHEN _Fld9234_RTRef = 0x00000040 THEN 1 ELSE 0 END) AS client_rows,
    COUNT(DISTINCT CASE WHEN _Fld9234_RTRef = 0x00000040 THEN CONVERT(varchar(32), _Fld9234_RRRef, 2) END) AS distinct_clients,
    SUM(CASE WHEN _Posted = 0x01 THEN 1 ELSE 0 END) AS posted_rows,
    SUM(CASE WHEN _Marked = 0x01 THEN 1 ELSE 0 END) AS marked_rows,
    MIN(_Date_Time) AS min_doc_date,
    MAX(_Date_Time) AS max_doc_date,
    SUM(CASE WHEN _Date_Time >= DATEADD(day, -90, @cutoff) AND _Date_Time < @cutoff_next_day THEN 1 ELSE 0 END) AS rows_last_90_days_to_cutoff,
    SUM(CASE WHEN _Date_Time >= @cutoff AND _Date_Time < @cutoff_next_day THEN 1 ELSE 0 END) AS rows_on_cutoff_day
FROM dbo._Document9230;
GO

SELECT
    'Document9230_flags' AS probe,
    CONVERT(varchar(2), _Marked, 2) AS marked_hex,
    CONVERT(varchar(2), _Posted, 2) AS posted_hex,
    CONVERT(varchar(2), _Fld9240, 2) AS fld9240_hex,
    CONVERT(varchar(2), _Fld9249, 2) AS fld9249_hex,
    CONVERT(varchar(2), _Fld9250, 2) AS fld9250_hex,
    CONVERT(varchar(2), _Fld9254, 2) AS fld9254_hex,
    CONVERT(varchar(2), _Fld9255, 2) AS fld9255_hex,
    CONVERT(varchar(2), _Fld9261, 2) AS fld9261_hex,
    CONVERT(varchar(2), _Fld10085, 2) AS fld10085_hex,
    CONVERT(varchar(2), _Fld10086, 2) AS fld10086_hex,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CASE WHEN _Fld9234_RTRef = 0x00000040 THEN CONVERT(varchar(32), _Fld9234_RRRef, 2) END) AS distinct_clients,
    MIN(_Date_Time) AS min_doc_date,
    MAX(_Date_Time) AS max_doc_date
FROM dbo._Document9230
GROUP BY
    CONVERT(varchar(2), _Marked, 2),
    CONVERT(varchar(2), _Posted, 2),
    CONVERT(varchar(2), _Fld9240, 2),
    CONVERT(varchar(2), _Fld9249, 2),
    CONVERT(varchar(2), _Fld9250, 2),
    CONVERT(varchar(2), _Fld9254, 2),
    CONVERT(varchar(2), _Fld9255, 2),
    CONVERT(varchar(2), _Fld9261, 2),
    CONVERT(varchar(2), _Fld10085, 2),
    CONVERT(varchar(2), _Fld10086, 2)
ORDER BY rows_count DESC;
GO

IF OBJECT_ID('tempdb..#all_references') IS NOT NULL
    DROP TABLE #all_references;

CREATE TABLE #all_references (
    source_table nvarchar(128) NOT NULL,
    ref binary(16) NOT NULL,
    code nvarchar(200) NULL,
    description nvarchar(600) NULL
);

DECLARE
    @schema_name nvarchar(128),
    @reference_table nvarchar(128),
    @has_code bit,
    @sql nvarchar(max);

DECLARE reference_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name,
       CASE WHEN EXISTS (
            SELECT 1 FROM sys.columns c
            WHERE c.object_id = t.object_id AND c.name = N'_Code'
       ) THEN 1 ELSE 0 END AS has_code
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
  AND t.name LIKE N'_Reference%'
  AND t.name NOT LIKE N'%[_]VT%'
  AND EXISTS (
      SELECT 1 FROM sys.columns c
      WHERE c.object_id = t.object_id AND c.name = N'_IDRRef'
  )
  AND EXISTS (
      SELECT 1 FROM sys.columns c
      WHERE c.object_id = t.object_id AND c.name = N'_Description'
  );

OPEN reference_cursor;
FETCH NEXT FROM reference_cursor INTO @schema_name, @reference_table, @has_code;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #all_references (source_table, ref, code, description)
SELECT
    @reference_table,
    _IDRRef,
    ' + CASE WHEN @has_code = 1 THEN N'CONVERT(nvarchar(200), _Code)' ELSE N'NULL' END + N',
    CONVERT(nvarchar(600), _Description)
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@reference_table) + N'
WHERE _IDRRef <> 0x00000000000000000000000000000000;';

    EXEC sp_executesql
        @sql,
        N'@reference_table nvarchar(128)',
        @reference_table = @reference_table;

    FETCH NEXT FROM reference_cursor INTO @schema_name, @reference_table, @has_code;
END

CLOSE reference_cursor;
DEALLOCATE reference_cursor;

CREATE INDEX IX_all_references_ref ON #all_references(ref);

IF OBJECT_ID('tempdb..#reference_column_matches') IS NOT NULL
    DROP TABLE #reference_column_matches;

CREATE TABLE #reference_column_matches (
    source_table nvarchar(128) NOT NULL,
    source_column nvarchar(128) NOT NULL,
    matched_reference_table nvarchar(128) NOT NULL,
    distinct_matched_values bigint NOT NULL,
    sample_code nvarchar(200) NULL,
    sample_description nvarchar(600) NULL
);

DECLARE
    @source_column nvarchar(128);

DECLARE source_column_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT c.name AS source_column
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name = N'_Document9230'
  AND ty.name = N'binary'
  AND c.max_length = 16
  AND c.name NOT IN (N'_IDRRef', N'_Version', N'_Marked', N'_Posted', N'_Active')
ORDER BY c.column_id;

OPEN source_column_cursor;
FETCH NEXT FROM source_column_cursor INTO @source_column;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
WITH distinct_values AS (
    SELECT DISTINCT ' + QUOTENAME(@source_column) + N' AS ref
    FROM dbo._Document9230
    WHERE ' + QUOTENAME(@source_column) + N' <> 0x00000000000000000000000000000000
)
INSERT INTO #reference_column_matches (
    source_table, source_column, matched_reference_table,
    distinct_matched_values, sample_code, sample_description
)
SELECT
    N''_Document9230'',
    @source_column,
    ar.source_table,
    COUNT_BIG(*) AS distinct_matched_values,
    MIN(ar.code) AS sample_code,
    MIN(ar.description) AS sample_description
FROM distinct_values dv
JOIN #all_references ar ON ar.ref = dv.ref
GROUP BY ar.source_table
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@source_column nvarchar(128)',
        @source_column = @source_column;

    FETCH NEXT FROM source_column_cursor INTO @source_column;
END

CLOSE source_column_cursor;
DEALLOCATE source_column_cursor;

SELECT
    source_table,
    source_column,
    matched_reference_table,
    distinct_matched_values,
    sample_code,
    sample_description
FROM #reference_column_matches
WHERE distinct_matched_values > 0
ORDER BY source_column, distinct_matched_values DESC;
GO

SELECT TOP 80
    'Document9230_recent_sample' AS probe,
    d._Number,
    d._Date_Time,
    CONVERT(varchar(2), d._Marked, 2) AS marked_hex,
    CONVERT(varchar(2), d._Posted, 2) AS posted_hex,
    c._Code AS client_code,
    c._Description AS client_fio,
    d._Fld9235,
    d._Fld9238,
    d._Fld9242,
    d._Fld9252,
    d._Fld9253,
    d._Fld9257,
    d._Fld9241,
    d._Fld9243,
    d._Fld9244,
    d._Fld9245,
    d._Fld9246,
    d._Fld9247,
    d._Fld9258,
    LEFT(d._Fld9259, 240) AS fld9259_text,
    d._Fld9262,
    d._Fld10087,
    CONVERT(varchar(32), d._Fld9232RRef, 2) AS fld9232_ref,
    CONVERT(varchar(32), d._Fld9233RRef, 2) AS fld9233_ref,
    CONVERT(varchar(32), d._Fld9236RRef, 2) AS fld9236_ref,
    CONVERT(varchar(8), d._Fld9237_RTRef, 2) AS fld9237_rtref,
    CONVERT(varchar(32), d._Fld9237_RRRef, 2) AS fld9237_rrref,
    CONVERT(varchar(32), d._Fld9239RRef, 2) AS fld9239_ref,
    CONVERT(varchar(8), d._Fld9248_RTRef, 2) AS fld9248_rtref,
    CONVERT(varchar(32), d._Fld9248_RRRef, 2) AS fld9248_rrref,
    CONVERT(varchar(32), d._Fld9251RRef, 2) AS fld9251_ref,
    CONVERT(varchar(32), d._Fld9260RRef, 2) AS fld9260_ref
FROM dbo._Document9230 AS d
JOIN dbo._Reference64 AS c
    ON d._Fld9234_RTRef = 0x00000040
   AND d._Fld9234_RRRef = c._IDRRef
ORDER BY d._Date_Time DESC, d._Number DESC;
GO

SELECT
    'Document9230_text_bron' AS probe,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CASE WHEN _Fld9234_RTRef = 0x00000040 THEN CONVERT(varchar(32), _Fld9234_RRRef, 2) END) AS distinct_clients,
    MIN(_Date_Time) AS min_doc_date,
    MAX(_Date_Time) AS max_doc_date
FROM dbo._Document9230
WHERE _Fld9258 LIKE N'%брон%'
   OR _Fld9258 LIKE N'%Брон%'
   OR _Fld9259 LIKE N'%брон%'
   OR _Fld9259 LIKE N'%Брон%'
   OR _Fld9262 LIKE N'%брон%'
   OR _Fld9262 LIKE N'%Брон%'
   OR _Fld10087 LIKE N'%брон%'
   OR _Fld10087 LIKE N'%Брон%';
GO

SELECT TOP 80
    'Document9230_text_bron_sample' AS probe,
    d._Number,
    d._Date_Time,
    c._Code AS client_code,
    c._Description AS client_fio,
    d._Fld9258,
    LEFT(d._Fld9259, 400) AS fld9259_text,
    d._Fld9262,
    d._Fld10087
FROM dbo._Document9230 AS d
LEFT JOIN dbo._Reference64 AS c
    ON d._Fld9234_RTRef = 0x00000040
   AND d._Fld9234_RRRef = c._IDRRef
WHERE d._Fld9258 LIKE N'%брон%'
   OR d._Fld9258 LIKE N'%Брон%'
   OR d._Fld9259 LIKE N'%брон%'
   OR d._Fld9259 LIKE N'%Брон%'
   OR d._Fld9262 LIKE N'%брон%'
   OR d._Fld9262 LIKE N'%Брон%'
   OR d._Fld10087 LIKE N'%брон%'
   OR d._Fld10087 LIKE N'%Брон%'
ORDER BY d._Date_Time DESC;
GO

SELECT
    'Reference64_note_bron' AS probe,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), _IDRRef, 2)) AS distinct_clients
FROM dbo._Reference64
WHERE _Fld3818 LIKE N'%брон%'
   OR _Fld3818 LIKE N'%Брон%';
GO

SELECT
    'InfoRg5226_note_bron' AS probe,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CASE WHEN _Fld5227_RTRef = 0x00000040 THEN CONVERT(varchar(32), _Fld5227_RRRef, 2) END) AS distinct_clients,
    MIN(_Period) AS min_period,
    MAX(_Period) AS max_period,
    SUM(CASE WHEN _Period >= DATEADD(day, -90, CONVERT(datetime2, '4026-04-29')) AND _Period < CONVERT(datetime2, '4026-04-30') THEN 1 ELSE 0 END) AS rows_last_90_days_to_cutoff
FROM dbo._InfoRg5226
WHERE _Fld5231 LIKE N'%брон%'
   OR _Fld5231 LIKE N'%Брон%';
GO

SELECT TOP 80
    'InfoRg5226_recent_bron_sample' AS probe,
    c._Code AS client_code,
    c._Description AS client_fio,
    r._Period,
    LEFT(r._Fld5231, 500) AS note
FROM dbo._InfoRg5226 AS r
LEFT JOIN dbo._Reference64 AS c
    ON r._Fld5227_RTRef = 0x00000040
   AND r._Fld5227_RRRef = c._IDRRef
WHERE r._Fld5231 LIKE N'%брон%'
   OR r._Fld5231 LIKE N'%Брон%'
ORDER BY r._Period DESC;
GO
