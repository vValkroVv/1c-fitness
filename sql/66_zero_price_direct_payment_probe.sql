SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#targets') IS NOT NULL
    DROP TABLE #targets;

CREATE TABLE #targets (
    contract_id nvarchar(20) NOT NULL PRIMARY KEY,
    manual_note nvarchar(300) NOT NULL
);

INSERT INTO #targets(contract_id, manual_note)
VALUES
    (N'00000041901', N'manual: Проведен возврат. Блокировка абонемента.'),
    (N'00000070045', N'manual: Бесплатная неделя. Цена 0.');

IF OBJECT_ID('tempdb..#target_refs') IS NOT NULL
    DROP TABLE #target_refs;

SELECT
    t.contract_id,
    t.manual_note,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.product_class,
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.duration_days,
    f.status,
    f.booking_status_name,
    f.is_active_on_cutoff,
    f.is_finished_before_cutoff,
    f.days_to_end,
    f.days_since_end,
    f.rg_price,
    f.rg_paid_candidate,
    f.rg_payment_count_candidate,
    f.matched_payment_ref,
    CONVERT(binary(16), f.matched_payment_ref, 2) AS matched_payment_ref_bin,
    f.matched_payment_datetime,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_operation,
    f.matched_payment_match_source,
    f.normalized_club
INTO #target_refs
FROM #targets AS t
JOIN fitbase_part2.membership_import_facts AS f
  ON f.document_number COLLATE DATABASE_DEFAULT = t.contract_id COLLATE DATABASE_DEFAULT;

PRINT '01 target membership_import_facts';

SELECT *
FROM #target_refs
ORDER BY contract_id;

PRINT '02 all memberships for target clients, active/current focus';

SELECT
    tr.contract_id AS target_contract_id,
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.product_class,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.duration_days,
    f.status,
    f.booking_status_name,
    f.is_active_on_cutoff,
    f.is_finished_before_cutoff,
    f.days_to_end,
    f.rg_price,
    f.rg_paid_candidate,
    f.rg_payment_count_candidate,
    f.matched_payment_ref,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    f.subscription_ref
FROM #target_refs AS tr
JOIN fitbase_part2.membership_import_facts AS f
  ON f.client_id = tr.client_id
ORDER BY tr.contract_id, f.sale_datetime, f.document_number;

PRINT '03 final_funnel selected subscription for target clients';

SELECT
    tr.contract_id AS target_contract_id,
    fc.client_id,
    fc.client_fio,
    fc.funnel,
    fc.funnel_step,
    fc.selected_subscription_name,
    fc.selected_subscription_start_date,
    fc.selected_subscription_end_date,
    fc.selected_subscription_ref,
    fc.active_full_subscription_count,
    fc.validation_status,
    fc.selected_card_number
FROM #target_refs AS tr
LEFT JOIN fitbase_part2.final_funnel_clients AS fc
  ON fc.client_id = tr.client_id
ORDER BY tr.contract_id;

PRINT '04 raw Document163 target details';

SELECT
    tr.contract_id,
    tr.manual_note,
    d._Number AS document_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS document_ref,
    CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END AS document_datetime,
    d._Posted AS posted,
    d._Marked AS marked,
    prod._Code AS product_code,
    prod._Description AS product_name,
    holder._Code AS holder_9152_id,
    holder._Description AS holder_9152_fio,
    payer._Code AS payer_1447_id,
    payer._Description AS payer_1447_fio,
    org._Description AS organization_name,
    d._Fld1458,
    d._Fld1461,
    d._Fld1463,
    d._Fld1464,
    d._Fld1465,
    d._Fld1466,
    d._Fld1467,
    d._Fld1468,
    d._Fld1474,
    d._Fld1481 AS doc_duration_value,
    CASE WHEN d._Fld1482 > '3000-01-01' THEN DATEADD(year, -2000, d._Fld1482) ELSE d._Fld1482 END AS fld1482_datetime,
    d._Fld1485,
    d._Fld1486,
    d._Fld1493,
    d._Fld5925,
    d._Fld9153,
    d._Fld1495 AS comment_1495,
    d._Fld5404 AS comment_5404,
    d._Fld7855 AS text_7855,
    d._Fld7857 AS comment_7857
FROM #target_refs AS tr
JOIN dbo._Document163 AS d
  ON d._IDRRef = tr.subscription_ref_bin
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = d._Fld1446RRef
LEFT JOIN dbo._Reference64 AS holder
  ON holder._IDRRef = d._Fld9152RRef
