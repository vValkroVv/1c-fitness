SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#targets') IS NOT NULL DROP TABLE #targets;
IF OBJECT_ID('tempdb..#facts') IS NOT NULL DROP TABLE #facts;
IF OBJECT_ID('tempdb..#sale_docs') IS NOT NULL DROP TABLE #sale_docs;
IF OBJECT_ID('tempdb..#operations') IS NOT NULL DROP TABLE #operations;
IF OBJECT_ID('tempdb..#doc_refs') IS NOT NULL DROP TABLE #doc_refs;
IF OBJECT_ID('tempdb..#payments') IS NOT NULL DROP TABLE #payments;
IF OBJECT_ID('tempdb..#register_related') IS NOT NULL DROP TABLE #register_related;
IF OBJECT_ID('tempdb..#register_client') IS NOT NULL DROP TABLE #register_client;

CREATE TABLE #targets (
    contract_id nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    problem_group nvarchar(120) COLLATE DATABASE_DEFAULT NOT NULL
);

INSERT INTO #targets(contract_id, problem_group)
VALUES
    (N'00000149776', N'no-payment: manager says payment exists'),
    (N'00000150179', N'no-payment: manager says 50% installment paid'),
    (N'00000150540', N'no-payment: manager says payment exists'),
    (N'00000134419', N'no-payment: manager says extra sale'),
    (N'00000143904', N'no-payment: manager says extra sale'),
    (N'00000149797', N'no-payment: manager says extra sale'),
    (N'00000142446', N'no-payment: manager says extra sale with visits'),
    (N'00000138477', N'zero-direct: active full, freeze/modifier chain'),
    (N'00000135375', N'zero-direct: active full, clean payment chain'),
    (N'00000114583', N'zero-direct: historical full, contract/payment chain'),
    (N'00000115678', N'zero-direct: week fitness + doplata'),
    (N'00000145694', N'payment-left: auxiliary sale/emulator candidate');

SELECT
    t.problem_group,
    f.document_number AS contract_id,
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    f.client_ref,
    CONVERT(binary(16), f.client_ref, 2) AS client_ref_bin,
    f.client_id,
    f.effective_client_fio AS client_fio,
    f.subscription_name,
    f.status,
    f.sale_datetime,
    CAST(f.start_date AS date) AS start_date,
    CAST(f.end_date AS date) AS end_date,
    f.rg_price,
    f.rg_paid_candidate,
    f.rg_payment_count_candidate,
    f.matched_payment_ref,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    f.membership_sale_line_amount,
    f.document131_posted_unmarked_refund_count
INTO #facts
FROM #targets AS t
JOIN fitbase_part2.membership_import_facts AS f
  ON f.document_number = t.contract_id;

SELECT
    f.contract_id,
    d154._IDRRef AS sale_doc_ref_bin,
    CONVERT(varchar(32), d154._IDRRef, 2) AS sale_doc_ref,
    d154._Number AS sale_number,
    CASE WHEN d154._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d154._Date_Time) ELSE d154._Date_Time END AS sale_datetime,
    d154._Posted AS sale_posted,
    d154._Marked AS sale_marked,
    SUM(CAST(line._Fld1160 AS decimal(15, 2))) AS sale_line_sum,
    COUNT_BIG(*) AS sale_line_count
INTO #sale_docs
FROM #facts AS f
JOIN dbo._Document154_VT1137 AS line
  ON line._Fld1148_RTRef = 0x000000A3
 AND line._Fld1148_RRRef = f.subscription_ref_bin
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = line._Document154_IDRRef
GROUP BY
    f.contract_id,
    d154._IDRRef,
    CONVERT(varchar(32), d154._IDRRef, 2),
    d154._Number,
    CASE WHEN d154._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d154._Date_Time) ELSE d154._Date_Time END,
    d154._Posted,
    d154._Marked;

