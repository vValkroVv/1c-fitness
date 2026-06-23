SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_sql_at datetime2(0) = DATEADD(year, 2000, @cutoff_at);

WITH direct_candidates AS (
    SELECT DISTINCT
        f.subscription_ref,
        f.document_number AS membership_number,
        f.client_id,
        f.effective_client_fio,
        f.subscription_name,
        f.sale_datetime AS membership_sale_datetime,
        f.rg_price,
        f.matched_payment_ref,
        p._IDRRef AS payment_ref_bin,
        CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
        p._Number AS payment_number,
        CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
        END AS payment_datetime,
        CAST(p._Fld1080 AS decimal(15, 2)) AS payment_amount,
        pm._Description AS payment_method,
        op._Description AS payment_operation
    FROM fitbase_part2.membership_import_facts AS f
    JOIN dbo._Document163 AS m
      ON CONVERT(varchar(32), m._IDRRef, 2) = f.subscription_ref
    JOIN dbo._Document154_VT1137 AS vt154
      ON vt154._Fld1148_RTRef = 0x000000A3
     AND vt154._Fld1148_RRRef = m._IDRRef
    JOIN dbo._Document154 AS d154
      ON d154._IDRRef = vt154._Document154_IDRRef
     AND d154._Marked = 0x00
    JOIN dbo._Document152_VT1083 AS vt152
      ON vt152._Fld1087_RTRef = 0x0000009A
     AND vt152._Fld1087_RRRef = d154._IDRRef
    JOIN dbo._Document152 AS p
      ON p._IDRRef = vt152._Document152_IDRRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = p._Fld1072RRef
    WHERE p._Posted = 0x01
      AND p._Marked = 0x00
      AND p._Date_Time <= @cutoff_sql_at
      AND p._Fld1080 > 0
),
ranked_direct AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY subscription_ref
            ORDER BY
                CASE
                    WHEN payment_method IS NULL OR LTRIM(RTRIM(payment_method)) = N'' THEN 3
                    WHEN LOWER(payment_method) LIKE N'%сбп%'
                      OR LOWER(payment_method) LIKE N'%сбпр%'
                      OR LOWER(payment_method) LIKE N'%налич%'
                      OR LOWER(payment_method) LIKE N'%эквайр%'
                      OR LOWER(payment_method) LIKE N'%банк%'
                      OR LOWER(payment_method) LIKE N'%безнал%'
                      OR LOWER(payment_method) LIKE N'%терминал%'
                      OR LOWER(payment_method) LIKE N'%карта%'
                      OR LOWER(payment_method) LIKE N'%р/с%' THEN 0
                    ELSE 1
                END,
                ABS(DATEDIFF(second, payment_datetime, membership_sale_datetime)),
                payment_datetime DESC,
                payment_ref
        ) AS rn
    FROM direct_candidates
)
SELECT
    'direct_match_impact_current_stage' AS probe,
    CASE WHEN matched_payment_ref IS NULL THEN 'currently_no_match' ELSE 'currently_matched' END AS current_state,
    CASE WHEN rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END AS price_bucket,
    COUNT_BIG(*) AS subscriptions
FROM ranked_direct
WHERE rn = 1
GROUP BY
    CASE WHEN matched_payment_ref IS NULL THEN 'currently_no_match' ELSE 'currently_matched' END,
    CASE WHEN rg_price = 0 THEN 'price_zero' ELSE 'price_positive' END
ORDER BY current_state, price_bucket;

WITH direct_candidates AS (
    SELECT DISTINCT
        f.subscription_ref,
        f.rg_price,
        f.matched_payment_ref,
        pm._Description AS payment_method
    FROM fitbase_part2.membership_import_facts AS f
    JOIN dbo._Document163 AS m
      ON CONVERT(varchar(32), m._IDRRef, 2) = f.subscription_ref
    JOIN dbo._Document154_VT1137 AS vt154
      ON vt154._Fld1148_RTRef = 0x000000A3
     AND vt154._Fld1148_RRRef = m._IDRRef
    JOIN dbo._Document154 AS d154
      ON d154._IDRRef = vt154._Document154_IDRRef
     AND d154._Marked = 0x00
    JOIN dbo._Document152_VT1083 AS vt152
      ON vt152._Fld1087_RTRef = 0x0000009A
     AND vt152._Fld1087_RRRef = d154._IDRRef
    JOIN dbo._Document152 AS p
      ON p._IDRRef = vt152._Document152_IDRRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    WHERE f.matched_payment_ref IS NULL
      AND p._Posted = 0x01
      AND p._Marked = 0x00
      AND p._Date_Time <= @cutoff_sql_at
      AND p._Fld1080 > 0
),
ranked_direct AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY subscription_ref
            ORDER BY
                CASE
                    WHEN payment_method IS NULL OR LTRIM(RTRIM(payment_method)) = N'' THEN 3
                    WHEN LOWER(payment_method) LIKE N'%сбп%'
                      OR LOWER(payment_method) LIKE N'%сбпр%'
                      OR LOWER(payment_method) LIKE N'%налич%'
                      OR LOWER(payment_method) LIKE N'%эквайр%'
                      OR LOWER(payment_method) LIKE N'%банк%'
                      OR LOWER(payment_method) LIKE N'%безнал%'
                      OR LOWER(payment_method) LIKE N'%терминал%'
                      OR LOWER(payment_method) LIKE N'%карта%'
                      OR LOWER(payment_method) LIKE N'%р/с%' THEN 0
                    ELSE 1
                END
        ) AS rn
    FROM direct_candidates
)
SELECT
    'current_no_match_direct_method_buckets' AS probe,
    CASE
        WHEN payment_method IS NULL OR LTRIM(RTRIM(payment_method)) = N'' THEN N'<empty>'
        ELSE payment_method
    END AS payment_method,
    CASE
        WHEN payment_method IS NULL OR LTRIM(RTRIM(payment_method)) = N'' THEN 'blank'
        WHEN LOWER(payment_method) LIKE N'%сбп%'
          OR LOWER(payment_method) LIKE N'%сбпр%' THEN 'mappable_sbp'
        WHEN LOWER(payment_method) LIKE N'%налич%'
          AND LOWER(payment_method) NOT LIKE N'%безнал%' THEN 'mappable_cash'
        WHEN LOWER(payment_method) LIKE N'%эквайр%'
          OR LOWER(payment_method) LIKE N'%банк%'
          OR LOWER(payment_method) LIKE N'%безнал%'
          OR LOWER(payment_method) LIKE N'%терминал%'
          OR LOWER(payment_method) LIKE N'%карта%'
          OR LOWER(payment_method) LIKE N'%р/с%' THEN 'mappable_cashless'
        ELSE 'unmapped'
    END AS map_bucket,
    COUNT_BIG(*) AS subscriptions