LEFT JOIN dbo._Reference64 AS payer
  ON d._Fld1447_RTRef = 0x00000040
 AND payer._IDRRef = d._Fld1447_RRRef
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = d._Fld1443RRef
ORDER BY tr.contract_id;

PRINT '05 InfoRg3060 register rows';

SELECT
    tr.contract_id,
    r._Fld3062 AS register_datetime,
    CASE WHEN r._Fld3063 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3063)) ELSE CONVERT(date, r._Fld3063) END AS start_date,
    CASE WHEN r._Fld3064 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3064)) ELSE CONVERT(date, r._Fld3064) END AS end_date,
    r._Fld3065 AS duration_days,
    r._Fld3068 AS freeze_days,
    r._Fld3069 AS guests,
    r._Fld3070 AS price_candidate,
    r._Fld3072 AS paid_candidate,
    r._Fld5963 AS payment_count_candidate,
    r._Fld8007 AS visits_candidate_8007,
    r._Fld8008 AS visits_candidate_8008,
    r._Fld8009 AS visits_candidate_8009,
    st._Description AS status_name,
    book_st._Description AS booking_status_name
FROM #target_refs AS tr
JOIN dbo._InfoRg3060 AS r
  ON r._Fld3061RRef = tr.subscription_ref_bin
LEFT JOIN dbo._Reference5062 AS st
  ON st._IDRRef = r._Fld5960RRef
LEFT JOIN dbo._Reference5062 AS book_st
  ON book_st._IDRRef = r._Fld5960RRef
ORDER BY tr.contract_id, r._Fld3062;

PRINT '06 Document163 tabular sections';

SELECT
    tr.contract_id,
    N'_Document163_VT1497' AS table_name,
    vt._LineNo1498 AS line_no,
    vt._Fld1499_TYPE AS value_type,
    vt._Fld1499_RTRef AS value_rtref,
    CONVERT(varchar(32), vt._Fld1499_RRRef, 2) AS value_ref,
    vt._Fld1500 AS numeric_1500,
    vt._Fld1501 AS numeric_1501,
    ref1502._Description AS ref1502_name,
    CAST(NULL AS nvarchar(200)) AS extra_text
FROM #target_refs AS tr
JOIN dbo._Document163_VT1497 AS vt
  ON vt._Document163_IDRRef = tr.subscription_ref_bin
LEFT JOIN dbo._Reference72 AS ref1502
  ON ref1502._IDRRef = vt._Fld1502RRef
UNION ALL
SELECT
    tr.contract_id,
    N'_Document163_VT1503' AS table_name,
    vt._LineNo1504 AS line_no,
    NULL,
    NULL,
    CONVERT(varchar(32), vt._Fld1505RRef, 2),
    NULL,
    NULL,
    ref1505._Description,
    CONCAT(CONVERT(nvarchar(30), CASE WHEN vt._Fld1506 > '3000-01-01' THEN DATEADD(year, -2000, vt._Fld1506) ELSE vt._Fld1506 END, 120),
           N' - ',
           CONVERT(nvarchar(30), CASE WHEN vt._Fld1507 > '3000-01-01' THEN DATEADD(year, -2000, vt._Fld1507) ELSE vt._Fld1507 END, 120))
FROM #target_refs AS tr
JOIN dbo._Document163_VT1503 AS vt
  ON vt._Document163_IDRRef = tr.subscription_ref_bin
LEFT JOIN dbo._Reference95 AS ref1505
  ON ref1505._IDRRef = vt._Fld1505RRef
ORDER BY contract_id, table_name, line_no;

PRINT '07 Document154 sale lines directly linked to target memberships';

SELECT
    tr.contract_id,
    d154._Number AS sale_doc_number,
    CONVERT(varchar(32), d154._IDRRef, 2) AS sale_doc_ref,
    CASE WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time) ELSE d154._Date_Time END AS sale_doc_datetime,
    d154._Posted AS sale_posted,
    d154._Marked AS sale_marked,
    c._Code AS doc154_client_id,
    c._Description AS doc154_client_fio,
    prod._Description AS line_product,
    vt._LineNo1138 AS line_no,
    vt._Fld10484 AS text_10484,
    vt._Fld10224 AS text_10224,
    vt._Fld10485 AS text_10485,
    vt._Fld9149 AS comment_9149,
    vt._Fld1140,
    vt._Fld1144,
    vt._Fld1145,
    vt._Fld1150,
    vt._Fld1154,
    vt._Fld1155,
    vt._Fld1156,
    vt._Fld1157,
    vt._Fld1158,
    vt._Fld1160,
    d154._Fld1135 AS doc_comment_1135,
    d154._Fld7834 AS doc_comment_7834
