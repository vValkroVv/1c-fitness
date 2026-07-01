SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#manual_targets') IS NOT NULL
    DROP TABLE #manual_targets;

CREATE TABLE #manual_targets (
    contract_id nvarchar(20) NOT NULL PRIMARY KEY,
    manual_note nvarchar(300) NOT NULL
);

INSERT INTO #manual_targets(contract_id, manual_note)
VALUES
    (N'00000041901', N'manual: Проведен возврат. Блокировка абонемента.'),
    (N'00000070045', N'manual: Бесплатная неделя. Цена 0.');

IF OBJECT_ID('tempdb..#target_refs') IS NOT NULL
    DROP TABLE #target_refs;

CREATE TABLE #target_refs (
    ref_kind nvarchar(40) NOT NULL,
    ref_label nvarchar(100) NOT NULL,
    contract_id nvarchar(20) NULL,
    ref_bin binary(16) NOT NULL
);

INSERT INTO #target_refs(ref_kind, ref_label, contract_id, ref_bin)
SELECT
    N'membership_ref',
    CONCAT(N'membership_', f.document_number),
    f.document_number,
    CONVERT(binary(16), f.subscription_ref, 2)
FROM fitbase_part2.membership_import_facts AS f
JOIN #manual_targets AS t
  ON t.contract_id COLLATE DATABASE_DEFAULT = f.document_number COLLATE DATABASE_DEFAULT;

INSERT INTO #target_refs(ref_kind, ref_label, contract_id, ref_bin)
SELECT DISTINCT
    N'client_ref',
    CONCAT(N'client_', f.client_id),
    f.document_number,
    c._IDRRef
FROM fitbase_part2.membership_import_facts AS f
JOIN #manual_targets AS t
  ON t.contract_id COLLATE DATABASE_DEFAULT = f.document_number COLLATE DATABASE_DEFAULT
JOIN dbo._Reference64 AS c
  ON c._Code COLLATE DATABASE_DEFAULT = f.client_id COLLATE DATABASE_DEFAULT;

INSERT INTO #target_refs(ref_kind, ref_label, contract_id, ref_bin)
SELECT DISTINCT
    N'sale_doc_ref',
    CONCAT(N'sale_for_', tr.contract_id),
    tr.contract_id,
    d154._IDRRef
FROM #target_refs AS tr
JOIN dbo._Document154_VT1137 AS vt154
  ON tr.ref_kind = N'membership_ref'
 AND vt154._Fld1148_RTRef = 0x000000A3
 AND vt154._Fld1148_RRRef = tr.ref_bin
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt154._Document154_IDRRef;

INSERT INTO #target_refs(ref_kind, ref_label, contract_id, ref_bin)
SELECT DISTINCT
    N'payment_doc_ref',
    CONCAT(N'payment_for_', tr.contract_id),
    tr.contract_id,
    p._IDRRef
FROM #target_refs AS tr
JOIN dbo._Document154_VT1137 AS vt154
  ON tr.ref_kind = N'membership_ref'
 AND vt154._Fld1148_RTRef = 0x000000A3
 AND vt154._Fld1148_RRRef = tr.ref_bin
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt154._Document154_IDRRef
JOIN dbo._Document152_VT1083 AS vt152
  ON vt152._Fld1087_RTRef = 0x0000009A
 AND vt152._Fld1087_RRRef = d154._IDRRef
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt152._Document152_IDRRef;

PRINT '01 target refs used for wide search';

SELECT
    ref_kind,
    ref_label,
    contract_id,
    CONVERT(varchar(32), ref_bin, 2) AS ref_hex
FROM #target_refs
ORDER BY ref_kind, contract_id, ref_label;

PRINT '02 Reference52 metadata for refund/block/freeze objects';

SELECT
    _Description,
    _Fld3713 AS object_kind_code,
    _Fld3714 AS internal_name,
    _Fld3716 AS full_name,
    _Fld3719_TYPE AS ref_type,
    _Fld3719_RTRef AS rtref,
    CONVERT(int, _Fld3719_RTRef) AS rtref_decimal,
    CASE
        WHEN _Fld3719_TYPE = 0x08 AND CONVERT(int, _Fld3719_RTRef) > 0
            THEN CONCAT(N'_Document', CONVERT(varchar(20), CONVERT(int, _Fld3719_RTRef)))
        ELSE NULL
    END AS expected_table
FROM dbo._Reference52
WHERE _Fld3714 IN (
        N'ВозвратОтПокупателя',
        N'МассоваяЗаморозка',
        N'Заморозки',
        N'БлокировкаОбезличенныхКлиентов',
        N'БлокировкаОнлайнЗаписи',
        N'ЗаблокированныеНомераТелефонов'
    )
   OR _Description LIKE N'%Возврат оплаты%'
   OR _Description LIKE N'%Блокировка%'
