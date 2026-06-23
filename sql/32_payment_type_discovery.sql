SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#document152_doc163_matches') IS NOT NULL
    DROP TABLE #document152_doc163_matches;

CREATE TABLE #document152_doc163_matches (
    source_column nvarchar(128) NOT NULL,
    matched_rows bigint NOT NULL,
    distinct_payments bigint NOT NULL,
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
WHERE t.name = N'_Document152'
  AND ty.name = N'binary'
  AND c.max_length = 16
ORDER BY c.column_id;

OPEN column_cursor;
FETCH NEXT FROM column_cursor INTO @column_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #document152_doc163_matches (
    source_column,
    matched_rows,
    distinct_payments,
    distinct_memberships,
    sample_payment_number,
    sample_membership_number,
    sample_payment_method
)
SELECT
    @column_name,
    COUNT_BIG(*) AS matched_rows,
    COUNT(DISTINCT p._IDRRef) AS distinct_payments,
    COUNT(DISTINCT m._IDRRef) AS distinct_memberships,
    MIN(p._Number) AS sample_payment_number,
    MIN(m._Number) AS sample_membership_number,
    MIN(pm._Description) AS sample_payment_method
FROM dbo._Document152 AS p
JOIN dbo._Document163 AS m
  ON p.' + QUOTENAME(@column_name) + N' = m._IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Date_Time <= DATEADD(year, 2000, @cutoff_at);';

    EXEC sp_executesql
        @sql,
        N'@column_name nvarchar(128), @cutoff_at datetime2(0)',
        @column_name = @column_name,
        @cutoff_at = @cutoff_at;

    FETCH NEXT FROM column_cursor INTO @column_name;
END

CLOSE column_cursor;
DEALLOCATE column_cursor;

SELECT *
FROM #document152_doc163_matches
WHERE matched_rows > 0
ORDER BY matched_rows DESC;

SELECT TOP (100)
    'direct_payment_by_membership_sample' AS probe,
    f.client_id,
    f.effective_client_fio,
    f.document_number AS membership_number,
    f.subscription_name,
    f.sale_datetime AS membership_sale_datetime,
    f.rg_price,
    p._Number AS payment_number,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    p._Fld1080 AS payment_amount,
    pm._Description AS payment_method,
    op._Description AS operation_name,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CONVERT(varchar(32), p._Fld1060RRef, 2) AS fld1060_ref
FROM fitbase_part2.membership_import_facts AS f
JOIN dbo._Document163 AS m
  ON CONVERT(varchar(32), m._IDRRef, 2) = f.subscription_ref
JOIN dbo._Document152 AS p
  ON p._Fld1060RRef = m._IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
WHERE f.matched_payment_ref IS NULL
  AND f.rg_price > 0
  AND p._Posted = 0x01
  AND p._Marked = 0x00
ORDER BY f.sale_datetime DESC;

SELECT
    'no_match_recoverable_by_direct_membership_link' AS probe,
    CASE WHEN f.rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END AS price_bucket,
    COUNT_BIG(*) AS rows_count
FROM fitbase_part2.membership_import_facts AS f
WHERE f.matched_payment_ref IS NULL
  AND EXISTS (
      SELECT 1
      FROM dbo._Document152 AS p
      JOIN dbo._Document163 AS m
        ON m._IDRRef = p._Fld1060RRef
      WHERE CONVERT(varchar(32), m._IDRRef, 2) = f.subscription_ref
        AND p._Posted = 0x01
        AND p._Marked = 0x00
        AND p._Fld1080 > 0
  )
GROUP BY CASE WHEN f.rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END;

WITH no_match AS (
    SELECT f.*
    FROM fitbase_part2.membership_import_facts AS f
    WHERE f.matched_payment_ref IS NULL
),
nearest AS (
    SELECT
        n.subscription_ref,
        n.rg_price,
        n.product_class,
        n.subscription_name,
        n.sale_datetime,
        p.sale_ref,
        p.sale_datetime AS payment_datetime,
        p.amount,
        p.payment_method,
        ABS(DATEDIFF(day, p.sale_datetime, n.sale_datetime)) AS abs_day_diff,
        DATEDIFF(day, n.sale_datetime, p.sale_datetime) AS signed_day_diff
    FROM no_match AS n
    OUTER APPLY (
        SELECT TOP (1) p.*
        FROM fitbase_part2.stg_sales_all AS p
        WHERE p.sale_source = N'dbo._Document152'
          AND p.amount IS NOT NULL
          AND p.amount > 0
          AND p.sale_datetime <= @cutoff_at
          AND p.client_ref IN (
              n.client_ref,
              n.original_client_ref,
              n.holder_client_ref,
              n.payer_client_ref
          )
        ORDER BY
            ABS(DATEDIFF(second, p.sale_datetime, n.sale_datetime)),
            p.sale_datetime DESC
    ) AS p
)
SELECT
    CASE
        WHEN sale_ref IS NULL THEN 'no_payment_for_client_refs'
        WHEN abs_day_diff <= 14 THEN 'within_14_but_not_matched'
        WHEN abs_day_diff <= 30 THEN '15_30_days'
        WHEN abs_day_diff <= 90 THEN '31_90_days'
        WHEN abs_day_diff <= 365 THEN '91_365_days'
        ELSE 'over_365_days'
    END AS nearest_payment_bucket,
    CASE WHEN rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END AS price_bucket,
    COUNT_BIG(*) AS rows_count
FROM nearest
GROUP BY
    CASE
        WHEN sale_ref IS NULL THEN 'no_payment_for_client_refs'
        WHEN abs_day_diff <= 14 THEN 'within_14_but_not_matched'
        WHEN abs_day_diff <= 30 THEN '15_30_days'
        WHEN abs_day_diff <= 90 THEN '31_90_days'
        WHEN abs_day_diff <= 365 THEN '91_365_days'
        ELSE 'over_365_days'
    END,
    CASE WHEN rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END
ORDER BY rows_count DESC;