SELECT
    f.contract_id,
    d138._IDRRef AS operation_ref_bin,
    CONVERT(varchar(32), d138._IDRRef, 2) AS operation_ref,
    d138._Number AS operation_number,
    CASE WHEN d138._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d138._Date_Time) ELSE d138._Date_Time END AS operation_datetime,
    d138._Posted AS operation_posted,
    d138._Marked AS operation_marked,
    mod._Description AS operation_name,
    old_client._Code AS old_client_id,
    old_client._Description AS old_client_fio,
    new_client._Code AS new_client_id,
    new_client._Description AS new_client_fio,
    CAST(d138._Fld775 AS decimal(15, 2)) AS amount_or_days_candidate
INTO #operations
FROM #facts AS f
JOIN dbo._Document138 AS d138
  ON d138._Fld763RRef = f.subscription_ref_bin
LEFT JOIN dbo._Reference72 AS mod
  ON mod._IDRRef = d138._Fld764RRef
LEFT JOIN dbo._Reference64 AS old_client
  ON old_client._IDRRef = d138._Fld762RRef
LEFT JOIN dbo._Reference64 AS new_client
  ON new_client._IDRRef = d138._Fld767RRef
WHERE CASE WHEN d138._Date_Time > '3000-01-01'
           THEN DATEADD(year, -2000, d138._Date_Time) ELSE d138._Date_Time END <= @cutoff_at;

CREATE TABLE #doc_refs (
    contract_id nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
    doc_kind nvarchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
    doc_tref binary(4) NOT NULL,
    doc_ref binary(16) NOT NULL,
    doc_number nvarchar(32) COLLATE DATABASE_DEFAULT NULL,
    doc_datetime datetime2(0) NULL,
    doc_label nvarchar(300) COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT contract_id, N'Document163 membership', 0x000000A3, subscription_ref_bin, contract_id, sale_datetime, subscription_name
FROM #facts;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT contract_id, N'Document154 sale', 0x0000009A, sale_doc_ref_bin, sale_number, sale_datetime,
       CONCAT(N'sale_line_sum=', sale_line_sum)
FROM #sale_docs;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT contract_id, N'Document138 operation', 0x0000008A, operation_ref_bin, operation_number, operation_datetime, operation_name
FROM #operations;

SELECT DISTINCT
    dr.contract_id,
    dr.doc_kind AS matched_to_doc_kind,
    dr.doc_number AS matched_to_doc_number,
    p._IDRRef AS payment_ref_bin,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    p._Number AS payment_number,
    CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    CAST(p._Fld1080 AS decimal(15, 2)) AS payment_total,
    pm._Description AS payment_method,
    op._Description AS payment_operation,
    CONVERT(varchar(8), vt._Fld1087_RTRef, 2) AS vt1087_tref
INTO #payments
FROM #doc_refs AS dr
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = dr.doc_tref
 AND vt._Fld1087_RRRef = dr.doc_ref
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT DISTINCT
    contract_id,
    N'Document152 payment',
    0x00000098,
    payment_ref_bin,
    payment_number,
    payment_datetime,
    CONCAT(N'payment_total=', payment_total, N'; ', COALESCE(payment_method, N'<empty method>'))
FROM #payments;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT DISTINCT
    sd.contract_id,
    N'Document131 refund',
    0x00000083,
    r._IDRRef,
    r._Number,
    CASE WHEN r._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, r._Date_Time) ELSE r._Date_Time END,
    CONCAT(N'refund_sum_548=', CAST(r._Fld548 AS decimal(15, 2)), N'; refund_sum_549=', CAST(r._Fld549 AS decimal(15, 2)))
FROM #sale_docs AS sd
JOIN dbo._Document131 AS r
  ON r._Fld545_RRRef = sd.sale_doc_ref_bin
  OR r._Fld547_RRRef = sd.sale_doc_ref_bin
WHERE r._Posted = 0x01
  AND r._Marked = 0x00;

