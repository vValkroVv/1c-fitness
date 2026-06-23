SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_date date = CONVERT(date, @cutoff_at);

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
    f.subscription_ref,
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

CREATE INDEX IX_active_subrent_ref ON #active_subrent(subscription_ref_bin);

IF OBJECT_ID('tempdb..#rg3336_active') IS NOT NULL
    DROP TABLE #rg3336_active;

SELECT
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.sale_date,
    s.start_date,
    s.end_date,
    s.visit_limit,
    s.subscription_ref,
    DATEADD(year, -2000, r._Period) AS movement_datetime,
    CONVERT(date, DATEADD(year, -2000, r._Period)) AS movement_date,
    CONVERT(varchar(8), r._RecorderTRef, 2) AS recorder_tref,
    CONVERT(varchar(32), r._RecorderRRef, 2) AS recorder_ref,
    d163._Number AS recorder_document163_number,
    DATEADD(year, -2000, d163._Date_Time) AS recorder_document163_datetime,
    d150._Number AS recorder_document150_number,
    DATEADD(year, -2000, d150._Date_Time) AS recorder_document150_datetime,
    r._LineNo AS line_no,
    CONVERT(varchar(2), r._Active, 2) AS active_hex,
    CAST(r._RecordKind AS int) AS record_kind,
    CAST(r._Fld3339 AS decimal(18, 3)) AS qty,
    CASE
        WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(18, 3))
        WHEN r._RecordKind = 1 THEN -CAST(r._Fld3339 AS decimal(18, 3))
        ELSE CAST(0 AS decimal(18, 3))
    END AS signed_qty,
    CONVERT(varchar(2), r._Fld3337_TYPE, 2) AS fld3337_type,
    CONVERT(varchar(8), r._Fld3337_RTRef, 2) AS fld3337_tref,
    CONVERT(varchar(32), r._Fld3337_RRRef, 2) AS fld3337_ref,
    CONVERT(varchar(2), r._Fld3338_TYPE, 2) AS fld3338_type,
    CONVERT(varchar(8), r._Fld3338_RTRef, 2) AS fld3338_tref,
    CONVERT(varchar(32), r._Fld3338_RRRef, 2) AS fld3338_ref
INTO #rg3336_active
FROM #active_subrent AS s
JOIN dbo._AccumRg3336 AS r
  ON r._Fld3337_RRRef = s.subscription_ref_bin
LEFT JOIN dbo._Document163 AS d163
  ON r._RecorderTRef = 0x000000A3
 AND r._RecorderRRef = d163._IDRRef
LEFT JOIN dbo._Document150 AS d150
  ON r._RecorderTRef = 0x00000096
 AND r._RecorderRRef = d150._IDRRef;

CREATE INDEX IX_rg3336_active_contract_dt
    ON #rg3336_active(document_number, movement_datetime, recorder_tref, recorder_ref);

SELECT
    'rg3336_active_full_summary' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    sale_date,
    start_date,
    end_date,
    visit_limit,
    COUNT(*) AS rg3336_rows_all,
    SUM(CASE WHEN active_hex = '01' THEN 1 ELSE 0 END) AS active_rows_all,
    SUM(CASE WHEN active_hex = '01' AND movement_datetime <= @cutoff_at THEN 1 ELSE 0 END) AS active_rows_to_cutoff,
    SUM(CASE WHEN active_hex = '01' AND record_kind = 0 AND movement_datetime <= @cutoff_at THEN qty ELSE 0 END) AS receipt_qty_to_cutoff,
    SUM(CASE WHEN active_hex = '01' AND record_kind = 1 AND movement_datetime <= @cutoff_at THEN qty ELSE 0 END) AS expense_qty_to_cutoff,
    SUM(CASE WHEN active_hex = '01' AND movement_datetime <= @cutoff_at THEN signed_qty ELSE 0 END) AS balance_qty_to_cutoff,
    visit_limit - SUM(CASE WHEN active_hex = '01' AND record_kind = 1 AND movement_datetime <= @cutoff_at THEN qty ELSE 0 END) AS name_limit_minus_expense,
    MIN(CASE WHEN active_hex = '01' THEN movement_datetime END) AS first_active_movement,
    MAX(CASE WHEN active_hex = '01' THEN movement_datetime END) AS last_active_movement
FROM #rg3336_active
GROUP BY
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    sale_date,
    start_date,
    end_date,
    visit_limit
ORDER BY document_number;

SELECT
    'rg3336_active_recorder_types' AS probe,
    recorder_tref,
    CASE
        WHEN recorder_tref = '000000A3' THEN '_Document163'
        WHEN recorder_tref = '00000096' THEN '_Document150'
        ELSE 'unknown'
    END AS recorder_table_guess,
    record_kind,
    active_hex,
    COUNT(*) AS rows_count,
    SUM(qty) AS sum_qty
FROM #rg3336_active
GROUP BY recorder_tref, record_kind, active_hex
ORDER BY recorder_tref, record_kind, active_hex;

WITH ordered AS (
    SELECT
        *,
        SUM(CASE WHEN active_hex = '01' AND movement_datetime <= @cutoff_at THEN signed_qty ELSE 0 END)
            OVER (
                PARTITION BY document_number
                ORDER BY movement_datetime, recorder_tref, recorder_ref, line_no
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS balance_after_movement,
        ROW_NUMBER() OVER (
            PARTITION BY document_number
            ORDER BY movement_datetime, recorder_tref, recorder_ref, line_no
        ) AS movement_no
    FROM #rg3336_active
    WHERE active_hex = '01'
      AND movement_datetime <= @cutoff_at
)
SELECT
    'rg3336_active_movement_sequence' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    movement_no,
    movement_datetime,
    recorder_tref,
    CASE
        WHEN recorder_tref = '000000A3' THEN '_Document163 sale/membership'
        WHEN recorder_tref = '00000096' THEN '_Document150 visit'
        ELSE 'unknown'
    END AS recorder_table_guess,
    COALESCE(recorder_document163_number, recorder_document150_number, recorder_ref) AS recorder_number,
    record_kind,
    qty,
    signed_qty,
    balance_after_movement,
    recorder_ref
FROM ordered
ORDER BY document_number, movement_no;

SELECT
    'rg3336_active_balance_check' AS probe,
    (SELECT SUM(visit_limit) FROM #active_subrent) AS total_name_limit,
    SUM(CASE WHEN active_hex = '01' AND record_kind = 0 AND movement_datetime <= @cutoff_at THEN qty ELSE 0 END) AS total_receipt_qty_to_cutoff,
    SUM(CASE WHEN active_hex = '01' AND record_kind = 1 AND movement_datetime <= @cutoff_at THEN qty ELSE 0 END) AS total_expense_qty_to_cutoff,
    SUM(CASE WHEN active_hex = '01' AND movement_datetime <= @cutoff_at THEN signed_qty ELSE 0 END) AS total_balance_qty_to_cutoff
FROM #rg3336_active;
