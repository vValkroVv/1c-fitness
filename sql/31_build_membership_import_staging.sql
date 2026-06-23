SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID(N'fitbase_part2.membership_import_facts', N'U') IS NOT NULL
    DROP TABLE fitbase_part2.membership_import_facts;

IF OBJECT_ID('tempdb..#direct_membership_payments') IS NOT NULL
    DROP TABLE #direct_membership_payments;

SELECT DISTINCT
    CONVERT(varchar(32), membership_doc._IDRRef, 2) AS subscription_ref,
    CONVERT(varchar(32), p._IDRRef, 2) AS sale_ref,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS sale_datetime,
    CAST(p._Fld1080 AS decimal(15, 2)) AS amount,
    pm._Description AS payment_method,
    op._Description AS operation_name,
    N'direct_doc152_vt1083_doc154_vt1137_doc163' AS match_source,
    0 AS match_priority
INTO #direct_membership_payments
FROM dbo._Document163 AS membership_doc
JOIN dbo._Document154_VT1137 AS sale_line
  ON sale_line._Fld1148_RTRef = 0x000000A3
 AND sale_line._Fld1148_RRRef = membership_doc._IDRRef
JOIN dbo._Document154 AS sale_doc
  ON sale_doc._IDRRef = sale_line._Document154_IDRRef
 AND sale_doc._Posted = 0x01
 AND sale_doc._Marked = 0x00
JOIN dbo._Document152_VT1083 AS payment_line
  ON payment_line._Fld1087_RTRef = 0x0000009A
 AND payment_line._Fld1087_RRRef = sale_doc._IDRRef
JOIN dbo._Document152 AS p
  ON p._IDRRef = payment_line._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Fld1080 IS NOT NULL
  AND p._Fld1080 > 0
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END <= @cutoff_at;

CREATE INDEX IX_direct_membership_payments_subscription_ref
    ON #direct_membership_payments(subscription_ref);