SELECT DISTINCT
    dr.contract_id,
    dr.doc_kind AS related_doc_kind,
    dr.doc_number AS related_doc_number,
    CASE WHEN rg._Period > '3000-01-01'
         THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END AS movement_datetime,
    CONVERT(varchar(8), rg._RecorderTRef, 2) AS recorder_tref,
    CASE
        WHEN rg._RecorderTRef = 0x00000098 THEN p._Number
        WHEN rg._RecorderTRef = 0x0000009A THEN s._Number
        WHEN rg._RecorderTRef = 0x00000083 THEN r._Number
        WHEN rg._RecorderTRef = 0x0000008A THEN ch._Number
        WHEN rg._RecorderTRef = 0x000000A3 THEN m._Number
        ELSE CONVERT(varchar(32), rg._RecorderRRef, 2)
    END AS recorder_number,
    rg._RecordKind AS record_kind,
    client._Code AS register_client_id,
    client._Description AS register_client_fio,
    CONVERT(varchar(8), rg._Fld3308_RTRef, 2) AS linked_doc_tref,
    linked_sale._Number AS linked_sale_number,
    CAST(rg._Fld3311 AS decimal(15, 2)) AS amount_3311,
    CAST(rg._Fld3312 AS decimal(15, 2)) AS amount_3312,
    CAST(rg._Fld9180 AS decimal(15, 2)) AS amount_9180
INTO #register_related
FROM #doc_refs AS dr
JOIN dbo._AccumRg3305 AS rg
  ON (
        rg._RecorderTRef = dr.doc_tref
    AND rg._RecorderRRef = dr.doc_ref
  )
  OR (
        rg._Fld3308_RTRef = dr.doc_tref
    AND rg._Fld3308_RRRef = dr.doc_ref
  )
LEFT JOIN dbo._Reference64 AS client
  ON rg._Fld3307_RTRef = 0x00000040
 AND client._IDRRef = rg._Fld3307_RRRef
LEFT JOIN dbo._Document152 AS p
  ON rg._RecorderTRef = 0x00000098 AND p._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document154 AS s
  ON rg._RecorderTRef = 0x0000009A AND s._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document131 AS r
  ON rg._RecorderTRef = 0x00000083 AND r._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document138 AS ch
  ON rg._RecorderTRef = 0x0000008A AND ch._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document163 AS m
  ON rg._RecorderTRef = 0x000000A3 AND m._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document154 AS linked_sale
  ON rg._Fld3308_RTRef = 0x0000009A
 AND linked_sale._IDRRef = rg._Fld3308_RRRef;

SELECT
    f.contract_id,
    CASE WHEN rg._Period > '3000-01-01'
         THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END AS movement_datetime,
    CONVERT(varchar(8), rg._RecorderTRef, 2) AS recorder_tref,
    CASE
        WHEN rg._RecorderTRef = 0x00000098 THEN p._Number
        WHEN rg._RecorderTRef = 0x0000009A THEN s._Number
        WHEN rg._RecorderTRef = 0x00000083 THEN r._Number
        ELSE CONVERT(varchar(32), rg._RecorderRRef, 2)
    END AS recorder_number,
    rg._RecordKind AS record_kind,
    linked_sale._Number AS linked_sale_number,
    CAST(rg._Fld3311 AS decimal(15, 2)) AS amount_3311,
    pm._Description AS payment_method_if_payment_recorder
INTO #register_client
FROM #facts AS f
JOIN dbo._AccumRg3305 AS rg
  ON rg._Fld3307_RTRef = 0x00000040
 AND rg._Fld3307_RRRef = f.client_ref_bin
 AND CASE WHEN rg._Period > '3000-01-01'
          THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END >= DATEADD(day, -180, f.sale_datetime)
 AND CASE WHEN rg._Period > '3000-01-01'
          THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END < DATEADD(day, 181, f.sale_datetime)