FROM #target_refs AS tr
JOIN dbo._Document154_VT1137 AS vt
  ON vt._Fld1148_RTRef = 0x000000A3
 AND vt._Fld1148_RRRef = tr.subscription_ref_bin
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt._Document154_IDRRef
LEFT JOIN dbo._Reference64 AS c
  ON c._IDRRef = d154._Fld1119RRef
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = vt._Fld1146RRef
ORDER BY tr.contract_id, sale_doc_datetime, line_no;

PRINT '08 Document154 additional tabular sections for sale docs';

WITH sale_docs AS (
    SELECT DISTINCT tr.contract_id, d154._IDRRef AS sale_ref
    FROM #target_refs AS tr
    JOIN dbo._Document154_VT1137 AS vt
      ON vt._Fld1148_RTRef = 0x000000A3
     AND vt._Fld1148_RRRef = tr.subscription_ref_bin
    JOIN dbo._Document154 AS d154
      ON d154._IDRRef = vt._Document154_IDRRef
)
SELECT
    sd.contract_id,
    N'_Document154_VT1162' AS table_name,
    vt._LineNo1163 AS line_no,
    ref1168._Description AS ref_1168,
    ref1167._Description AS ref_1167,
    ref1166._Description AS ref_1166,
    vt._Fld1169 AS amount,
    CAST(NULL AS nvarchar(200)) AS text_value
FROM sale_docs AS sd
JOIN dbo._Document154_VT1162 AS vt
  ON vt._Document154_IDRRef = sd.sale_ref
LEFT JOIN dbo._Reference64 AS ref1168
  ON ref1168._IDRRef = vt._Fld1168RRef
LEFT JOIN dbo._Reference72 AS ref1167
  ON ref1167._IDRRef = vt._Fld1167RRef
LEFT JOIN dbo._Reference125 AS ref1166
  ON ref1166._IDRRef = vt._Fld1166RRef
UNION ALL
SELECT
    sd.contract_id,
    N'_Document154_VT1181' AS table_name,
    vt._LineNo1182 AS line_no,
    ref1184._Description,
    ref1187._Description,
    ref1185._Description,
    vt._Fld1189,
    vt._Fld7836
FROM sale_docs AS sd
JOIN dbo._Document154_VT1181 AS vt
  ON vt._Document154_IDRRef = sd.sale_ref
LEFT JOIN dbo._Reference72 AS ref1184
  ON ref1184._IDRRef = vt._Fld1184RRef
LEFT JOIN dbo._Reference125 AS ref1187
  ON ref1187._IDRRef = vt._Fld1187RRef
LEFT JOIN dbo._Reference64 AS ref1185
  ON ref1185._IDRRef = vt._Fld1185RRef
ORDER BY contract_id, table_name, line_no;

PRINT '09 Document152 payments linked through sale docs';

SELECT
    tr.contract_id,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    p._Posted AS payment_posted,
    p._Marked AS payment_marked,
    op._Description AS operation_name,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_amount,
    p._Fld1079 AS fld1079,
    c1057._Code AS client_1057_id,
    c1057._Description AS client_1057_fio,
    org._Description AS organization_name,
    p._Fld1082 AS comment_1082,
    p._Fld1073 AS text_1073,
    p._Fld1075 AS text_1075,
    p._Fld1076 AS text_1076,
    p._Fld1077 AS text_1077,
    p._Fld7822 AS text_7822,
    p._Fld7826 AS comment_7826,
    vt._LineNo1084 AS line_no,
    vt._Fld1090 AS line_amount,
    CONVERT(varchar(32), vt._Fld1087_RRRef, 2) AS linked_sale_ref,
    vt._Fld1087_RTRef AS linked_sale_rtref,
    ref1088._Description AS ref1088_name,
    ref1089._Description AS ref1089_name,
    CONVERT(varchar(32), vt._Fld8771_RRRef, 2) AS linked_extra_ref,
    vt._Fld8771_RTRef AS linked_extra_rtref