ORDER BY _Fld3713, _Fld3714;

PRINT '03 known refund/freeze physical table row counts';

SELECT
    t.name AS table_name,
    SUM(p.rows) AS rows_count
FROM sys.tables AS t
JOIN sys.partitions AS p
  ON p.object_id = t.object_id
 AND p.index_id IN (0, 1)
WHERE t.name IN (N'_Document131', N'_Document6137')
GROUP BY t.name
ORDER BY t.name;

PRINT '04 Document131 refund docs directly referencing target membership/sale/payment refs';

SELECT
    tr.ref_kind,
    tr.ref_label,
    tr.contract_id AS target_contract_id,
    d._Number AS refund_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS refund_ref,
    CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END AS refund_datetime,
    d._Posted,
    d._Marked,
    CASE
        WHEN d._IDRRef = tr.ref_bin THEN N'_IDRRef'
        WHEN d._Fld550RRef = tr.ref_bin THEN N'_Fld550RRef'
        WHEN d._Fld545_RRRef = tr.ref_bin THEN N'_Fld545_RRRef'
        WHEN d._Fld7766RRef = tr.ref_bin THEN N'_Fld7766RRef'
        WHEN d._Fld543RRef = tr.ref_bin THEN N'_Fld543RRef'
        WHEN d._Fld4935RRef = tr.ref_bin THEN N'_Fld4935RRef'
        WHEN d._Fld546RRef = tr.ref_bin THEN N'_Fld546RRef'
        WHEN d._Fld547_RRRef = tr.ref_bin THEN N'_Fld547_RRRef'
        WHEN d._Fld542RRef = tr.ref_bin THEN N'_Fld542RRef'
        WHEN d._Fld8918RRef = tr.ref_bin THEN N'_Fld8918RRef'
        ELSE N'unknown'
    END AS matched_column,
    d._Fld548 AS amount_548,
    d._Fld549 AS amount_549,
    d._Fld551 AS comment_551,
    d._Fld5909 AS text_5909,
    d._Fld7770 AS text_7770
FROM dbo._Document131 AS d
JOIN #target_refs AS tr
  ON tr.ref_kind <> N'client_ref'
 AND (
        d._IDRRef = tr.ref_bin
     OR d._Fld550RRef = tr.ref_bin
     OR d._Fld545_RRRef = tr.ref_bin
     OR d._Fld7766RRef = tr.ref_bin
     OR d._Fld543RRef = tr.ref_bin
     OR d._Fld4935RRef = tr.ref_bin
     OR d._Fld546RRef = tr.ref_bin
     OR d._Fld547_RRRef = tr.ref_bin
     OR d._Fld542RRef = tr.ref_bin
     OR d._Fld8918RRef = tr.ref_bin
 )
ORDER BY target_contract_id, ref_kind, refund_datetime, refund_number;

PRINT '05 Document131 refund docs for target clients by any direct client ref column';

WITH target_clients AS (
    SELECT DISTINCT contract_id, ref_bin
    FROM #target_refs
    WHERE ref_kind = N'client_ref'
)
SELECT
    tc.contract_id AS target_contract_id,
    d._Number AS refund_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS refund_ref,
    CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END AS refund_datetime,
    d._Posted,
    d._Marked,
    d._Fld545_RTRef,
    c545._Code AS client_545_code,
    c545._Description AS client_545_fio,
    c550._Code AS ref550_code,
    c550._Description AS ref550_desc,
    c543._Code AS ref543_code,
    c543._Description AS ref543_desc,
    c546._Code AS ref546_code,
    c546._Description AS ref546_desc,
    d._Fld548 AS amount_548,
    d._Fld549 AS amount_549,
    d._Fld551 AS comment_551,
    d._Fld5909 AS text_5909,
    d._Fld7770 AS text_7770
FROM dbo._Document131 AS d
JOIN target_clients AS tc
  ON d._Fld545_RRRef = tc.ref_bin
  OR d._Fld550RRef = tc.ref_bin
  OR d._Fld543RRef = tc.ref_bin
  OR d._Fld546RRef = tc.ref_bin
  OR d._Fld547_RRRef = tc.ref_bin
  OR d._Fld542RRef = tc.ref_bin
LEFT JOIN dbo._Reference64 AS c545
  ON d._Fld545_RTRef = 0x00000040
 AND c545._IDRRef = d._Fld545_RRRef
LEFT JOIN dbo._Reference64 AS c550
  ON c550._IDRRef = d._Fld550RRef
LEFT JOIN dbo._Reference64 AS c543
  ON c543._IDRRef = d._Fld543RRef
LEFT JOIN dbo._Reference64 AS c546
  ON c546._IDRRef = d._Fld546RRef
ORDER BY target_contract_id, refund_datetime, refund_number;