LEFT JOIN dbo._Document152 AS p
  ON rg._RecorderTRef = 0x00000098 AND p._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Document154 AS s
  ON rg._RecorderTRef = 0x0000009A AND s._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document131 AS r
  ON rg._RecorderTRef = 0x00000083 AND r._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document154 AS linked_sale
  ON rg._Fld3308_RTRef = 0x0000009A
 AND linked_sale._IDRRef = rg._Fld3308_RRRef;

PRINT '01 source table scale';
SELECT N'_Document163 memberships' AS source_name, COUNT_BIG(*) AS rows_count FROM dbo._Document163
UNION ALL SELECT N'_Document154 sales', COUNT_BIG(*) FROM dbo._Document154
UNION ALL SELECT N'_Document154_VT1137 sale lines', COUNT_BIG(*) FROM dbo._Document154_VT1137
UNION ALL SELECT N'_Document152 payments', COUNT_BIG(*) FROM dbo._Document152
UNION ALL SELECT N'_Document152_VT1083 payment links', COUNT_BIG(*) FROM dbo._Document152_VT1083
UNION ALL SELECT N'_Document138 membership operations', COUNT_BIG(*) FROM dbo._Document138
UNION ALL SELECT N'_AccumRg3305 payment/debt movements', COUNT_BIG(*) FROM dbo._AccumRg3305
UNION ALL SELECT N'_DocumentJournal1621', COUNT_BIG(*) FROM dbo._DocumentJournal1621
UNION ALL SELECT N'_DataHistoryVersions', COUNT_BIG(*) FROM dbo._DataHistoryVersions;

PRINT '02 per-target report-like availability';
SELECT
    f.contract_id,
    f.problem_group,
    f.client_id,
    f.client_fio,
    f.subscription_name,
    f.status,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    COUNT(DISTINCT sd.sale_doc_ref) AS sale_doc_count,
    COUNT(DISTINCT op.operation_ref) AS operation_count,
    COUNT(DISTINCT pay.payment_ref) AS direct_payment_doc_count,
    COUNT(DISTINCT CONCAT(rr.movement_datetime, N'|', rr.recorder_tref, N'|', rr.recorder_number, N'|', rr.record_kind, N'|', rr.amount_3311)) AS related_register_movement_count,
    COUNT(DISTINCT CONCAT(rc.movement_datetime, N'|', rc.recorder_tref, N'|', rc.recorder_number, N'|', rc.record_kind, N'|', rc.amount_3311)) AS client_register_movement_180d_count,
    SUM(CASE WHEN rc.record_kind = 1 THEN rc.amount_3311 ELSE 0 END) AS client_register_sales_180d,
    SUM(CASE WHEN rc.record_kind = 0 THEN rc.amount_3311 ELSE 0 END) AS client_register_payments_180d
FROM #facts AS f
LEFT JOIN #sale_docs AS sd
  ON sd.contract_id = f.contract_id
LEFT JOIN #operations AS op
  ON op.contract_id = f.contract_id
LEFT JOIN #payments AS pay
  ON pay.contract_id = f.contract_id
LEFT JOIN #register_related AS rr
  ON rr.contract_id = f.contract_id
LEFT JOIN #register_client AS rc
  ON rc.contract_id = f.contract_id
GROUP BY
    f.contract_id,
    f.problem_group,
    f.client_id,
    f.client_fio,
    f.subscription_name,
    f.status,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source
ORDER BY f.contract_id;

PRINT '03 reconstructed subordination docs';
SELECT
    contract_id,
    doc_kind,
    doc_number,
    doc_datetime,
    doc_label,
    CONVERT(varchar(8), doc_tref, 2) AS doc_tref,
    CONVERT(varchar(32), doc_ref, 2) AS doc_ref
FROM #doc_refs
ORDER BY contract_id, doc_datetime, doc_kind, doc_number;

