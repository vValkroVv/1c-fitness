SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @client_id nvarchar(20) = N'000003758';
DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

PRINT '01 Godareva memberships from membership_import_facts';

SELECT
    f.document_number,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.duration_days,
    f.status,
    f.is_active_on_cutoff,
    f.is_finished_before_cutoff,
    f.rg_price,
    f.rg_paid_candidate,
    f.rg_payment_count_candidate,
    f.matched_payment_ref,
    f.matched_payment_datetime,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    f.subscription_ref
FROM fitbase_part2.membership_import_facts AS f
WHERE f.client_id = @client_id
ORDER BY f.sale_datetime, f.document_number;

PRINT '02 sale docs and payment docs linked to Godareva memberships';

SELECT
    m._Number AS membership_number,
    prod._Description AS membership_name,
    CASE WHEN m._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, m._Date_Time) ELSE m._Date_Time END AS membership_datetime,
    d154._Number AS sale_number,
    CONVERT(varchar(32), d154._IDRRef, 2) AS sale_ref,
    CASE WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time) ELSE d154._Date_Time END AS sale_datetime,
    d154._Posted AS sale_posted,
    d154._Marked AS sale_marked,
    vt154._Fld1140 AS sale_line_sum_1140,
    vt154._Fld1154 AS sale_line_sum_1154,
    vt154._Fld1160 AS sale_line_sum_1160,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    op._Description AS payment_operation,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_amount,
    p._Posted AS payment_posted,
    p._Marked AS payment_marked
FROM dbo._Document163 AS m
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = m._Fld1446RRef
LEFT JOIN dbo._Document154_VT1137 AS vt154
  ON vt154._Fld1148_RTRef = 0x000000A3
 AND vt154._Fld1148_RRRef = m._IDRRef
LEFT JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt154._Document154_IDRRef
LEFT JOIN dbo._Document152_VT1083 AS vt152
  ON vt152._Fld1087_RTRef = 0x0000009A
 AND vt152._Fld1087_RRRef = d154._IDRRef
LEFT JOIN dbo._Document152 AS p
  ON p._IDRRef = vt152._Document152_IDRRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference64 AS payer
  ON m._Fld1447_RTRef = 0x00000040
 AND payer._IDRRef = m._Fld1447_RRRef
WHERE payer._Code = @client_id
ORDER BY membership_datetime, membership_number, payment_datetime, payment_number;

PRINT '03 visits by membership for Godareva';

SELECT
    m._Number AS membership_number,
    prod._Description AS membership_name,
    COUNT_BIG(v._IDRRef) AS visit_docs,
    MIN(CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END) AS first_visit,
    MAX(CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END) AS last_visit
FROM dbo._Document163 AS m
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = m._Fld1446RRef
LEFT JOIN dbo._Document150 AS v
  ON v._Fld991_RTRef = 0x000000A3
 AND v._Fld991_RRRef = m._IDRRef
 AND v._Posted = 0x01
 AND v._Marked = 0x00
 AND CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END <= @cutoff_at
LEFT JOIN dbo._Reference64 AS payer
  ON m._Fld1447_RTRef = 0x00000040
 AND payer._IDRRef = m._Fld1447_RRRef
WHERE payer._Code = @client_id
GROUP BY m._Number, prod._Description
ORDER BY MIN(CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END), m._Number;

PRINT '04 visit documents for 2019 duplicated memberships';

SELECT
    m._Number AS membership_number,
    prod._Description AS membership_name,
    v._Number AS visit_number,
    CONVERT(varchar(32), v._IDRRef, 2) AS visit_ref,
    CASE WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time) ELSE v._Date_Time END AS visit_datetime,
    v._Posted AS visit_posted,
    v._Marked AS visit_marked,
    c989._Code AS client_989_id,
    c989._Description AS client_989_fio,
    c990._Code AS client_990_id,
    c990._Description AS client_990_fio
FROM dbo._Document150 AS v
JOIN dbo._Document163 AS m
  ON v._Fld991_RTRef = 0x000000A3
 AND v._Fld991_RRRef = m._IDRRef
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = m._Fld1446RRef
LEFT JOIN dbo._Reference64 AS c989
  ON v._Fld989_RTRef = 0x00000040
 AND c989._IDRRef = v._Fld989_RRRef
LEFT JOIN dbo._Reference64 AS c990
  ON c990._IDRRef = v._Fld990RRef
WHERE m._Number IN (N'00000041901', N'00000041903')
  AND v._Posted = 0x01
  AND v._Marked = 0x00
ORDER BY membership_number, visit_datetime;

PRINT '05 direct keyword search in Godareva document/payment/sale text fields';

SELECT
    N'Document163' AS source_name,
    m._Number AS document_number,
    CASE WHEN m._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, m._Date_Time) ELSE m._Date_Time END AS document_datetime,
    prod._Description AS product_name,
    CONCAT_WS(N' | ', m._Fld1495, m._Fld5404, m._Fld7855, m._Fld7857) AS text_blob
FROM dbo._Document163 AS m
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = m._Fld1446RRef
LEFT JOIN dbo._Reference64 AS payer
  ON m._Fld1447_RTRef = 0x00000040
 AND payer._IDRRef = m._Fld1447_RRRef
WHERE payer._Code = @client_id
  AND (
      m._Fld1495 LIKE N'%возврат%' OR m._Fld1495 LIKE N'%блок%'
   OR m._Fld5404 LIKE N'%возврат%' OR m._Fld5404 LIKE N'%блок%'
   OR m._Fld7855 LIKE N'%возврат%' OR m._Fld7855 LIKE N'%блок%'
   OR m._Fld7857 LIKE N'%возврат%' OR m._Fld7857 LIKE N'%блок%'
  )
UNION ALL
SELECT
    N'Document152',
    p._Number,
    CASE WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END,
    pm._Description,
    CONCAT_WS(N' | ', p._Fld1082, p._Fld1073, p._Fld1075, p._Fld1076, p._Fld1077, p._Fld7822, p._Fld7826)
FROM dbo._Document152 AS p
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference64 AS c1057
  ON p._Fld1057_RTRef = 0x00000040
 AND c1057._IDRRef = p._Fld1057_RRRef
WHERE c1057._Code = @client_id
  AND (
      p._Fld1082 LIKE N'%возврат%' OR p._Fld1082 LIKE N'%блок%'
   OR p._Fld1073 LIKE N'%возврат%' OR p._Fld1073 LIKE N'%блок%'
   OR p._Fld1075 LIKE N'%возврат%' OR p._Fld1075 LIKE N'%блок%'
   OR p._Fld1076 LIKE N'%возврат%' OR p._Fld1076 LIKE N'%блок%'
   OR p._Fld1077 LIKE N'%возврат%' OR p._Fld1077 LIKE N'%блок%'
   OR p._Fld7822 LIKE N'%возврат%' OR p._Fld7822 LIKE N'%блок%'
   OR p._Fld7826 LIKE N'%возврат%' OR p._Fld7826 LIKE N'%блок%'
  )
ORDER BY document_datetime, source_name, document_number;
