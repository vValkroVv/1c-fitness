SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#targets') IS NOT NULL DROP TABLE #targets;
IF OBJECT_ID('tempdb..#facts') IS NOT NULL DROP TABLE #facts;
IF OBJECT_ID('tempdb..#sale_docs') IS NOT NULL DROP TABLE #sale_docs;
IF OBJECT_ID('tempdb..#operations') IS NOT NULL DROP TABLE #operations;
IF OBJECT_ID('tempdb..#doc_refs') IS NOT NULL DROP TABLE #doc_refs;

CREATE TABLE #targets (
    contract_id nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    why nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL
);

INSERT INTO #targets(contract_id, why)
VALUES
    (N'00000149776', N'no-payment, business says payment exists'),
    (N'00000150179', N'no-payment, business says 50% installment paid'),
    (N'00000150540', N'no-payment, business says payment exists'),
    (N'00000134419', N'no-payment, business says extra sale'),
    (N'00000143904', N'no-payment, business says extra sale'),
    (N'00000149797', N'no-payment duplicate, business says extra sale'),
    (N'00000142446', N'no-payment with visits, business says extra sale'),
    (N'00000138477', N'zero-direct active full, modifier/freeze chain'),
    (N'00000135375', N'zero-direct active full, freeze/payment chain'),
    (N'00000114583', N'zero-direct historical full, contract/payment chain'),
    (N'00000115678', N'zero-direct week fitness + doplata'),
    (N'00000145694', N'non-named payment_left, auxiliary sale/emulator');

SELECT
    t.why,
    f.document_number AS contract_id,
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    f.client_ref,
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

PRINT '01 target membership facts';
SELECT
    why,
    contract_id,
    client_id,
    client_fio,
    subscription_name,
    status,
    sale_datetime,
    start_date,
    end_date,
    rg_price,
    rg_paid_candidate,
    rg_payment_count_candidate,
    matched_payment_amount,
    matched_payment_method,
    matched_payment_match_source,
    membership_sale_line_amount,
    document131_posted_unmarked_refund_count
FROM #facts
ORDER BY why, contract_id;

SELECT
    f.contract_id,
    CONVERT(varchar(32), d154._IDRRef, 2) AS sale_doc_ref,
    d154._IDRRef AS sale_doc_ref_bin,
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
    CONVERT(varchar(32), d154._IDRRef, 2),
    d154._IDRRef,
    d154._Number,
    CASE WHEN d154._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d154._Date_Time) ELSE d154._Date_Time END,
    d154._Posted,
    d154._Marked;

PRINT '02 structure: membership -> Document154 sale docs';
SELECT *
FROM #sale_docs
ORDER BY contract_id, sale_datetime;

SELECT
    f.contract_id,
    CONVERT(varchar(32), d138._IDRRef, 2) AS operation_ref,
    d138._IDRRef AS operation_ref_bin,
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
    CAST(d138._Fld775 AS decimal(15, 2)) AS amount_or_days_candidate,
    d138._Fld773 AS comment_1,
    d138._Fld771 AS comment_2
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

PRINT '03 operation history: Document138 operations linked to membership';
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
    amount_or_days_candidate,
    LEFT(comment_1, 200) AS comment_1,
    LEFT(comment_2, 200) AS comment_2
FROM #operations
ORDER BY contract_id, operation_datetime, operation_number;

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
SELECT
    contract_id,
    N'Document163 membership',
    0x000000A3,
    subscription_ref_bin,
    contract_id,
    sale_datetime,
    subscription_name
FROM #facts;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT
    contract_id,
    N'Document154 sale',
    0x0000009A,
    sale_doc_ref_bin,
    sale_number,
    sale_datetime,
    CONCAT(N'sale_line_sum=', sale_line_sum)
FROM #sale_docs;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT
    contract_id,
    N'Document138 operation',
    0x0000008A,
    operation_ref_bin,
    operation_number,
    operation_datetime,
    operation_name