PRINT '04 membership operations Document138';
SELECT
    contract_id,
    operation_number,
    operation_datetime,
    operation_posted,
    operation_marked,
    operation_name,
    old_client_id,
    old_client_fio,
    new_client_id,
    new_client_fio,
    amount_or_days_candidate
FROM #operations
ORDER BY contract_id, operation_datetime, operation_number;

PRINT '05 payment documents linked via subordination docs';
SELECT
    contract_id,
    matched_to_doc_kind,
    matched_to_doc_number,
    payment_number,
    payment_datetime,
    payment_total,
    payment_method,
    payment_operation,
    vt1087_tref
FROM #payments
ORDER BY contract_id, payment_datetime, payment_number;

PRINT '06 register movements for related docs';
SELECT
    contract_id,
    related_doc_kind,
    related_doc_number,
    movement_datetime,
    recorder_tref,
    recorder_number,
    record_kind,
    linked_sale_number,
    amount_3311,
    amount_3312,
    amount_9180
FROM #register_related
ORDER BY contract_id, movement_datetime, recorder_number, record_kind;

PRINT '07 payment/debt register by client around target sale date (+/- 180 days)';
SELECT
    contract_id,
    movement_datetime,
    recorder_tref,
    recorder_number,
    record_kind,
    linked_sale_number,
    amount_3311,
    payment_method_if_payment_recorder
FROM #register_client
ORDER BY contract_id, movement_datetime, recorder_number, record_kind;

PRINT '08 document journal 1621 client rows around target sale date (+/- 180 days)';
SELECT
    f.contract_id,
    CASE WHEN j._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, j._Date_Time) ELSE j._Date_Time END AS journal_datetime,
    CONVERT(varchar(8), j._DocumentTRef, 2) AS document_tref,
    j._Number AS document_number,
    j._Posted,
    j._Marked,
    CONVERT(varchar(8), j._Fld1623_RTRef, 2) AS client_rtref
FROM #facts AS f
JOIN dbo._DocumentJournal1621 AS j
  ON j._Fld1623_RTRef = 0x00000040
 AND j._Fld1623_RRRef = f.client_ref_bin
 AND CASE WHEN j._Date_Time > '3000-01-01'
          THEN DATEADD(year, -2000, j._Date_Time) ELSE j._Date_Time END >= DATEADD(day, -180, f.sale_datetime)
 AND CASE WHEN j._Date_Time > '3000-01-01'
          THEN DATEADD(year, -2000, j._Date_Time) ELSE j._Date_Time END < DATEADD(day, 181, f.sale_datetime)
ORDER BY f.contract_id, journal_datetime, document_number;

PRINT '09 data history tables';
SELECT
    table_name,
    rows_count
FROM (
    SELECT N'_DataHistoryAfterWriteQueue' AS table_name, COUNT_BIG(*) AS rows_count FROM dbo._DataHistoryAfterWriteQueue
    UNION ALL SELECT N'_DataHistoryLatestVersions', COUNT_BIG(*) FROM dbo._DataHistoryLatestVersions
    UNION ALL SELECT N'_DataHistoryLatestVersions1', COUNT_BIG(*) FROM dbo._DataHistoryLatestVersions1
    UNION ALL SELECT N'_DataHistoryLatestVersions2', COUNT_BIG(*) FROM dbo._DataHistoryLatestVersions2
    UNION ALL SELECT N'_DataHistoryMetadata', COUNT_BIG(*) FROM dbo._DataHistoryMetadata
    UNION ALL SELECT N'_DataHistoryQueue0', COUNT_BIG(*) FROM dbo._DataHistoryQueue0
    UNION ALL SELECT N'_DataHistorySettings', COUNT_BIG(*) FROM dbo._DataHistorySettings
    UNION ALL SELECT N'_DataHistoryVersions', COUNT_BIG(*) FROM dbo._DataHistoryVersions
) AS x
ORDER BY table_name;
