SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#final_active_contracts') IS NOT NULL
    DROP TABLE #final_active_contracts;

CREATE TABLE #final_active_contracts (
    document_number nvarchar(20) COLLATE Cyrillic_General_CI_AS NOT NULL PRIMARY KEY
);

INSERT INTO #final_active_contracts(document_number)
VALUES
    (N'00000149952'),
    (N'00000149697'),
    (N'00000150143'),
    (N'00000149696'),
    (N'00000150128'),
    (N'00000150231'),
    (N'00000150029'),
    (N'00000149630'),
    (N'00000149628'),
    (N'00000149980'),
    (N'00000150031'),
    (N'00000149921');

IF OBJECT_ID('tempdb..#active_subrent') IS NOT NULL
    DROP TABLE #active_subrent;

SELECT
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_date,
    f.start_date,
    f.end_date,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    CASE
        WHEN f.subscription_name LIKE N'%20 посещ%' THEN 20
        WHEN f.subscription_name LIKE N'%15 посещ%' THEN 15
        WHEN f.subscription_name LIKE N'%12 посещ%' THEN 12
        WHEN f.subscription_name LIKE N'%10 посещ%' THEN 10
        WHEN f.subscription_name LIKE N'%8 посещ%' THEN 8
        ELSE NULL
    END AS visit_limit
INTO #active_subrent
FROM fitbase_part2.membership_import_facts AS f
JOIN #final_active_contracts AS c
  ON c.document_number = f.document_number;

IF OBJECT_ID('tempdb..#correct_dimension_movements') IS NOT NULL
    DROP TABLE #correct_dimension_movements;

SELECT
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.visit_limit,
    s.start_date,
    s.end_date,
    DATEADD(year, -2000, r._Period) AS movement_datetime,
    CONVERT(varchar(8), r._RecorderTRef, 2) AS recorder_tref,
    COALESCE(d163._Number, d150._Number) AS recorder_number,
    CAST(r._LineNo AS int) AS line_no,
    CAST(r._RecordKind AS int) AS record_kind,
    CAST(r._Fld3339 AS decimal(18, 3)) AS qty,
    CAST(CASE
        WHEN r._RecordKind = 0 THEN r._Fld3339
        WHEN r._RecordKind = 1 THEN -r._Fld3339
        ELSE 0
    END AS decimal(18, 3)) AS signed_qty,
    CONVERT(varchar(2), r._Fld3338_TYPE, 2) AS fld3338_type,
    CONVERT(varchar(8), r._Fld3338_RTRef, 2) AS fld3338_tref,
    CONVERT(varchar(32), r._Fld3338_RRRef, 2) AS fld3338_ref,
    CONVERT(varchar(32), r._Fld3348RRef, 2) AS fld3348_ref,
    CONVERT(varchar(32), r._Fld3349RRef, 2) AS fld3349_ref,
    CAST(r._Fld3341 AS decimal(18, 3)) AS fld3341,
    CAST(r._Fld3343 AS decimal(18, 3)) AS fld3343
INTO #correct_dimension_movements
FROM #active_subrent AS s
JOIN dbo._AccumRg3336 AS r
  ON r._Fld3337_RRRef = s.subscription_ref_bin
LEFT JOIN dbo._Document163 AS d163
  ON r._RecorderTRef = 0x000000A3
 AND r._RecorderRRef = d163._IDRRef
LEFT JOIN dbo._Document150 AS d150
  ON r._RecorderTRef = 0x00000096
 AND r._RecorderRRef = d150._IDRRef
WHERE r._Active = 0x01
  AND DATEADD(year, -2000, r._Period) <= @cutoff_at
  -- This is the visit-balance dimension. The second receipt dimension
  -- (_Fld3338_TYPE = 0x08) duplicates the limit but is not spent by visits.
  AND r._Fld3338_TYPE = 0x01
  AND r._Fld3338_RTRef = 0x00000000
  AND r._Fld3338_RRRef = 0x00000000000000000000000000000000
  AND r._Fld3339 <> 0;

