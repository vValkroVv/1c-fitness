SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_sql_at datetime2(0) = DATEADD(year, 2000, @cutoff_at);

IF OBJECT_ID('tempdb..#doc154_doc163_matches') IS NOT NULL
    DROP TABLE #doc154_doc163_matches;

CREATE TABLE #doc154_doc163_matches (
    table_name nvarchar(128) NOT NULL,
    source_column nvarchar(128) NOT NULL,
    matched_rows bigint NOT NULL,
    distinct_doc154 bigint NOT NULL,
    distinct_memberships bigint NOT NULL,
    sample_doc154_number nvarchar(32) NULL,
    sample_membership_number nvarchar(32) NULL
);

DECLARE
    @table_name nvarchar(128),
    @column_name nvarchar(128),
    @sql nvarchar(max);

DECLARE column_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT t.name, c.name
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
WHERE t.name IN (
        N'_Document154',
        N'_Document154_VT1137',
        N'_Document154_VT1162',
        N'_Document154_VT1171',
        N'_Document154_VT1181'
    )
  AND ty.name = N'binary'
  AND c.max_length = 16
ORDER BY t.name, c.column_id;

OPEN column_cursor;
FETCH NEXT FROM column_cursor INTO @table_name, @column_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @table_name = N'_Document154'
    BEGIN
        SET @sql = N'
INSERT INTO #doc154_doc163_matches (
    table_name,
    source_column,
    matched_rows,
    distinct_doc154,
    distinct_memberships,
    sample_doc154_number,
    sample_membership_number
)
SELECT
    @table_name,
    @column_name,
    COUNT_BIG(*) AS matched_rows,
    COUNT(DISTINCT d._IDRRef) AS distinct_doc154,
    COUNT(DISTINCT m._IDRRef) AS distinct_memberships,
    MIN(d._Number) AS sample_doc154_number,
    MIN(m._Number) AS sample_membership_number
FROM dbo._Document154 AS d
JOIN dbo._Document163 AS m
  ON d.' + QUOTENAME(@column_name) + N' = m._IDRRef
WHERE d._Marked = 0x00
  AND d._Date_Time <= @cutoff_sql_at;';
    END
    ELSE
    BEGIN
        SET @sql = N'
INSERT INTO #doc154_doc163_matches (
    table_name,
    source_column,
    matched_rows,
    distinct_doc154,
    distinct_memberships,
    sample_doc154_number,
    sample_membership_number
)
SELECT
    @table_name,
    @column_name,
    COUNT_BIG(*) AS matched_rows,
    COUNT(DISTINCT d._IDRRef) AS distinct_doc154,
    COUNT(DISTINCT m._IDRRef) AS distinct_memberships,
    MIN(d._Number) AS sample_doc154_number,
    MIN(m._Number) AS sample_membership_number
FROM dbo.' + QUOTENAME(@table_name) + N' AS vt
JOIN dbo._Document154 AS d
  ON d._IDRRef = vt._Document154_IDRRef
JOIN dbo._Document163 AS m
  ON vt.' + QUOTENAME(@column_name) + N' = m._IDRRef
WHERE d._Marked = 0x00
  AND d._Date_Time <= @cutoff_sql_at;';
    END

    EXEC sp_executesql
        @sql,
        N'@table_name nvarchar(128), @column_name nvarchar(128), @cutoff_sql_at datetime2(0)',
        @table_name = @table_name,
        @column_name = @column_name,
        @cutoff_sql_at = @cutoff_sql_at;

    FETCH NEXT FROM column_cursor INTO @table_name, @column_name;
END

CLOSE column_cursor;
DEALLOCATE column_cursor;

SELECT *
FROM #doc154_doc163_matches
WHERE matched_rows > 0
ORDER BY matched_rows DESC;

SELECT
    'doc152_vt1087_to_doc154' AS probe,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT p._IDRRef) AS distinct_payments,
    COUNT(DISTINCT d154._IDRRef) AS distinct_doc154,
    MIN(p._Number) AS sample_payment_number,
    MIN(d154._Number) AS sample_doc154_number
FROM dbo._Document152_VT1083 AS vt
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt._Fld1087_RRRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Date_Time <= @cutoff_sql_at;

SELECT TOP (60)
    'doc152_doc154_examples' AS probe,
    p._Number AS payment_number,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    CAST(p._Fld1080 AS decimal(15, 2)) AS payment_amount,
    pm._Description AS payment_method,
    d154._Number AS doc154_number,
    CASE
        WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time)
        ELSE d154._Date_Time
    END AS doc154_datetime,
    d154._Posted AS doc154_posted,
    CONVERT(varchar(8), d154._Fld1131_RTRef, 2) AS doc154_fld1131_rtref,
    CONVERT(varchar(32), d154._Fld1131_RRRef, 2) AS doc154_fld1131_rrref,
    d154._Fld1128 AS doc154_amount,
    d154._Fld1135 AS doc154_comment
FROM dbo._Document152_VT1083 AS vt
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt._Fld1087_RRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Date_Time <= @cutoff_sql_at
ORDER BY p._Date_Time DESC;
