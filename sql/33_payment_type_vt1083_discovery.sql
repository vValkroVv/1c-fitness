SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_sql_at datetime2(0) = DATEADD(year, 2000, @cutoff_at);

IF OBJECT_ID('tempdb..#vt_doc163_matches') IS NOT NULL
    DROP TABLE #vt_doc163_matches;

CREATE TABLE #vt_doc163_matches (
    source_column nvarchar(128) NOT NULL,
    matched_rows bigint NOT NULL,
    distinct_payment_docs bigint NOT NULL,
    distinct_memberships bigint NOT NULL,
    sample_payment_number nvarchar(32) NULL,
    sample_membership_number nvarchar(32) NULL,
    sample_payment_method nvarchar(200) NULL
);

DECLARE
    @column_name nvarchar(128),
    @sql nvarchar(max);

DECLARE column_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT c.name
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
WHERE t.name = N'_Document152_VT1083'
  AND ty.name = N'binary'
  AND c.max_length = 16
ORDER BY c.column_id;

OPEN column_cursor;
FETCH NEXT FROM column_cursor INTO @column_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #vt_doc163_matches (
    source_column,
    matched_rows,
    distinct_payment_docs,
    distinct_memberships,
    sample_payment_number,
    sample_membership_number,
    sample_payment_method
)
SELECT
    @column_name,
    COUNT_BIG(*) AS matched_rows,
    COUNT(DISTINCT p._IDRRef) AS distinct_payment_docs,
    COUNT(DISTINCT m._IDRRef) AS distinct_memberships,
    MIN(p._Number) AS sample_payment_number,
    MIN(m._Number) AS sample_membership_number,
    MIN(pm._Description) AS sample_payment_method
FROM dbo._Document152_VT1083 AS vt
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
JOIN dbo._Document163 AS m
  ON vt.' + QUOTENAME(@column_name) + N' = m._IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Date_Time <= @cutoff_sql_at;';

    EXEC sp_executesql
        @sql,
        N'@column_name nvarchar(128), @cutoff_sql_at datetime2(0)',
        @column_name = @column_name,
        @cutoff_sql_at = @cutoff_sql_at;

    FETCH NEXT FROM column_cursor INTO @column_name;
END

CLOSE column_cursor;
DEALLOCATE column_cursor;

SELECT *
FROM #vt_doc163_matches
WHERE matched_rows > 0
ORDER BY matched_rows DESC;

SELECT
    CONVERT(varchar(8), vt._Fld1087_RTRef, 2) AS fld1087_rtref,
    COUNT_BIG(*) AS rows_count,
    SUM(CASE WHEN m1087._IDRRef IS NOT NULL THEN 1 ELSE 0 END) AS rows_join_document163,
    SUM(CASE WHEN c1087._IDRRef IS NOT NULL THEN 1 ELSE 0 END) AS rows_join_reference64
FROM dbo._Document152_VT1083 AS vt
LEFT JOIN dbo._Document163 AS m1087
  ON m1087._IDRRef = vt._Fld1087_RRRef
LEFT JOIN dbo._Reference64 AS c1087
  ON c1087._IDRRef = vt._Fld1087_RRRef
GROUP BY CONVERT(varchar(8), vt._Fld1087_RTRef, 2)
ORDER BY rows_count DESC;

SELECT
    CONVERT(varchar(8), vt._Fld8771_RTRef, 2) AS fld8771_rtref,
    COUNT_BIG(*) AS rows_count,
    SUM(CASE WHEN m8771._IDRRef IS NOT NULL THEN 1 ELSE 0 END) AS rows_join_document163,
    SUM(CASE WHEN c8771._IDRRef IS NOT NULL THEN 1 ELSE 0 END) AS rows_join_reference64
FROM dbo._Document152_VT1083 AS vt
LEFT JOIN dbo._Document163 AS m8771
  ON m8771._IDRRef = vt._Fld8771_RRRef
LEFT JOIN dbo._Reference64 AS c8771
  ON c8771._IDRRef = vt._Fld8771_RRRef
GROUP BY CONVERT(varchar(8), vt._Fld8771_RTRef, 2)
ORDER BY rows_count DESC;

WITH direct_vt_payment AS (
    SELECT
        f.subscription_ref,
        f.document_number AS membership_number,
        f.client_id,
        f.effective_client_fio,
        f.subscription_name,
        f.sale_datetime AS membership_sale_datetime,
        f.rg_price,
        p._Number AS payment_number,
        CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
        END AS payment_datetime,
        CAST(p._Fld1080 AS decimal(15, 2)) AS payment_amount,
        pm._Description AS payment_method,
        op._Description AS payment_operation,
        CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref
    FROM fitbase_part2.membership_import_facts AS f
    JOIN dbo._Document163 AS m
      ON CONVERT(varchar(32), m._IDRRef, 2) = f.subscription_ref
    JOIN dbo._Document152_VT1083 AS vt
      ON vt._Fld1087_RRRef = m._IDRRef
    JOIN dbo._Document152 AS p
      ON p._IDRRef = vt._Document152_IDRRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = p._Fld1072RRef
    WHERE p._Posted = 0x01
      AND p._Marked = 0x00
      AND p._Date_Time <= @cutoff_sql_at
      AND p._Fld1080 > 0
)
SELECT
    'current_no_match_recoverable_by_vt1087' AS probe,
    CASE WHEN rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END AS price_bucket,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT subscription_ref) AS distinct_subscriptions
FROM direct_vt_payment
WHERE subscription_ref IN (
    SELECT subscription_ref
    FROM fitbase_part2.membership_import_facts
    WHERE matched_payment_ref IS NULL
)
GROUP BY CASE WHEN rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END
ORDER BY rows_count DESC;

SELECT TOP (80)
    'current_no_match_vt1087_examples' AS probe,
    client_id,
    effective_client_fio,
    membership_number,
    subscription_name,
    membership_sale_datetime,
    rg_price,
    payment_number,
    payment_datetime,
    payment_amount,
    payment_method,
    payment_operation,
    payment_ref
FROM direct_vt_payment
WHERE subscription_ref IN (
    SELECT subscription_ref
    FROM fitbase_part2.membership_import_facts
    WHERE matched_payment_ref IS NULL
)
ORDER BY membership_sale_datetime DESC, payment_datetime DESC;
