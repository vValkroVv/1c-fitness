USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

SELECT
    'InfoRg3060_summary' AS probe,
    COUNT_BIG(*) AS total_rows,
    MIN(_Fld3062) AS min_fld3062,
    MAX(_Fld3062) AS max_fld3062,
    MIN(_Fld3063) AS min_fld3063,
    MAX(_Fld3063) AS max_fld3063,
    MIN(_Fld3064) AS min_fld3064,
    MAX(_Fld3064) AS max_fld3064,
    SUM(CASE WHEN _Fld3062 >= CONVERT(datetime2, '4026-04-29') THEN 1 ELSE 0 END) AS fld3062_after_cutoff,
    SUM(CASE WHEN _Fld3063 >= CONVERT(datetime2, '4026-04-29') THEN 1 ELSE 0 END) AS fld3063_after_cutoff,
    SUM(CASE WHEN _Fld3064 >= CONVERT(datetime2, '4026-04-29') THEN 1 ELSE 0 END) AS fld3064_after_cutoff
FROM dbo._InfoRg3060;
GO

SELECT '_Fld3061RRef->Document163' AS match_name, COUNT_BIG(*) AS rows_count, COUNT(DISTINCT CONVERT(varchar(32), r._Fld3061RRef, 2)) AS distinct_refs
FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld3061RRef = d._IDRRef
UNION ALL SELECT '_Fld5962RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld5962RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld5962RRef = d._IDRRef
UNION ALL SELECT '_Fld6081RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld6081RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld6081RRef = d._IDRRef
UNION ALL SELECT '_Fld5416RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld5416RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld5416RRef = d._IDRRef
UNION ALL SELECT '_Fld6082RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld6082RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld6082RRef = d._IDRRef
UNION ALL SELECT '_Fld5957RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld5957RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld5957RRef = d._IDRRef
UNION ALL SELECT '_Fld5958RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld5958RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld5958RRef = d._IDRRef
UNION ALL SELECT '_Fld5959RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld5959RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld5959RRef = d._IDRRef
UNION ALL SELECT '_Fld5960RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld5960RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld5960RRef = d._IDRRef
UNION ALL SELECT '_Fld6083RRef->Document163', COUNT_BIG(*), COUNT(DISTINCT CONVERT(varchar(32), r._Fld6083RRef, 2)) FROM dbo._InfoRg3060 AS r JOIN dbo._Document163 AS d ON r._Fld6083RRef = d._IDRRef;
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
WHERE t.name = N'_InfoRg3060'
  AND ty.name = N'binary'
  AND c.max_length = 16
ORDER BY c.column_id;

OPEN source_column_cursor;
FETCH NEXT FROM source_column_cursor INTO @source_column;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
WITH distinct_values AS (
    SELECT DISTINCT ' + QUOTENAME(@source_column) + N' AS ref
    FROM dbo._InfoRg3060
    WHERE ' + QUOTENAME(@source_column) + N' <> 0x00000000000000000000000000000000
)
INSERT INTO #reference_column_matches (
    source_table, source_column, matched_reference_table,
    distinct_matched_values, sample_code, sample_description
)
SELECT
    N''_InfoRg3060'',
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

SELECT
    'InfoRg3060_booking_status_distribution' AS probe,
    st._Code AS status_code,
    st._Description AS status_name,
    CONVERT(varchar(32), r._Fld5960RRef, 2) AS fld5960_ref,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), d._Fld1447_RRRef, 2)) AS distinct_clients,
    SUM(CASE WHEN r._Fld3064 >= CONVERT(datetime2, '4026-04-29') THEN 1 ELSE 0 END) AS rows_active_by_fld3064,
    COUNT(DISTINCT CASE WHEN r._Fld3064 >= CONVERT(datetime2, '4026-04-29') THEN CONVERT(varchar(32), d._Fld1447_RRRef, 2) END) AS active_clients_by_fld3064,
    MIN(r._Fld3062) AS min_sale_or_start,
    MAX(r._Fld3062) AS max_sale_or_start,
    MIN(r._Fld3063) AS min_end_candidate,
    MAX(r._Fld3063) AS max_end_candidate,
    MIN(r._Fld3064) AS min_valid_until_candidate,
    MAX(r._Fld3064) AS max_valid_until_candidate
FROM dbo._InfoRg3060 AS r
JOIN dbo._Document163 AS d
    ON r._Fld3061RRef = d._IDRRef
LEFT JOIN dbo._Reference5062 AS st
    ON r._Fld5960RRef = st._IDRRef