PRINT '06 zero-direct 207 payment operation names';

WITH zero_direct AS (
    SELECT *
    FROM fitbase_part2.membership_import_facts
    WHERE rg_price = 0
      AND matched_payment_ref IS NOT NULL
      AND matched_payment_match_source LIKE N'direct%'
      AND matched_payment_method IS NOT NULL
      AND LTRIM(RTRIM(matched_payment_method)) <> N''
)
SELECT
    COALESCE(NULLIF(matched_payment_operation, N''), N'blank') AS matched_payment_operation,
    COUNT(*) AS rows_count,
    SUM(CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_rows
FROM zero_direct
GROUP BY COALESCE(NULLIF(matched_payment_operation, N''), N'blank')
ORDER BY rows_count DESC, matched_payment_operation;

PRINT '07 zero-direct 207 service-date and active split';

WITH zero_direct AS (
    SELECT *
    FROM fitbase_part2.membership_import_facts
    WHERE rg_price = 0
      AND matched_payment_ref IS NOT NULL
      AND matched_payment_match_source LIKE N'direct%'
      AND matched_payment_method IS NOT NULL
      AND LTRIM(RTRIM(matched_payment_method)) <> N''
)
SELECT
    product_class,
    CASE WHEN start_date = '2001-01-01' AND end_date = '2001-01-01' THEN 1 ELSE 0 END AS service_dates_2001,
    is_active_on_cutoff,
    COUNT(*) AS rows_count,
    SUM(CASE WHEN matched_payment_operation LIKE N'%Возврат%' THEN 1 ELSE 0 END) AS payment_operation_refund_rows
FROM zero_direct
GROUP BY
    product_class,
    CASE WHEN start_date = '2001-01-01' AND end_date = '2001-01-01' THEN 1 ELSE 0 END,
    is_active_on_cutoff
ORDER BY product_class, service_dates_2001, is_active_on_cutoff;

PRINT '08 zero-direct rows with Document131 refund linked to sale doc';

WITH zero_direct AS (
    SELECT *
    FROM fitbase_part2.membership_import_facts
    WHERE rg_price = 0
      AND matched_payment_ref IS NOT NULL
      AND matched_payment_match_source LIKE N'direct%'
      AND matched_payment_method IS NOT NULL
      AND LTRIM(RTRIM(matched_payment_method)) <> N''
),
sale_docs AS (
    SELECT
        z.document_number,
        z.client_id,
        z.effective_client_fio,
        z.subscription_name,
        z.product_class,
        z.sale_datetime,
        z.start_date,
        z.end_date,
        z.is_active_on_cutoff,
        z.matched_payment_amount,
        z.matched_payment_method,
        z.matched_payment_operation,
        d154._Number AS sale_doc_number,
        d154._IDRRef AS sale_doc_ref
    FROM zero_direct AS z
    JOIN dbo._Document154_VT1137 AS vt154
      ON vt154._Fld1148_RTRef = 0x000000A3
     AND vt154._Fld1148_RRRef = CONVERT(binary(16), z.subscription_ref, 2)
    JOIN dbo._Document154 AS d154
      ON d154._IDRRef = vt154._Document154_IDRRef
)
SELECT
    sd.document_number,
    sd.client_id,
    sd.effective_client_fio,
    sd.subscription_name,
    sd.product_class,
    sd.sale_datetime,
    sd.start_date,
    sd.end_date,
    sd.is_active_on_cutoff,
    sd.matched_payment_amount,
    sd.matched_payment_method,
    sd.matched_payment_operation,
    sd.sale_doc_number,
    CONVERT(varchar(32), sd.sale_doc_ref, 2) AS sale_doc_ref,
    d131._Number AS refund_number,
    CONVERT(varchar(32), d131._IDRRef, 2) AS refund_ref,
    CASE WHEN d131._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d131._Date_Time) ELSE d131._Date_Time END AS refund_datetime,
    d131._Posted AS refund_posted,
    d131._Marked AS refund_marked,
    CASE
        WHEN d131._Fld545_RRRef = sd.sale_doc_ref THEN N'_Fld545_RRRef'
        WHEN d131._Fld547_RRRef = sd.sale_doc_ref THEN N'_Fld547_RRRef'
        ELSE N'other'
    END AS refund_sale_match_column,
    d131._Fld548 AS refund_amount_548,
    d131._Fld549 AS refund_amount_549,
    d131._Fld551 AS refund_comment_551,
    d131._Fld5909 AS refund_text_5909,
    d131._Fld7770 AS refund_text_7770
FROM sale_docs AS sd
JOIN dbo._Document131 AS d131
  ON d131._Fld545_RRRef = sd.sale_doc_ref
  OR d131._Fld547_RRRef = sd.sale_doc_ref
ORDER BY sd.document_number, refund_datetime, refund_number;
