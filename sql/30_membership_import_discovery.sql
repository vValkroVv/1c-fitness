SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

SELECT
    @@SERVERNAME AS server_name,
    DB_NAME() AS database_name,
    @cutoff_at AS cutoff_at;

SELECT
    'source_counts' AS probe,
    'fitbase_part2.stg_subscriptions_all' AS source_name,
    COUNT_BIG(*) AS rows_count
FROM fitbase_part2.stg_subscriptions_all
UNION ALL
SELECT 'source_counts', 'fitbase_part2.stg_sales_all', COUNT_BIG(*)
FROM fitbase_part2.stg_sales_all
UNION ALL
SELECT 'source_counts', 'fitbase_part2.final_funnel_clients', COUNT_BIG(*)
FROM fitbase_part2.final_funnel_clients;

SELECT
    'membership_candidates_in_existing_stage' AS probe,
    product_class,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_ref) AS distinct_clients,
    COUNT(DISTINCT subscription_ref) AS distinct_subscriptions,
    MIN(sale_datetime) AS min_sale_datetime,
    MAX(sale_datetime) AS max_sale_datetime
FROM fitbase_part2.stg_subscriptions_all
WHERE sale_datetime <= @cutoff_at
GROUP BY product_class
ORDER BY rows_count DESC;

SELECT
    t.name AS table_name,
    c.column_id,
    c.name AS column_name,
    ty.name AS type_name,
    c.max_length,
    c.precision,
    c.scale
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
WHERE t.name IN (N'_Document163', N'_InfoRg3060', N'_Document152', N'_Reference72')
ORDER BY t.name, c.column_id;

SELECT TOP (80)
    'document163_inforg3060_recent_memberships' AS probe,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.product_class,
    s.sale_datetime,
    s.start_date,
    s.end_date,
    s.duration_days,
    d._Number AS document_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS document_ref,
    d._Fld1454 AS doc_fld1454,
    d._Fld1461 AS doc_fld1461,
    d._Fld1463 AS doc_fld1463,
    d._Fld1465 AS doc_fld1465,
    d._Fld1466 AS doc_fld1466,
    d._Fld1467 AS doc_fld1467,
    d._Fld1481 AS doc_fld1481,
    d._Fld1485 AS doc_fld1485,
    d._Fld1493 AS doc_fld1493,
    r._Fld3065 AS rg_fld3065,
    r._Fld3066 AS rg_fld3066,
    r._Fld3067 AS rg_fld3067,
    r._Fld3068 AS rg_fld3068,
    r._Fld3069 AS rg_fld3069,
    r._Fld3070 AS rg_fld3070,
    r._Fld3071 AS rg_fld3071,
    r._Fld3072 AS rg_fld3072,
    r._Fld5961 AS rg_fld5961,
    r._Fld5963 AS rg_fld5963,
    r._Fld8007 AS rg_fld8007,
    r._Fld8008 AS rg_fld8008,
    r._Fld8009 AS rg_fld8009
FROM fitbase_part2.stg_subscriptions_all AS s
JOIN dbo._Document163 AS d
  ON CONVERT(varchar(32), d._IDRRef, 2) = s.subscription_ref
LEFT JOIN dbo._InfoRg3060 AS r
  ON r._Fld3061RRef = d._IDRRef
WHERE s.sale_datetime <= @cutoff_at
  AND s.product_class IN (N'full_subscription', N'trial_or_guest')
ORDER BY s.sale_datetime DESC;

SELECT
    'candidate_numeric_nonzero_counts' AS probe,
    COUNT_BIG(*) AS source_rows,
    SUM(CASE WHEN r._Fld3070 <> 0 THEN 1 ELSE 0 END) AS price_fld3070_nonzero,
    SUM(CASE WHEN r._Fld3072 <> 0 THEN 1 ELSE 0 END) AS paid_or_debt_fld3072_nonzero,
    SUM(CASE WHEN r._Fld3068 <> 0 THEN 1 ELSE 0 END) AS freeze_fld3068_nonzero,
    SUM(CASE WHEN r._Fld3069 <> 0 THEN 1 ELSE 0 END) AS guests_fld3069_nonzero,
    SUM(CASE WHEN d._Fld1481 <> 0 THEN 1 ELSE 0 END) AS duration_doc_fld1481_nonzero,
    SUM(CASE WHEN d._Fld1493 <> 0 THEN 1 ELSE 0 END) AS doc_fld1493_nonzero,
    SUM(CASE WHEN r._Fld8007 <> 0 OR r._Fld8008 <> 0 OR r._Fld8009 <> 0 THEN 1 ELSE 0 END) AS rg_8007_8009_nonzero
FROM fitbase_part2.stg_subscriptions_all AS s
JOIN dbo._Document163 AS d
  ON CONVERT(varchar(32), d._IDRRef, 2) = s.subscription_ref
LEFT JOIN dbo._InfoRg3060 AS r
  ON r._Fld3061RRef = d._IDRRef
WHERE s.sale_datetime <= @cutoff_at
  AND s.product_class IN (N'full_subscription', N'trial_or_guest');

SELECT TOP (80)
    'possible_installments_or_debt' AS probe,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.sale_datetime,
    s.start_date,
    s.end_date,
    r._Fld3070 AS price_candidate,
    r._Fld3072 AS paid_or_debt_candidate,
    CASE
        WHEN r._Fld3070 > 0 AND r._Fld3072 > 0 AND r._Fld3072 < r._Fld3070
        THEN r._Fld3070 - r._Fld3072
        ELSE 0
    END AS computed_left_if_fld3072_is_paid,
    r._Fld5963 AS rg_fld5963,
    r._Fld8007,
    r._Fld8008,
    r._Fld8009
FROM fitbase_part2.stg_subscriptions_all AS s
JOIN dbo._Document163 AS d
  ON CONVERT(varchar(32), d._IDRRef, 2) = s.subscription_ref
LEFT JOIN dbo._InfoRg3060 AS r
  ON r._Fld3061RRef = d._IDRRef
WHERE s.sale_datetime <= @cutoff_at
  AND s.product_class IN (N'full_subscription', N'trial_or_guest')
  AND (
      s.subscription_name LIKE N'%рассроч%'
      OR r._Fld3072 > 0
      OR r._Fld8007 <> 0
      OR r._Fld8008 <> 0
      OR r._Fld8009 <> 0
  )
ORDER BY s.sale_datetime DESC;

SELECT
    'owner_change_memberships_for_import' AS probe,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT subscription_ref) AS distinct_subscriptions,
    COUNT(DISTINCT client_ref) AS distinct_effective_clients
FROM fitbase_part2.stg_subscriptions_all
WHERE owner_change_ref IS NOT NULL
  AND owner_change_ref <> ''
  AND sale_datetime <= @cutoff_at
  AND product_class IN (N'full_subscription', N'trial_or_guest');

SELECT TOP (80)
    'owner_change_memberships_sample' AS probe,
    client_id,
    effective_client_fio,
    original_client_id,
    original_client_fio,
    subscription_ref,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    owner_change_number,
    owner_change_datetime,
    owner_change_modifier_name
FROM fitbase_part2.stg_subscriptions_all
WHERE owner_change_ref IS NOT NULL
  AND owner_change_ref <> ''
  AND sale_datetime <= @cutoff_at
  AND product_class IN (N'full_subscription', N'trial_or_guest')
ORDER BY owner_change_datetime DESC, sale_datetime DESC;