WHERE d._Fld1447_RTRef = 0x00000040
GROUP BY
    st._Code,
    st._Description,
    CONVERT(varchar(32), r._Fld5960RRef, 2)
ORDER BY rows_count DESC;
GO

SELECT TOP 80
    'InfoRg3060_booking_status_sample' AS probe,
    c._Code AS client_code,
    c._Description AS client_fio,
    p._Code AS product_code,
    p._Description AS product_name,
    st._Code AS status_code,
    st._Description AS status_name,
    d._Number AS doc_number,
    d._Date_Time AS doc_date,
    d._Fld1450 AS doc_end,
    r._Fld3062,
    r._Fld3063,
    r._Fld3064,
    r._Fld3065,
    r._Fld3066,
    r._Fld3067,
    r._Fld3068,
    r._Fld3069,
    r._Fld3070
FROM dbo._InfoRg3060 AS r
JOIN dbo._Document163 AS d
    ON r._Fld3061RRef = d._IDRRef
JOIN dbo._Reference64 AS c
    ON d._Fld1447_RTRef = 0x00000040
   AND d._Fld1447_RRRef = c._IDRRef
LEFT JOIN dbo._Reference72 AS p
    ON d._Fld1446RRef = p._IDRRef
LEFT JOIN dbo._Reference5062 AS st
    ON r._Fld5960RRef = st._IDRRef
WHERE st._Description LIKE N'%Брон%'
   OR st._Description LIKE N'%брон%'
ORDER BY r._Fld3064 DESC, r._Fld3063 DESC, r._Fld3062 DESC;
GO

SELECT TOP 80
    'InfoRg3060_by_document163_sample' AS probe,
    c._Code AS client_code,
    c._Description AS client_fio,
    p._Code AS product_code,
    p._Description AS product_name,
    d._Number AS doc_number,
    d._Date_Time AS doc_date,
    d._Fld1450 AS doc_end,
    r._Fld3062,
    r._Fld3063,
    r._Fld3064,
    r._Fld3065,
    r._Fld3066,
    r._Fld3067,
    r._Fld3068,
    r._Fld3069,
    r._Fld3070,
    r._Fld3071,
    r._Fld3072,
    CONVERT(varchar(32), r._Fld3061RRef, 2) AS fld3061_ref,
    CONVERT(varchar(32), r._Fld5962RRef, 2) AS fld5962_ref,
    CONVERT(varchar(32), r._Fld6081RRef, 2) AS fld6081_ref,
    CONVERT(varchar(32), r._Fld5416RRef, 2) AS fld5416_ref,
    CONVERT(varchar(32), r._Fld6082RRef, 2) AS fld6082_ref,
    CONVERT(varchar(32), r._Fld5957RRef, 2) AS fld5957_ref,
    CONVERT(varchar(32), r._Fld5958RRef, 2) AS fld5958_ref,
    CONVERT(varchar(32), r._Fld5959RRef, 2) AS fld5959_ref,
    CONVERT(varchar(32), r._Fld5960RRef, 2) AS fld5960_ref,
    CONVERT(varchar(2), r._Fld6084, 2) AS fld6084_hex
FROM dbo._InfoRg3060 AS r
LEFT JOIN dbo._Document163 AS d
    ON r._Fld3061RRef = d._IDRRef
LEFT JOIN dbo._Reference64 AS c
    ON d._Fld1447_RTRef = 0x00000040
   AND d._Fld1447_RRRef = c._IDRRef
LEFT JOIN dbo._Reference72 AS p
    ON d._Fld1446RRef = p._IDRRef
ORDER BY r._Fld3064 DESC, r._Fld3063 DESC, r._Fld3062 DESC;
GO

SELECT
    'InfoRg3060_active_by_fld3064' AS probe,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), d._Fld1447_RRRef, 2)) AS distinct_clients
FROM dbo._InfoRg3060 AS r
JOIN dbo._Document163 AS d
    ON r._Fld3061RRef = d._IDRRef
WHERE d._Fld1447_RTRef = 0x00000040
  AND d._Posted = 0x01
  AND d._Marked = 0x00
  AND r._Fld3064 >= CONVERT(datetime2, '4026-04-29');
GO

SELECT
    'InfoRg3060_active_by_fld3063' AS probe,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), d._Fld1447_RRRef, 2)) AS distinct_clients
FROM dbo._InfoRg3060 AS r
JOIN dbo._Document163 AS d
    ON r._Fld3061RRef = d._IDRRef
WHERE d._Fld1447_RTRef = 0x00000040
  AND d._Posted = 0x01
  AND d._Marked = 0x00
  AND r._Fld3063 >= CONVERT(datetime2, '4026-04-29');
GO