SELECT
    'correct_dimension_summary' AS probe,
    COUNT(DISTINCT document_number) AS active_limited_contracts,
    (SELECT SUM(visit_limit) FROM #active_subrent) AS total_name_limit,
    SUM(CASE WHEN record_kind = 0 THEN qty ELSE 0 END) AS receipt_qty,
    SUM(CASE WHEN record_kind = 1 THEN qty ELSE 0 END) AS expense_qty,
    SUM(signed_qty) AS signed_balance
FROM #correct_dimension_movements;

SELECT
    'correct_dimension_by_contract' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    MIN(start_date) AS start_date,
    MIN(end_date) AS end_date,
    SUM(CASE WHEN record_kind = 0 THEN qty ELSE 0 END) AS receipt_qty,
    SUM(CASE WHEN record_kind = 1 THEN qty ELSE 0 END) AS expense_qty,
    SUM(signed_qty) AS visits_left_by_register,
    SUM(CASE WHEN recorder_tref = '00000096' AND record_kind = 1 THEN qty ELSE 0 END) AS visit_doc_expense_qty,
    COUNT(CASE WHEN record_kind = 0 THEN 1 END) AS receipt_rows,
    COUNT(CASE WHEN record_kind = 1 THEN 1 END) AS expense_rows
FROM #correct_dimension_movements
GROUP BY
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit
ORDER BY document_number;

WITH ordered AS (
    SELECT
        document_number,
        client_id,
        effective_client_fio,
        subscription_name,
        visit_limit,
        movement_datetime,
        recorder_tref,
        recorder_number,
        line_no,
        record_kind,
        qty,
        signed_qty,
        SUM(signed_qty) OVER (
            PARTITION BY document_number
            ORDER BY movement_datetime, recorder_tref, recorder_number, line_no, record_kind
            ROWS UNBOUNDED PRECEDING
        ) AS balance_after_movement,
        ROW_NUMBER() OVER (
            PARTITION BY document_number
            ORDER BY movement_datetime, recorder_tref, recorder_number, line_no, record_kind
        ) AS movement_no
    FROM #correct_dimension_movements
)
SELECT
    'correct_dimension_sequence_samples' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    movement_no,
    movement_datetime,
    CASE
        WHEN record_kind = 0 THEN N'receipt'
        WHEN record_kind = 1 THEN N'expense'
        ELSE N'unknown'
    END AS movement_kind,
    qty,
    signed_qty,
    balance_after_movement,
    recorder_tref,
    recorder_number
FROM ordered
WHERE document_number IN (N'00000149696', N'00000150029', N'00000149628', N'00000149952')
ORDER BY document_number, movement_no;

WITH ordered AS (
    SELECT
        document_number,
        client_id,
        effective_client_fio,
        subscription_name,
        visit_limit,
        movement_datetime,
        recorder_tref,
        recorder_number,
        line_no,
        record_kind,
        qty,
        signed_qty,
        SUM(signed_qty) OVER (
            PARTITION BY document_number
            ORDER BY movement_datetime, recorder_tref, recorder_number, line_no, record_kind
            ROWS UNBOUNDED PRECEDING
        ) AS balance_after_movement,
        ROW_NUMBER() OVER (
            PARTITION BY document_number
            ORDER BY movement_datetime, recorder_tref, recorder_number, line_no, record_kind
        ) AS movement_no
    FROM #correct_dimension_movements
)
SELECT
    'correct_dimension_negative_or_overrun_checks' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    MIN(balance_after_movement) AS min_balance_after_movement,
    MAX(balance_after_movement) AS max_balance_after_movement,
    SUM(CASE WHEN balance_after_movement < 0 THEN 1 ELSE 0 END) AS negative_balance_steps,
    SUM(CASE WHEN balance_after_movement > visit_limit THEN 1 ELSE 0 END) AS above_limit_steps
FROM ordered
GROUP BY
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit
ORDER BY document_number;