FROM #target_refs AS tr
JOIN dbo._Document154_VT1137 AS vt154
  ON vt154._Fld1148_RTRef = 0x000000A3
 AND vt154._Fld1148_RRRef = tr.subscription_ref_bin
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt154._Document154_IDRRef
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = 0x0000009A
 AND vt._Fld1087_RRRef = d154._IDRRef
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference64 AS c1057
  ON p._Fld1057_RTRef = 0x00000040
 AND c1057._IDRRef = p._Fld1057_RRRef
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = p._Fld1051RRef
LEFT JOIN dbo._Reference72 AS ref1088
  ON ref1088._IDRRef = vt._Fld1088RRef
LEFT JOIN dbo._Reference125 AS ref1089
  ON ref1089._IDRRef = vt._Fld1089RRef
ORDER BY tr.contract_id, payment_datetime, payment_number, line_no;

PRINT '10 all Document152 payments for target clients around target sale/payment dates';

SELECT
    tr.contract_id AS target_contract_id,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    p._Posted AS payment_posted,
    p._Marked AS payment_marked,
    op._Description AS operation_name,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_amount,
    c1057._Code AS client_1057_id,
    c1057._Description AS client_1057_fio,
    org._Description AS organization_name,
    p._Fld1082 AS comment_1082,
    p._Fld1075 AS text_1075,
    p._Fld7826 AS comment_7826
FROM #target_refs AS tr
JOIN dbo._Document152 AS p
  ON CASE WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END
     BETWEEN DATEADD(day, -30, tr.sale_datetime) AND DATEADD(day, 30, tr.sale_datetime)
LEFT JOIN dbo._Reference64 AS c1057
  ON p._Fld1057_RTRef = 0x00000040
 AND c1057._IDRRef = p._Fld1057_RRRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = p._Fld1051RRef
WHERE c1057._Code = tr.client_id
ORDER BY tr.contract_id, payment_datetime, payment_number;

PRINT '11 visits by target membership';

SELECT
    tr.contract_id,
    COUNT_BIG(v._IDRRef) AS visit_docs,
    MIN(CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END) AS first_visit,
    MAX(CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END) AS last_visit
FROM #target_refs AS tr
LEFT JOIN dbo._Document150 AS v
  ON v._Fld991_TYPE = 0x08
 AND v._Fld991_RTRef = 0x000000A3
 AND v._Fld991_RRRef = tr.subscription_ref_bin
 AND v._Posted = 0x01
 AND v._Marked = 0x00
 AND CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END <= @cutoff_at
GROUP BY tr.contract_id
ORDER BY tr.contract_id;

PRINT '12 targeted document/register references to target membership refs';

SELECT N'_InfoRg3060._Fld3061RRef' AS source_name, tr.contract_id, COUNT_BIG(*) AS rows_count
FROM #target_refs AS tr
JOIN dbo._InfoRg3060 AS r
  ON r._Fld3061RRef = tr.subscription_ref_bin
GROUP BY tr.contract_id
UNION ALL
SELECT N'_Document154_VT1137._Fld1148_RRRef', tr.contract_id, COUNT_BIG(*)
FROM #target_refs AS tr
JOIN dbo._Document154_VT1137 AS vt
  ON vt._Fld1148_RTRef = 0x000000A3
 AND vt._Fld1148_RRRef = tr.subscription_ref_bin
GROUP BY tr.contract_id
UNION ALL
SELECT N'_Document150._Fld991_RRRef', tr.contract_id, COUNT_BIG(*)
FROM #target_refs AS tr
JOIN dbo._Document150 AS v
  ON v._Fld991_RTRef = 0x000000A3
 AND v._Fld991_RRRef = tr.subscription_ref_bin
GROUP BY tr.contract_id
UNION ALL
SELECT N'_Document138._Fld763RRef', tr.contract_id, COUNT_BIG(*)
FROM #target_refs AS tr
JOIN dbo._Document138 AS d
  ON d._Fld763RRef = tr.subscription_ref_bin
GROUP BY tr.contract_id
UNION ALL
SELECT N'_Document163_VT1497._Document163_IDRRef', tr.contract_id, COUNT_BIG(*)
FROM #target_refs AS tr
JOIN dbo._Document163_VT1497 AS vt
  ON vt._Document163_IDRRef = tr.subscription_ref_bin
GROUP BY tr.contract_id
UNION ALL
SELECT N'_Document163_VT1503._Document163_IDRRef', tr.contract_id, COUNT_BIG(*)
FROM #target_refs AS tr
JOIN dbo._Document163_VT1503 AS vt
  ON vt._Document163_IDRRef = tr.subscription_ref_bin
GROUP BY tr.contract_id
ORDER BY source_name, contract_id;