FROM ranked_direct
WHERE rn = 1
GROUP BY
    CASE
        WHEN payment_method IS NULL OR LTRIM(RTRIM(payment_method)) = N'' THEN N'<empty>'
        ELSE payment_method
    END,
    CASE
        WHEN payment_method IS NULL OR LTRIM(RTRIM(payment_method)) = N'' THEN 'blank'
        WHEN LOWER(payment_method) LIKE N'%сбп%'
          OR LOWER(payment_method) LIKE N'%сбпр%' THEN 'mappable_sbp'
        WHEN LOWER(payment_method) LIKE N'%налич%'
          AND LOWER(payment_method) NOT LIKE N'%безнал%' THEN 'mappable_cash'
        WHEN LOWER(payment_method) LIKE N'%эквайр%'
          OR LOWER(payment_method) LIKE N'%банк%'
          OR LOWER(payment_method) LIKE N'%безнал%'
          OR LOWER(payment_method) LIKE N'%терминал%'
          OR LOWER(payment_method) LIKE N'%карта%'
          OR LOWER(payment_method) LIKE N'%р/с%' THEN 'mappable_cashless'
        ELSE 'unmapped'
    END
ORDER BY subscriptions DESC;

WITH direct_candidates AS (
    SELECT DISTINCT
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
        ROW_NUMBER() OVER (
            PARTITION BY f.subscription_ref
            ORDER BY
                CASE
                    WHEN pm._Description IS NULL OR LTRIM(RTRIM(pm._Description)) = N'' THEN 3
                    WHEN LOWER(pm._Description) LIKE N'%сбп%'
                      OR LOWER(pm._Description) LIKE N'%сбпр%'
                      OR LOWER(pm._Description) LIKE N'%налич%'
                      OR LOWER(pm._Description) LIKE N'%эквайр%'
                      OR LOWER(pm._Description) LIKE N'%банк%'
                      OR LOWER(pm._Description) LIKE N'%безнал%'
                      OR LOWER(pm._Description) LIKE N'%терминал%'
                      OR LOWER(pm._Description) LIKE N'%карта%'
                      OR LOWER(pm._Description) LIKE N'%р/с%' THEN 0
                    ELSE 1
                END,
                ABS(DATEDIFF(second,
                    CASE WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END,
                    f.sale_datetime
                )),
                p._Date_Time DESC
        ) AS rn
    FROM fitbase_part2.membership_import_facts AS f
    JOIN dbo._Document163 AS m
      ON CONVERT(varchar(32), m._IDRRef, 2) = f.subscription_ref
    JOIN dbo._Document154_VT1137 AS vt154
      ON vt154._Fld1148_RTRef = 0x000000A3
     AND vt154._Fld1148_RRRef = m._IDRRef
    JOIN dbo._Document154 AS d154
      ON d154._IDRRef = vt154._Document154_IDRRef
     AND d154._Marked = 0x00
    JOIN dbo._Document152_VT1083 AS vt152
      ON vt152._Fld1087_RTRef = 0x0000009A
     AND vt152._Fld1087_RRRef = d154._IDRRef
    JOIN dbo._Document152 AS p
      ON p._IDRRef = vt152._Document152_IDRRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = p._Fld1072RRef
    WHERE f.matched_payment_ref IS NULL
      AND p._Posted = 0x01
      AND p._Marked = 0x00
      AND p._Date_Time <= @cutoff_sql_at
      AND p._Fld1080 > 0
)
SELECT TOP (80)
    'current_no_match_direct_examples' AS probe,
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
    payment_operation
FROM direct_candidates
WHERE rn = 1
ORDER BY membership_sale_datetime DESC, payment_datetime DESC;