WITH membership_source AS (
    SELECT
        s.*,
        d._Number AS document_number,
        d._Fld1481 AS doc_duration_value,
        r._Fld3065 AS rg_duration_days,
        r._Fld3068 AS rg_freeze_days,
        r._Fld3069 AS rg_guests,
        r._Fld3070 AS rg_price,
        r._Fld3072 AS rg_paid_candidate,
        r._Fld5963 AS rg_payment_count_candidate,
        r._Fld8007 AS rg_visits_candidate_8007,
        r._Fld8008 AS rg_visits_candidate_8008,
        r._Fld8009 AS rg_visits_candidate_8009,
        CASE WHEN LOWER(s.subscription_name) LIKE N'%субаренд%' THEN 1 ELSE 0 END AS is_subrent,
        CASE
            WHEN LOWER(s.subscription_name) LIKE N'%субаренд%'
             AND LOWER(s.subscription_name) NOT LIKE N'%безлимит%' THEN 1
            ELSE 0
        END AS is_limited_subrent
    FROM fitbase_part2.stg_subscriptions_all AS s
    JOIN dbo._Document163 AS d
      ON CONVERT(varchar(32), d._IDRRef, 2) = s.subscription_ref
    LEFT JOIN dbo._InfoRg3060 AS r
      ON r._Fld3061RRef = d._IDRRef
    WHERE s.sale_datetime <= @cutoff_at
      AND (
          s.product_class IN (N'full_subscription', N'trial_or_guest')
          OR LOWER(s.subscription_name) LIKE N'%субаренд%'
      )
),
with_payment AS (
    SELECT
        ms.*,
        pay.sale_ref AS matched_payment_ref,
        pay.sale_datetime AS matched_payment_datetime,
        pay.amount AS matched_payment_amount,
        pay.payment_method AS matched_payment_method,
        pay.operation_name AS matched_payment_operation,
        pay.match_source AS matched_payment_match_source
    FROM membership_source AS ms
    OUTER APPLY (
        SELECT TOP (1)
            candidates.sale_ref,
            candidates.sale_datetime,
            candidates.amount,
            candidates.payment_method,
            candidates.operation_name,
            candidates.match_source
        FROM (
            SELECT
                direct.sale_ref,
                direct.sale_datetime,
                direct.amount,
                direct.payment_method,
                direct.operation_name,
                direct.match_source,
                direct.match_priority
            FROM #direct_membership_payments AS direct
            WHERE direct.subscription_ref = ms.subscription_ref

            UNION ALL

            SELECT
                p.sale_ref,
                p.sale_datetime,
                p.amount,
                p.payment_method,
                p.operation_name,
                N'client_date_14_days' AS match_source,
                1 AS match_priority
            FROM fitbase_part2.stg_sales_all AS p
            WHERE p.sale_source = N'dbo._Document152'
              AND p.amount IS NOT NULL
              AND p.amount > 0
              AND p.sale_datetime <= @cutoff_at
              AND p.client_ref IN (
                  ms.client_ref,
                  ms.original_client_ref,
                  ms.holder_client_ref,
                  ms.payer_client_ref
              )
              AND ABS(DATEDIFF(day, p.sale_datetime, ms.sale_datetime)) <= 14
        ) AS candidates
        ORDER BY
            candidates.match_priority,
            CASE
                WHEN candidates.payment_method IS NULL OR LTRIM(RTRIM(candidates.payment_method)) = N'' THEN 3
                WHEN LOWER(candidates.payment_method) LIKE N'%сбп%'
                  OR LOWER(candidates.payment_method) LIKE N'%сбпр%'
                  OR LOWER(candidates.payment_method) LIKE N'%налич%'
                  OR LOWER(candidates.payment_method) LIKE N'%эквайр%'
                  OR LOWER(candidates.payment_method) LIKE N'%банк%'
                  OR LOWER(candidates.payment_method) LIKE N'%безнал%'
                  OR LOWER(candidates.payment_method) LIKE N'%терминал%'
                  OR LOWER(candidates.payment_method) LIKE N'%карта%'
                  OR LOWER(candidates.payment_method) LIKE N'%р/с%' THEN 0
                ELSE 1
            END,
            CASE WHEN CONVERT(date, candidates.sale_datetime) = CONVERT(date, ms.sale_datetime) THEN 0 ELSE 1 END,
            ABS(DATEDIFF(second, candidates.sale_datetime, ms.sale_datetime)),
            ABS(COALESCE(candidates.amount, 0) - COALESCE(NULLIF(ms.rg_paid_candidate, 0), NULLIF(ms.rg_price, 0), 0)) ASC,
            candidates.sale_datetime DESC
    ) AS pay
),
with_subrent_visits AS (
    SELECT
        wp.*,
        limit_calc.visit_limit AS subrent_visit_limit,
        CASE
            WHEN wp.is_limited_subrent = 1
             AND wp.start_date <= CAST(@cutoff_at AS date)
             AND wp.end_date >= CAST(@cutoff_at AS date)
            THEN 1
            ELSE 0
        END AS subrent_active_by_dates_on_cutoff,
        CASE
            WHEN wp.is_limited_subrent = 1
             AND wp.end_date < CAST(@cutoff_at AS date)
            THEN 1
            ELSE 0
        END AS subrent_finished_by_dates_before_cutoff,
        COALESCE(balance.receipt_qty, 0) AS subrent_rg3336_receipt_qty,
        COALESCE(balance.expense_qty, 0) AS subrent_rg3336_expense_qty,
        COALESCE(balance.signed_balance, 0) AS subrent_rg3336_signed_balance,
        COALESCE(balance.visit_doc_expense_qty, 0) AS subrent_rg3336_visit_doc_expense_qty,
        COALESCE(balance.receipt_rows, 0) AS subrent_rg3336_receipt_rows,
        COALESCE(balance.expense_rows, 0) AS subrent_rg3336_expense_rows,
        CASE
            WHEN wp.is_limited_subrent = 0 THEN N''
            WHEN COALESCE(balance.receipt_qty, 0) = limit_calc.visit_limit
             AND COALESCE(balance.signed_balance, 0) BETWEEN 0 AND limit_calc.visit_limit
            THEN N'clean_register_balance'
            WHEN COALESCE(balance.receipt_qty, 0) = 0
             AND COALESCE(balance.expense_qty, 0) = 0
            THEN N'no_register_movements'
            WHEN COALESCE(balance.receipt_qty, 0) = 0
             AND COALESCE(balance.expense_qty, 0) > 0
            THEN N'expense_without_receipt'
            WHEN COALESCE(balance.receipt_qty, 0) <> limit_calc.visit_limit
            THEN N'receipt_not_equal_name_limit'
            WHEN COALESCE(balance.signed_balance, 0) < 0
            THEN N'negative_balance'
            WHEN COALESCE(balance.signed_balance, 0) > limit_calc.visit_limit
            THEN N'balance_above_name_limit'
            ELSE N'other'
        END AS subrent_rg3336_case_group
    FROM with_payment AS wp
    CROSS APPLY (
        SELECT CASE
            WHEN wp.is_limited_subrent = 1 AND LOWER(wp.subscription_name) LIKE N'%20 посещ%' THEN 20
            WHEN wp.is_limited_subrent = 1 AND LOWER(wp.subscription_name) LIKE N'%15 посещ%' THEN 15
            WHEN wp.is_limited_subrent = 1 AND LOWER(wp.subscription_name) LIKE N'%12 посещ%' THEN 12
            WHEN wp.is_limited_subrent = 1 AND LOWER(wp.subscription_name) LIKE N'%10 посещ%' THEN 10
            WHEN wp.is_limited_subrent = 1 AND LOWER(wp.subscription_name) LIKE N'%8 посещ%' THEN 8
            ELSE 0
        END AS visit_limit
    ) AS limit_calc
    OUTER APPLY (
        SELECT
            SUM(CASE WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS receipt_qty,
            SUM(CASE WHEN r._RecordKind = 1 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS expense_qty,
            SUM(CASE
                WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3))
                WHEN r._RecordKind = 1 THEN -CAST(r._Fld3339 AS decimal(15, 3))
                ELSE 0
            END) AS signed_balance,
            SUM(CASE
                WHEN r._RecorderTRef = 0x00000096 AND r._RecordKind = 1
                THEN CAST(r._Fld3339 AS decimal(15, 3))
                ELSE 0
            END) AS visit_doc_expense_qty,
            SUM(CASE WHEN r._RecordKind = 0 THEN 1 ELSE 0 END) AS receipt_rows,
            SUM(CASE WHEN r._RecordKind = 1 THEN 1 ELSE 0 END) AS expense_rows
        FROM dbo._AccumRg3336 AS r
        WHERE wp.is_limited_subrent = 1
          AND r._Active = 0x01
          AND r._Fld3337_RRRef = CONVERT(binary(16), wp.subscription_ref, 2)
          AND r._Fld3338_TYPE = 0x01
          AND r._Fld3338_RTRef = 0x00000000
          AND r._Fld3338_RRRef = 0x00000000000000000000000000000000
          AND r._Fld3339 <> 0
          AND DATEADD(year, -2000, r._Period) <= @cutoff_at
    ) AS balance
)
SELECT
    client_ref,
    client_id,
    original_client_ref,
    original_client_id,
    original_client_fio,
    effective_client_ref,
    effective_client_id,
    effective_client_fio,
    owner_change_ref,
    owner_change_number,
    owner_change_datetime,
    owner_change_old_client_ref,
    owner_change_new_client_ref,
    owner_change_modifier_name,
    owner_change_count_for_membership,
    subscription_ref,
    document_number,
    holder_client_ref,
    payer_client_ref,
    client_role_source,
    product_ref,
    product_code,
    subscription_name,
    product_class,
    is_full_subscription,
    is_trial_or_guest,
    is_subrent,
    is_limited_subrent,
    sale_date,
    sale_datetime,
    start_date,
    end_date,
    duration_days,
    status,
    booking_status_ref,
    booking_status_name,
    doc_posted,
    doc_marked,
    register_duration_days,
    is_active_on_cutoff,
    is_finished_before_cutoff,
    days_to_end,
    days_since_end,
    raw_club,
    normalized_club,
    club_source,
    raw_source,
    CAST(COALESCE(doc_duration_value, 0) AS decimal(15, 2)) AS doc_duration_value,
    CAST(COALESCE(rg_duration_days, 0) AS decimal(15, 2)) AS rg_duration_days,
    CAST(COALESCE(rg_freeze_days, 0) AS decimal(15, 2)) AS rg_freeze_days,
    CAST(COALESCE(rg_guests, 0) AS decimal(15, 2)) AS rg_guests,
    CAST(COALESCE(rg_price, 0) AS decimal(15, 2)) AS rg_price,
    CAST(COALESCE(rg_paid_candidate, 0) AS decimal(15, 2)) AS rg_paid_candidate,
    CAST(COALESCE(rg_payment_count_candidate, 0) AS decimal(15, 2)) AS rg_payment_count_candidate,
    CAST(COALESCE(rg_visits_candidate_8007, 0) AS decimal(15, 2)) AS rg_visits_candidate_8007,
    CAST(COALESCE(rg_visits_candidate_8008, 0) AS decimal(15, 2)) AS rg_visits_candidate_8008,
    CAST(COALESCE(rg_visits_candidate_8009, 0) AS decimal(15, 2)) AS rg_visits_candidate_8009,
    CAST(COALESCE(subrent_visit_limit, 0) AS decimal(15, 2)) AS subrent_visit_limit,
    subrent_active_by_dates_on_cutoff,
    subrent_finished_by_dates_before_cutoff,
    CAST(COALESCE(subrent_rg3336_receipt_qty, 0) AS decimal(15, 3)) AS subrent_rg3336_receipt_qty,
    CAST(COALESCE(subrent_rg3336_expense_qty, 0) AS decimal(15, 3)) AS subrent_rg3336_expense_qty,
    CAST(COALESCE(subrent_rg3336_signed_balance, 0) AS decimal(15, 3)) AS subrent_rg3336_signed_balance,
    CAST(COALESCE(subrent_rg3336_visit_doc_expense_qty, 0) AS decimal(15, 3)) AS subrent_rg3336_visit_doc_expense_qty,
    subrent_rg3336_receipt_rows,
    subrent_rg3336_expense_rows,
    subrent_rg3336_case_group,
    matched_payment_ref,
    matched_payment_datetime,
    CAST(COALESCE(matched_payment_amount, 0) AS decimal(15, 2)) AS matched_payment_amount,
    matched_payment_method,
    matched_payment_operation,
    matched_payment_match_source,
    @cutoff_at AS cutoff_at
INTO fitbase_part2.membership_import_facts
FROM with_subrent_visits;

CREATE INDEX IX_membership_import_facts_client_id
    ON fitbase_part2.membership_import_facts(client_id);

CREATE INDEX IX_membership_import_facts_subscription_ref
    ON fitbase_part2.membership_import_facts(subscription_ref);

SELECT
    'membership_import_facts' AS table_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS distinct_clients,
    COUNT(DISTINCT subscription_ref) AS distinct_subscriptions,
    SUM(CASE WHEN is_subrent = 1 THEN 1 ELSE 0 END) AS subrent_rows,
    SUM(CASE WHEN is_limited_subrent = 1 THEN 1 ELSE 0 END) AS limited_subrent_rows,
    SUM(CASE WHEN owner_change_ref IS NOT NULL AND owner_change_ref <> '' THEN 1 ELSE 0 END) AS owner_change_rows
FROM fitbase_part2.membership_import_facts;

SELECT
    product_class,
    is_subrent,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS distinct_clients
FROM fitbase_part2.membership_import_facts
GROUP BY product_class, is_subrent
ORDER BY rows_count DESC;
