SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#limited_subrent') IS NOT NULL
    DROP TABLE #limited_subrent;

SELECT
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_date,
    f.start_date,
    f.end_date,
    f.is_active_on_cutoff,
    f.is_finished_before_cutoff,
    CASE
        WHEN f.start_date <= CAST(@cutoff_at AS date)
         AND f.end_date >= CAST(@cutoff_at AS date)
        THEN 1
        ELSE 0
    END AS is_active_by_dates_on_cutoff,
    CASE
        WHEN f.end_date < CAST(@cutoff_at AS date) THEN 1
        ELSE 0
    END AS is_finished_by_dates_before_cutoff,
    CASE
        WHEN f.subscription_name LIKE N'%20 посещ%' THEN 20
        WHEN f.subscription_name LIKE N'%15 посещ%' THEN 15
        WHEN f.subscription_name LIKE N'%12 посещ%' THEN 12
        WHEN f.subscription_name LIKE N'%10 посещ%' THEN 10
        WHEN f.subscription_name LIKE N'%8 посещ%' THEN 8
        ELSE NULL
    END AS visit_limit
INTO #limited_subrent
FROM fitbase_part2.membership_import_facts AS f
WHERE f.is_limited_subrent = 1;

CREATE INDEX IX_limited_subrent_ref ON #limited_subrent(subscription_ref_bin);

IF OBJECT_ID('tempdb..#rg3336_correct_dimension') IS NOT NULL
    DROP TABLE #rg3336_correct_dimension;

SELECT
    s.subscription_ref,
    DATEADD(year, -2000, r._Period) AS movement_datetime,
    CONVERT(varchar(8), r._RecorderTRef, 2) AS recorder_tref,
    CAST(r._RecordKind AS int) AS record_kind,
    CAST(r._Fld3339 AS decimal(18, 3)) AS qty,
    CAST(CASE
        WHEN r._RecordKind = 0 THEN r._Fld3339
        WHEN r._RecordKind = 1 THEN -r._Fld3339
        ELSE 0
    END AS decimal(18, 3)) AS signed_qty
INTO #rg3336_correct_dimension
FROM #limited_subrent AS s
JOIN dbo._AccumRg3336 AS r
  ON r._Fld3337_RRRef = s.subscription_ref_bin
WHERE r._Active = 0x01
  AND DATEADD(year, -2000, r._Period) <= @cutoff_at
  AND r._Fld3338_TYPE = 0x01
  AND r._Fld3338_RTRef = 0x00000000
  AND r._Fld3338_RRRef = 0x00000000000000000000000000000000
  AND r._Fld3339 <> 0;

CREATE INDEX IX_rg3336_correct_dimension_ref ON #rg3336_correct_dimension(subscription_ref);

IF OBJECT_ID('tempdb..#balance') IS NOT NULL
    DROP TABLE #balance;

SELECT
    s.subscription_ref,
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.sale_date,
    s.start_date,
    s.end_date,
    s.is_active_on_cutoff,
    s.is_finished_before_cutoff,
    s.is_active_by_dates_on_cutoff,
    s.is_finished_by_dates_before_cutoff,
    s.visit_limit,
    COALESCE(SUM(CASE WHEN r.record_kind = 0 THEN r.qty ELSE 0 END), 0) AS receipt_qty,
    COALESCE(SUM(CASE WHEN r.record_kind = 1 THEN r.qty ELSE 0 END), 0) AS expense_qty,
    COALESCE(SUM(r.signed_qty), 0) AS signed_balance,
    COALESCE(SUM(CASE WHEN r.recorder_tref = '00000096' AND r.record_kind = 1 THEN r.qty ELSE 0 END), 0) AS visit_doc_expense_qty,
    COUNT(CASE WHEN r.record_kind = 0 THEN 1 END) AS receipt_rows,
    COUNT(CASE WHEN r.record_kind = 1 THEN 1 END) AS expense_rows,
    MIN(r.movement_datetime) AS first_movement_datetime,
    MAX(r.movement_datetime) AS last_movement_datetime