PRINT '13 decode unknown references from target tabular sections';

IF OBJECT_ID('tempdb..#interesting_refs') IS NOT NULL
    DROP TABLE #interesting_refs;

CREATE TABLE #interesting_refs (
    contract_id nvarchar(20) NOT NULL,
    context_name nvarchar(200) NOT NULL,
    ref_hex varchar(32) NOT NULL,
    ref_bin binary(16) NOT NULL
);

INSERT INTO #interesting_refs(contract_id, context_name, ref_hex, ref_bin)
SELECT
    tr.contract_id,
    N'_Document163_VT1497._Fld1499_RRRef',
    CONVERT(varchar(32), vt._Fld1499_RRRef, 2),
    vt._Fld1499_RRRef
FROM #target_refs AS tr
JOIN dbo._Document163_VT1497 AS vt
  ON vt._Document163_IDRRef = tr.subscription_ref_bin
WHERE vt._Fld1499_RRRef <> 0x00000000000000000000000000000000
UNION ALL
SELECT
    tr.contract_id,
    N'_Document163_VT1503._Fld1505RRef',
    CONVERT(varchar(32), vt._Fld1505RRef, 2),
    vt._Fld1505RRef
FROM #target_refs AS tr
JOIN dbo._Document163_VT1503 AS vt
  ON vt._Document163_IDRRef = tr.subscription_ref_bin
WHERE vt._Fld1505RRef <> 0x00000000000000000000000000000000;

IF OBJECT_ID('tempdb..#decoded_refs') IS NOT NULL
    DROP TABLE #decoded_refs;

CREATE TABLE #decoded_refs (
    table_name sysname NOT NULL,
    contract_id nvarchar(20) NOT NULL,
    context_name nvarchar(200) NOT NULL,
    ref_hex varchar(32) NOT NULL,
    ref_description nvarchar(4000) NULL
);

DECLARE @sql_decode_refs nvarchar(max) = N'';

SELECT @sql_decode_refs = @sql_decode_refs + N'
INSERT INTO #decoded_refs(table_name, contract_id, context_name, ref_hex, ref_description)
SELECT
    N''' + REPLACE(t.name, '''', '''''') + N''',
    ir.contract_id,
    ir.context_name,
    ir.ref_hex,
    CAST(x._Description AS nvarchar(4000))
FROM dbo.' + QUOTENAME(t.name) + N' AS x
JOIN #interesting_refs AS ir
  ON x._IDRRef = ir.ref_bin;
'
FROM sys.tables AS t
WHERE t.name LIKE N'[_]Reference%'
  AND EXISTS (
      SELECT 1
      FROM sys.columns AS c
      WHERE c.object_id = t.object_id
        AND c.name = N'_IDRRef'
  )
  AND EXISTS (
      SELECT 1
      FROM sys.columns AS c
      WHERE c.object_id = t.object_id
        AND c.name = N'_Description'
  );

EXEC sp_executesql @sql_decode_refs;

SELECT *
FROM #decoded_refs
ORDER BY contract_id, context_name, table_name, ref_description;

PRINT '14 reference descriptions containing refund/block keywords';

IF OBJECT_ID('tempdb..#keyword_refs') IS NOT NULL
    DROP TABLE #keyword_refs;

CREATE TABLE #keyword_refs (
    table_name sysname NOT NULL,
    ref_description nvarchar(4000) NULL
);

DECLARE @sql_refs nvarchar(max) = N'';

SELECT @sql_refs = @sql_refs + N'
INSERT INTO #keyword_refs(table_name, ref_description)
SELECT TOP (200)
    N''' + REPLACE(t.name, '''', '''''') + N''',
    CAST(x._Description AS nvarchar(4000))
FROM dbo.' + QUOTENAME(t.name) + N' AS x
WHERE x._Description LIKE N''%возврат%''
   OR x._Description LIKE N''%Возврат%''
   OR x._Description LIKE N''%блок%''
   OR x._Description LIKE N''%Блок%''
   OR x._Description LIKE N''%замороз%''
   OR x._Description LIKE N''%Замороз%'';
'
FROM sys.tables AS t
WHERE t.name LIKE N'[_]Reference%'
  AND EXISTS (
      SELECT 1
      FROM sys.columns AS c
      WHERE c.object_id = t.object_id
        AND c.name = N'_Description'
  );

EXEC sp_executesql @sql_refs;

SELECT *
FROM #keyword_refs
ORDER BY table_name, ref_description;
