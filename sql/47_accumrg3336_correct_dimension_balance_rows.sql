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

SELECT
    'balance_row' AS row_type,
    s.subscription_ref,
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.visit_limit,
    CONVERT(varchar(10), s.sale_date, 120) AS sale_date,
    CONVERT(varchar(10), s.start_date, 120) AS start_date,
    CONVERT(varchar(10), s.end_date, 120) AS end_date,
    s.is_active_by_dates_on_cutoff,
    s.is_finished_by_dates_before_cutoff,
    COALESCE(SUM(CASE WHEN r.record_kind = 0 THEN r.qty ELSE 0 END), 0) AS receipt_qty,
    COALESCE(SUM(CASE WHEN r.record_kind = 1 THEN r.qty ELSE 0 END), 0) AS expense_qty,
    COALESCE(SUM(r.signed_qty), 0) AS signed_balance,
    COALESCE(SUM(CASE WHEN r.recorder_tref = '00000096' AND r.record_kind = 1 THEN r.qty ELSE 0 END), 0) AS visit_doc_expense_qty,
    COUNT(CASE WHEN r.record_kind = 0 THEN 1 END) AS receipt_rows,
    COUNT(CASE WHEN r.record_kind = 1 THEN 1 END) AS expense_rows,
    CONVERT(varchar(19), MIN(r.movement_datetime), 120) AS first_movement_datetime,
    CONVERT(varchar(19), MAX(r.movement_datetime), 120) AS last_movement_datetime,
    CASE
        WHEN COALESCE(SUM(CASE WHEN r.record_kind = 0 THEN r.qty ELSE 0 END), 0) = s.visit_limit
         AND COALESCE(SUM(r.signed_qty), 0) BETWEEN 0 AND s.visit_limit
        THEN N'clean_register_balance'
        WHEN COALESCE(SUM(CASE WHEN r.record_kind = 0 THEN r.qty ELSE 0 END), 0) = 0
         AND COALESCE(SUM(CASE WHEN r.record_kind = 1 THEN r.qty ELSE 0 END), 0) = 0
        THEN N'no_register_movements'
        WHEN COALESCE(SUM(CASE WHEN r.record_kind = 0 THEN r.qty ELSE 0 END), 0) = 0
         AND COALESCE(SUM(CASE WHEN r.record_kind = 1 THEN r.qty ELSE 0 END), 0) > 0
        THEN N'expense_without_receipt'
        WHEN COALESCE(SUM(CASE WHEN r.record_kind = 0 THEN r.qty ELSE 0 END), 0) <> s.visit_limit
        THEN N'receipt_not_equal_name_limit'
        WHEN COALESCE(SUM(r.signed_qty), 0) < 0
        THEN N'negative_balance'
        WHEN COALESCE(SUM(r.signed_qty), 0) > s.visit_limit
        THEN N'balance_above_name_limit'
        ELSE N'other'
    END AS case_group
FROM #limited_subrent AS s
LEFT JOIN #rg3336_correct_dimension AS r
  ON r.subscription_ref = s.subscription_ref
GROUP BY
    s.subscription_ref,
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.visit_limit,
    s.sale_date,
    s.start_date,
    s.end_date,
    s.is_active_by_dates_on_cutoff,
    s.is_finished_by_dates_before_cutoff
ORDER BY s.document_number;