INTO #balance
FROM #limited_subrent AS s
LEFT JOIN #rg3336_correct_dimension AS r
  ON r.subscription_ref = s.subscription_ref
GROUP BY
    s.subscription_ref,
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.sale_date,
    s.start_date,
    s.end_date,
    s.is_active_on_cutoff,
    s.is_finished_before_cutoff,
    s.is_active_by_dates_on_cutoff,
    s.is_finished_by_dates_before_cutoff,
    s.visit_limit;

SELECT
    'wide_sql_limited_subrent_balance_summary' AS probe,
    COUNT(*) AS fact_rows,
    COUNT(DISTINCT subscription_ref) AS distinct_subscriptions,
    SUM(CASE WHEN is_active_by_dates_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_by_dates_on_cutoff,
    SUM(CASE WHEN is_finished_by_dates_before_cutoff = 1 THEN 1 ELSE 0 END) AS finished_by_dates_before_cutoff,
    SUM(visit_limit) AS total_name_limit,
    SUM(receipt_qty) AS receipt_qty,
    SUM(expense_qty) AS expense_qty,
    SUM(signed_balance) AS signed_balance,
    SUM(CASE WHEN receipt_qty = 0 AND expense_qty = 0 THEN 1 ELSE 0 END) AS no_register_movements,
    SUM(CASE WHEN receipt_qty = 0 AND expense_qty > 0 THEN 1 ELSE 0 END) AS expense_without_receipt,
    SUM(CASE WHEN receipt_qty <> visit_limit THEN 1 ELSE 0 END) AS receipt_not_equal_name_limit,
    SUM(CASE WHEN signed_balance < 0 THEN 1 ELSE 0 END) AS negative_balance,
    SUM(CASE WHEN signed_balance > visit_limit THEN 1 ELSE 0 END) AS balance_above_name_limit,
    SUM(CASE WHEN expense_qty > visit_limit THEN 1 ELSE 0 END) AS expense_above_name_limit
FROM #balance;

SELECT
    'wide_sql_limited_subrent_balance_by_active_status' AS probe,
    CASE
        WHEN is_active_by_dates_on_cutoff = 1 THEN N'active_by_dates'
        ELSE N'finished_or_not_active_by_dates'
    END AS active_status,
    COUNT(*) AS rows_count,
    SUM(visit_limit) AS total_name_limit,
    SUM(receipt_qty) AS receipt_qty,
    SUM(expense_qty) AS expense_qty,
    SUM(signed_balance) AS signed_balance,
    SUM(CASE WHEN receipt_qty = 0 AND expense_qty = 0 THEN 1 ELSE 0 END) AS no_register_movements,
    SUM(CASE WHEN receipt_qty <> visit_limit THEN 1 ELSE 0 END) AS receipt_not_equal_name_limit,
    SUM(CASE WHEN signed_balance < 0 THEN 1 ELSE 0 END) AS negative_balance,
    SUM(CASE WHEN signed_balance > visit_limit THEN 1 ELSE 0 END) AS balance_above_name_limit,
    SUM(CASE WHEN expense_qty > visit_limit THEN 1 ELSE 0 END) AS expense_above_name_limit
FROM #balance
GROUP BY CASE
        WHEN is_active_by_dates_on_cutoff = 1 THEN N'active_by_dates'
        ELSE N'finished_or_not_active_by_dates'
    END
ORDER BY active_status;

SELECT
    'wide_sql_limited_subrent_balance_by_name' AS probe,
    subscription_name,
    COUNT(*) AS rows_count,
    SUM(CASE WHEN is_active_by_dates_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_by_dates_on_cutoff,
    SUM(visit_limit) AS total_name_limit,
    SUM(receipt_qty) AS receipt_qty,
    SUM(expense_qty) AS expense_qty,
    SUM(signed_balance) AS signed_balance,
    SUM(CASE WHEN receipt_qty = 0 AND expense_qty = 0 THEN 1 ELSE 0 END) AS no_register_movements,
    SUM(CASE WHEN receipt_qty <> visit_limit THEN 1 ELSE 0 END) AS receipt_not_equal_name_limit,
    SUM(CASE WHEN signed_balance < 0 THEN 1 ELSE 0 END) AS negative_balance,
    SUM(CASE WHEN signed_balance > visit_limit THEN 1 ELSE 0 END) AS balance_above_name_limit,
    SUM(CASE WHEN expense_qty > visit_limit THEN 1 ELSE 0 END) AS expense_above_name_limit
FROM #balance
GROUP BY subscription_name
ORDER BY subscription_name;

SELECT
    'wide_sql_limited_subrent_balance_case_groups' AS probe,
    CASE
        WHEN receipt_qty = visit_limit AND signed_balance BETWEEN 0 AND visit_limit THEN N'clean_register_balance'
        WHEN receipt_qty = 0 AND expense_qty = 0 THEN N'no_register_movements'
        WHEN receipt_qty = 0 AND expense_qty > 0 THEN N'expense_without_receipt'
        WHEN receipt_qty <> visit_limit THEN N'receipt_not_equal_name_limit'
        WHEN signed_balance < 0 THEN N'negative_balance'
        WHEN signed_balance > visit_limit THEN N'balance_above_name_limit'
        ELSE N'other'
    END AS case_group,
    COUNT(*) AS rows_count,
    SUM(CASE WHEN is_active_by_dates_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_by_dates_on_cutoff,
    SUM(CASE WHEN is_finished_by_dates_before_cutoff = 1 THEN 1 ELSE 0 END) AS finished_by_dates_before_cutoff,
    SUM(visit_limit) AS total_name_limit,
    SUM(receipt_qty) AS receipt_qty,
    SUM(expense_qty) AS expense_qty,
    SUM(signed_balance) AS signed_balance
FROM #balance
GROUP BY CASE
        WHEN receipt_qty = visit_limit AND signed_balance BETWEEN 0 AND visit_limit THEN N'clean_register_balance'
        WHEN receipt_qty = 0 AND expense_qty = 0 THEN N'no_register_movements'
        WHEN receipt_qty = 0 AND expense_qty > 0 THEN N'expense_without_receipt'
        WHEN receipt_qty <> visit_limit THEN N'receipt_not_equal_name_limit'
        WHEN signed_balance < 0 THEN N'negative_balance'
        WHEN signed_balance > visit_limit THEN N'balance_above_name_limit'
        ELSE N'other'
    END
ORDER BY rows_count DESC;

SELECT TOP (80)
    'wide_sql_limited_subrent_anomaly_samples' AS probe,
    CASE
        WHEN receipt_qty = visit_limit AND signed_balance BETWEEN 0 AND visit_limit THEN N'clean_register_balance'
        WHEN receipt_qty = 0 AND expense_qty = 0 THEN N'no_register_movements'
        WHEN receipt_qty = 0 AND expense_qty > 0 THEN N'expense_without_receipt'
        WHEN receipt_qty <> visit_limit THEN N'receipt_not_equal_name_limit'
        WHEN signed_balance < 0 THEN N'negative_balance'
        WHEN signed_balance > visit_limit THEN N'balance_above_name_limit'
        ELSE N'other'
    END AS case_group,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    sale_date,
    start_date,
    end_date,
    is_active_on_cutoff,
    is_active_by_dates_on_cutoff,
    receipt_qty,
    expense_qty,
    signed_balance,
    visit_doc_expense_qty,
    receipt_rows,
    expense_rows,
    first_movement_datetime,
    last_movement_datetime
FROM #balance
WHERE NOT (receipt_qty = visit_limit AND signed_balance BETWEEN 0 AND visit_limit)
ORDER BY
    CASE
        WHEN is_active_by_dates_on_cutoff = 1 THEN 0
        WHEN receipt_qty = 0 AND expense_qty = 0 THEN 1
        WHEN signed_balance < 0 THEN 2
        WHEN receipt_qty <> visit_limit THEN 3
        ELSE 4
    END,
    subscription_name,
    document_number;
