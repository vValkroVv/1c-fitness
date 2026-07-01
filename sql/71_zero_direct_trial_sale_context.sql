SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF OBJECT_ID('tempdb..#targets') IS NOT NULL
    DROP TABLE #targets;

CREATE TABLE #targets (
    contract_id nvarchar(20) NOT NULL PRIMARY KEY,
    manual_context nvarchar(200) NOT NULL
);

INSERT INTO #targets(contract_id, manual_context)
VALUES
    (N'00000070045', N'manual free week: НЕДЕЛЯ САЙТ'),
    (N'00000070915', N'НЕДЕЛЯ САЙТ direct 5999'),
    (N'00000071040', N'НЕДЕЛЯ САЙТ direct 5999'),
    (N'00000072190', N'НЕДЕЛЯ САЙТ direct 5999'),
    (N'00000115678', N'Неделя Фитнес direct 2000'),
    (N'00000117756', N'Неделя Фитнес direct 2000'),
    (N'00000132241', N'2 недели Фитнес direct 490 with refund');

IF OBJECT_ID('tempdb..#target_facts') IS NOT NULL
    DROP TABLE #target_facts;

SELECT
    t.manual_context,
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.product_class,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.status,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_operation,
    f.matched_payment_ref,
    f.matched_payment_match_source,
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin
INTO #target_facts
FROM #targets AS t
JOIN fitbase_part2.membership_import_facts AS f
  ON f.document_number COLLATE DATABASE_DEFAULT = t.contract_id COLLATE DATABASE_DEFAULT;

PRINT '01 target facts';

SELECT *
FROM #target_facts
ORDER BY subscription_name, document_number;

PRINT '02 target sale docs';

IF OBJECT_ID('tempdb..#sale_docs') IS NOT NULL
    DROP TABLE #sale_docs;

SELECT DISTINCT
    tf.document_number,
    tf.subscription_name,
    tf.client_id,
    tf.effective_client_fio,
    d154._Number AS sale_doc_number,
    d154._IDRRef AS sale_doc_ref_bin,
    CONVERT(varchar(32), d154._IDRRef, 2) AS sale_doc_ref,
    CASE WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time) ELSE d154._Date_Time END AS sale_doc_datetime,
    d154._Posted AS sale_posted,
    d154._Marked AS sale_marked,
    d154._Fld1135 AS sale_comment_1135,
    d154._Fld7834 AS sale_comment_7834
INTO #sale_docs
FROM #target_facts AS tf
JOIN dbo._Document154_VT1137 AS vt
  ON vt._Fld1148_RTRef = 0x000000A3
 AND vt._Fld1148_RRRef = tf.subscription_ref_bin
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt._Document154_IDRRef;

SELECT
    document_number,
    subscription_name,
    client_id,
    effective_client_fio,
    sale_doc_number,
    sale_doc_ref,
    sale_doc_datetime,
    sale_posted,
    sale_marked,
    sale_comment_1135,
    sale_comment_7834
FROM #sale_docs
ORDER BY document_number, sale_doc_datetime;

PRINT '03 all Document154 sale lines in target sale docs';

SELECT
    sd.document_number AS target_contract_id,
    sd.subscription_name AS target_subscription_name,
    sd.sale_doc_number,
    sd.sale_doc_datetime,
    vt._LineNo1138 AS line_no,
    CASE
        WHEN vt._Fld1148_RTRef = 0x000000A3
         AND vt._Fld1148_RRRef = tf.subscription_ref_bin
            THEN 1
        ELSE 0
    END AS is_target_membership_line,
    prod._Description AS line_product,
    linked_m._Number AS linked_membership_number,
    linked_prod._Description AS linked_membership_product,
    holder._Code AS linked_holder_id,
    holder._Description AS linked_holder_fio,
    vt._Fld10484 AS text_10484,
    vt._Fld10224 AS text_10224,
    vt._Fld10485 AS text_10485,
    vt._Fld9149 AS comment_9149,
    vt._Fld1140 AS amount_1140,
    vt._Fld1154 AS amount_1154,
    vt._Fld1160 AS amount_1160
FROM #sale_docs AS sd
JOIN #target_facts AS tf
  ON tf.document_number = sd.document_number
JOIN dbo._Document154_VT1137 AS vt
  ON vt._Document154_IDRRef = sd.sale_doc_ref_bin
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = vt._Fld1146RRef
LEFT JOIN dbo._Document163 AS linked_m
  ON vt._Fld1148_RTRef = 0x000000A3
 AND linked_m._IDRRef = vt._Fld1148_RRRef
LEFT JOIN dbo._Reference72 AS linked_prod
  ON linked_prod._IDRRef = linked_m._Fld1446RRef
LEFT JOIN dbo._Reference64 AS holder
  ON holder._IDRRef = linked_m._Fld9152RRef
ORDER BY sd.document_number, vt._LineNo1138;

PRINT '04 payments linked to target sale docs';

SELECT
    sd.document_number AS target_contract_id,
    sd.subscription_name AS target_subscription_name,
    sd.sale_doc_number,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    p._Posted AS payment_posted,
    p._Marked AS payment_marked,
    op._Description AS payment_operation,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_doc_amount,
    vt152._LineNo1084 AS payment_line_no,
    vt152._Fld1090 AS payment_line_amount,
    CONVERT(varchar(32), vt152._Fld1087_RRRef, 2) AS payment_line_sale_ref,
    ref1088._Description AS ref1088_name,
    ref1089._Description AS ref1089_name
FROM #sale_docs AS sd
JOIN dbo._Document152_VT1083 AS vt152
  ON vt152._Fld1087_RTRef = 0x0000009A
 AND vt152._Fld1087_RRRef = sd.sale_doc_ref_bin
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt152._Document152_IDRRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference72 AS ref1088
  ON ref1088._IDRRef = vt152._Fld1088RRef
LEFT JOIN dbo._Reference125 AS ref1089
  ON ref1089._IDRRef = vt152._Fld1089RRef
ORDER BY sd.document_number, payment_datetime, payment_number, payment_line_no;

PRINT '05 same-client memberships near target dates';

SELECT
    tf.document_number AS target_contract_id,
    f.document_number,
    f.effective_client_fio,
    f.subscription_name,
    f.product_class,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.status,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source
FROM #target_facts AS tf
JOIN fitbase_part2.membership_import_facts AS f
  ON f.client_id = tf.client_id
 AND f.sale_datetime BETWEEN DATEADD(day, -3, tf.sale_datetime) AND DATEADD(day, 3, tf.sale_datetime)
ORDER BY tf.document_number, f.sale_datetime, f.document_number;