FROM #operations;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT DISTINCT
    sd.contract_id,
    N'Document152 payment',
    0x00000098,
    p._IDRRef,
    p._Number,
    CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END,
    CONCAT(N'payment_total=', CAST(p._Fld1080 AS decimal(15, 2)), N'; ', COALESCE(pm._Description, N'<empty method>'))
FROM #sale_docs AS sd
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = 0x0000009A
 AND vt._Fld1087_RRRef = sd.sale_doc_ref_bin
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT DISTINCT
    f.contract_id,
    N'Document152 payment-direct-membership',
    0x00000098,
    p._IDRRef,
    p._Number,
    CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END,
    CONCAT(N'payment_total=', CAST(p._Fld1080 AS decimal(15, 2)), N'; ', COALESCE(pm._Description, N'<empty method>'))
FROM #facts AS f
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = 0x000000A3
 AND vt._Fld1087_RRRef = f.subscription_ref_bin
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00;

INSERT INTO #doc_refs(contract_id, doc_kind, doc_tref, doc_ref, doc_number, doc_datetime, doc_label)
SELECT DISTINCT
    op.contract_id,
    N'Document152 payment-direct-operation',
    0x00000098,
    p._IDRRef,
    p._Number,
    CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END,
    CONCAT(N'payment_total=', CAST(p._Fld1080 AS decimal(15, 2)), N'; ', COALESCE(pm._Description, N'<empty method>'))
FROM #operations AS op
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = 0x0000008A
 AND vt._Fld1087_RRRef = op.operation_ref_bin
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00;

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

PRINT '04 reconstructed structure/subordination docs';
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

PRINT '05 payment Document152 lines linked to sale/membership/operation docs';
SELECT
    dr.contract_id,
    dr.doc_kind AS matched_to_doc_kind,
    dr.doc_number AS matched_to_doc_number,
    p._Number AS payment_number,
    CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    CAST(p._Fld1080 AS decimal(15, 2)) AS payment_total,
    pm._Description AS payment_method,
    op._Description AS payment_operation,
    CONVERT(varchar(8), vt._Fld1087_RTRef, 2) AS vt1087_rtref,
    CONVERT(varchar(32), vt._Fld1087_RRRef, 2) AS vt1087_rrref,
    CONVERT(varchar(8), vt._Fld8771_RTRef, 2) AS vt8771_rtref,
    CONVERT(varchar(32), vt._Fld8771_RRRef, 2) AS vt8771_rrref
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
  AND p._Marked = 0x00
ORDER BY dr.contract_id, payment_datetime, payment_number;

PRINT '06 register payments: _AccumRg3305 movements for reconstructed docs';
SELECT
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
 AND linked_sale._IDRRef = rg._Fld3308_RRRef
ORDER BY dr.contract_id, movement_datetime, recorder_number, record_kind;

PRINT '07 payment register by target client around target sale date (+/- 180 days)';
SELECT
    f.contract_id,
    f.client_id,
    f.client_fio,
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
FROM #facts AS f
JOIN dbo._AccumRg3305 AS rg
  ON rg._Fld3307_RTRef = 0x00000040
 AND rg._Fld3307_RRRef = f.client_ref
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
 AND linked_sale._IDRRef = rg._Fld3308_RRRef
ORDER BY f.contract_id, movement_datetime, recorder_number, record_kind;

PRINT '08 ready-made data history tables are empty';
SELECT
    table_name,
    rows_count
FROM (
    SELECT N'_DataHistoryVersions' AS table_name, COUNT_BIG(*) AS rows_count FROM dbo._DataHistoryVersions
    UNION ALL SELECT N'_DataHistoryLatestVersions', COUNT_BIG(*) FROM dbo._DataHistoryLatestVersions
    UNION ALL SELECT N'_DataHistoryMetadata', COUNT_BIG(*) FROM dbo._DataHistoryMetadata
    UNION ALL SELECT N'_DataHistoryAfterWriteQueue', COUNT_BIG(*) FROM dbo._DataHistoryAfterWriteQueue
) AS x
ORDER BY table_name;
