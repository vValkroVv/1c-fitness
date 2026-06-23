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

IF OBJECT_ID('tempdb..#rg3336') IS NOT NULL
    DROP TABLE #rg3336;

SELECT
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.visit_limit,
    DATEADD(year, -2000, r._Period) AS movement_datetime,
    CONVERT(varchar(8), r._RecorderTRef, 2) AS recorder_tref,
    d163._Number AS recorder_document163_number,
    d150._Number AS recorder_document150_number,
    CONVERT(varchar(2), r._Active, 2) AS active_hex,
    CAST(r._RecordKind AS int) AS record_kind,
    CAST(r._Fld3339 AS decimal(18, 3)) AS qty,
    CAST(r._Fld3340 AS decimal(18, 3)) AS fld3340,
    CAST(r._Fld3341 AS decimal(18, 3)) AS fld3341,
    CAST(r._Fld3342 AS decimal(18, 3)) AS fld3342,
    CAST(r._Fld3343 AS decimal(18, 3)) AS fld3343,
    CAST(r._Fld3344 AS decimal(18, 3)) AS fld3344,
    CAST(r._Fld3345 AS decimal(18, 3)) AS fld3345,
    CAST(r._Fld3346 AS decimal(18, 3)) AS fld3346,
    CAST(r._Fld3347 AS decimal(18, 3)) AS fld3347,
    CONVERT(varchar(2), r._Fld3337_TYPE, 2) AS fld3337_type,
    CONVERT(varchar(8), r._Fld3337_RTRef, 2) AS fld3337_tref,
    CONVERT(varchar(32), r._Fld3337_RRRef, 2) AS fld3337_ref,
    CONVERT(varchar(2), r._Fld3338_TYPE, 2) AS fld3338_type,
    CONVERT(varchar(8), r._Fld3338_RTRef, 2) AS fld3338_tref,
    CONVERT(varchar(32), r._Fld3338_RRRef, 2) AS fld3338_ref,
    CONVERT(varchar(32), r._Fld3348RRef, 2) AS fld3348_ref,
    CONVERT(varchar(32), r._Fld3349RRef, 2) AS fld3349_ref,
    CAST(r._Fld346 AS int) AS fld346
INTO #rg3336
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
  AND DATEADD(year, -2000, r._Period) <= @cutoff_at;

SELECT
    'rg3336_dimension_summary_by_ref' AS probe,
    fld3338_type,
    fld3338_tref,
    fld3338_ref,
    fld3348_ref,
    fld3349_ref,
    record_kind,
    recorder_tref,
    COUNT(*) AS rows_count,
    SUM(qty) AS sum_qty,
    COUNT(DISTINCT document_number) AS contracts_count,
    MIN(movement_datetime) AS min_movement,
    MAX(movement_datetime) AS max_movement
FROM #rg3336
GROUP BY
    fld3338_type,
    fld3338_tref,
    fld3338_ref,
    fld3348_ref,
    fld3349_ref,
    record_kind,
    recorder_tref
ORDER BY record_kind, recorder_tref, sum_qty DESC, rows_count DESC;

SELECT
    'rg3336_dimension_summary_by_contract_ref' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    fld3338_type,
    fld3338_tref,
    fld3338_ref,
    fld3348_ref,
    fld3349_ref,
    SUM(CASE WHEN record_kind = 0 THEN qty ELSE 0 END) AS receipt_qty,
    SUM(CASE WHEN record_kind = 1 THEN qty ELSE 0 END) AS expense_qty,
    SUM(CASE WHEN record_kind = 0 THEN qty WHEN record_kind = 1 THEN -qty ELSE 0 END) AS signed_balance,
    SUM(CASE WHEN recorder_tref = '00000096' AND record_kind = 1 THEN qty ELSE 0 END) AS visit_doc_expense_qty,
    COUNT(*) AS rows_count
FROM #rg3336
GROUP BY
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    fld3338_type,
    fld3338_tref,
    fld3338_ref,
    fld3348_ref,
    fld3349_ref
ORDER BY document_number, receipt_qty DESC, expense_qty DESC, fld3348_ref, fld3338_ref;

SELECT TOP (120)
    'rg3336_receipt_and_visit_samples' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    visit_limit,
    movement_datetime,
    recorder_tref,
    COALESCE(recorder_document163_number, recorder_document150_number) AS recorder_number,
    record_kind,
    qty,
    fld3338_type,
    fld3338_tref,
    fld3338_ref,
    fld3348_ref,
    fld3349_ref,
    fld3340,
    fld3341,
    fld3342,
    fld3343,
    fld3344,
    fld3345,
    fld3346,
    fld3347,
    fld346
FROM #rg3336
WHERE qty <> 0
ORDER BY document_number, movement_datetime, recorder_tref, record_kind, fld3348_ref, fld3338_ref;

