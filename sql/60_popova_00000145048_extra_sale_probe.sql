SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @target_contract nvarchar(20) = N'00000145048';
DECLARE @target_client_id nvarchar(20) = N'000014308';
DECLARE @target_fio nvarchar(200) = N'Попова Ирина Борисовна';
DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

PRINT '01 current import facts for target contract';

SELECT
    f.document_number,
    f.client_id,
    f.original_client_id,
    f.original_client_fio,
    f.effective_client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.duration_days,
    f.status,
    f.booking_status_name,
    f.doc_posted,
    f.doc_marked,
    f.is_active_on_cutoff,
    f.days_to_end,
    f.rg_price,
    f.rg_paid_candidate,
    f.rg_payment_count_candidate,
    f.matched_payment_ref,
    f.matched_payment_datetime,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_operation,
    f.matched_payment_match_source,
    f.client_role_source,
    f.raw_source,
    f.subscription_ref
FROM fitbase_part2.membership_import_facts AS f
WHERE f.document_number = @target_contract;

PRINT '02 all current import facts for Popova ordered by date';

SELECT
    f.document_number,
    f.client_id,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.status,
    f.is_active_on_cutoff,
    f.days_to_end,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    f.subscription_ref
FROM fitbase_part2.membership_import_facts AS f
WHERE f.client_id = @target_client_id
   OR f.effective_client_fio = @target_fio
   OR f.original_client_fio = @target_fio
ORDER BY f.sale_datetime, f.document_number;

PRINT '03 raw Document163 for all Popova memberships';

SELECT
    d._Number AS document_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS document_ref,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS document_datetime,
    d._Posted AS posted,
    d._Marked AS marked,
    prod._Code AS product_code,
    prod._Description AS product_name,
    holder._Code AS holder_9152_id,
    holder._Description AS holder_9152_fio,
    payer._Code AS payer_1447_id,
    payer._Description AS payer_1447_fio,
    org._Description AS organization_name,
    d._Fld1481 AS doc_duration_value,
    d._Fld1485,
    d._Fld1486,
    d._Fld1493,
    d._Fld5925,
    d._Fld9153
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = d._Fld1446RRef
LEFT JOIN dbo._Reference64 AS holder
  ON holder._IDRRef = d._Fld9152RRef
LEFT JOIN dbo._Reference64 AS payer
  ON d._Fld1447_RTRef = 0x00000040
 AND payer._IDRRef = d._Fld1447_RRRef
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = d._Fld1443RRef
WHERE holder._Code = @target_client_id
   OR payer._Code = @target_client_id
ORDER BY document_datetime, d._Number;

PRINT '04 InfoRg3060 subscription register rows for target and overlapping active membership';

SELECT
    d._Number AS document_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS document_ref,
    r._Fld3062 AS register_datetime,
    CASE
        WHEN r._Fld3063 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3063))
        ELSE CONVERT(date, r._Fld3063)
    END AS start_date,
    CASE
        WHEN r._Fld3064 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3064))
        ELSE CONVERT(date, r._Fld3064)
    END AS end_date,
    r._Fld3065 AS duration_days,
    r._Fld3068 AS freeze_days,
    r._Fld3069 AS guests,
    r._Fld3070 AS price_candidate,
    r._Fld3072 AS paid_candidate,
    r._Fld5963 AS payment_count_candidate,
    st._Description AS status_name,
    book_st._Description AS booking_status_name
FROM dbo._InfoRg3060 AS r
JOIN dbo._Document163 AS d
  ON d._IDRRef = r._Fld3061RRef
LEFT JOIN dbo._Reference5062 AS st
  ON st._IDRRef = r._Fld5960RRef
LEFT JOIN dbo._Reference5062 AS book_st
  ON book_st._IDRRef = r._Fld5960RRef
WHERE d._Number IN (@target_contract, N'00000139985')
ORDER BY d._Number, r._Fld3062;

PRINT '05 Document154 sale lines directly linked to target and overlapping active membership';

SELECT
    m._Number AS membership_number,
    d154._Number AS sale_doc_number,
    CONVERT(varchar(32), d154._IDRRef, 2) AS sale_doc_ref,
    CASE
        WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time)
        ELSE d154._Date_Time
    END AS sale_doc_datetime,
    d154._Posted AS sale_posted,
    d154._Marked AS sale_marked,
    c._Code AS doc154_client_id,
    c._Description AS doc154_client_fio,
    prod._Description AS line_product,
    vt._LineNo1138,
    CONVERT(varchar(32), vt._Fld1148_RRRef, 2) AS linked_membership_ref,
    vt._Fld1140,
    vt._Fld1144,
    vt._Fld1145,
    vt._Fld1150,
    vt._Fld1154,
    vt._Fld1155,
    vt._Fld1156,
    vt._Fld1157,
    vt._Fld1158,
    vt._Fld1160
FROM dbo._Document163 AS m
JOIN dbo._Document154_VT1137 AS vt
  ON vt._Fld1148_RTRef = 0x000000A3
 AND vt._Fld1148_RRRef = m._IDRRef
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt._Document154_IDRRef
LEFT JOIN dbo._Reference64 AS c
  ON c._IDRRef = d154._Fld1119RRef
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = vt._Fld1146RRef
WHERE m._Number IN (@target_contract, N'00000139985')
ORDER BY membership_number, sale_doc_datetime, vt._LineNo1138;

PRINT '06 Payment Document152 rows linked through sale docs for target and overlapping membership';

SELECT
    m._Number AS membership_number,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    p._Posted AS payment_posted,
    p._Marked AS payment_marked,
    cp1._Code AS client_1057_id,
    cp1._Description AS client_1057_fio,
    cp2._Code AS client_1058_id,
    cp2._Description AS client_1058_fio,
    op._Description AS operation_name,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_total,
    vt152._Fld1090 AS payment_line_amount,
    d154._Number AS linked_sale_doc_number,
    CONVERT(varchar(32), d154._IDRRef, 2) AS linked_sale_doc_ref
FROM dbo._Document163 AS m
JOIN dbo._Document154_VT1137 AS vt154
  ON vt154._Fld1148_RTRef = 0x000000A3
 AND vt154._Fld1148_RRRef = m._IDRRef
JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt154._Document154_IDRRef
JOIN dbo._Document152_VT1083 AS vt152
  ON vt152._Fld1087_RTRef = 0x0000009A
 AND vt152._Fld1087_RRRef = d154._IDRRef
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt152._Document152_IDRRef
LEFT JOIN dbo._Reference64 AS cp1
  ON p._Fld1057_RTRef = 0x00000040
 AND cp1._IDRRef = p._Fld1057_RRRef
LEFT JOIN dbo._Reference64 AS cp2
  ON cp2._IDRRef = p._Fld1058RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE m._Number IN (@target_contract, N'00000139985')
ORDER BY membership_number, payment_datetime;

PRINT '07 all posted payment docs for Popova around suspicious sale date';

SELECT
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    p._Posted AS payment_posted,
    p._Marked AS payment_marked,
    cp1._Code AS client_1057_id,
    cp1._Description AS client_1057_fio,
    cp2._Code AS client_1058_id,
    cp2._Description AS client_1058_fio,
    op._Description AS operation_name,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_total
FROM dbo._Reference64 AS c
JOIN dbo._Document152 AS p
  ON (
      p._Fld1057_RTRef = 0x00000040
      AND p._Fld1057_RRRef = c._IDRRef
  )
  OR p._Fld1058RRef = c._IDRRef
LEFT JOIN dbo._Reference64 AS cp1
  ON p._Fld1057_RTRef = 0x00000040
 AND cp1._IDRRef = p._Fld1057_RRRef
LEFT JOIN dbo._Reference64 AS cp2
  ON cp2._IDRRef = p._Fld1058RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE c._Code = @target_client_id
  AND p._Posted = 0x01
  AND p._Marked = 0x00
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END >= '2025-08-01'
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END < '2026-03-01'
ORDER BY payment_datetime, p._Number;

PRINT '08 all Document138 changes for target and overlapping membership';

SELECT
    m._Number AS membership_number,
    d._Number AS doc138_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS doc138_ref,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS doc138_datetime,
    d._Posted AS posted,
    d._Marked AS marked,
    oldc._Code AS old_client_id,
    oldc._Description AS old_client_fio,
    newc._Code AS new_client_id,
    newc._Description AS new_client_fio,
    mod._Description AS modifier_name,
    op._Description AS operation_name
FROM dbo._Document163 AS m
JOIN dbo._Document138 AS d
  ON d._Fld763RRef = m._IDRRef
LEFT JOIN dbo._Reference64 AS oldc
  ON oldc._IDRRef = d._Fld762RRef
LEFT JOIN dbo._Reference64 AS newc
  ON newc._IDRRef = d._Fld767RRef
LEFT JOIN dbo._Reference72 AS mod
  ON mod._IDRRef = d._Fld764RRef
LEFT JOIN dbo._Reference72 AS op
  ON op._IDRRef = d._Fld761RRef
WHERE m._Number IN (@target_contract, N'00000139985')
ORDER BY membership_number, doc138_datetime;

PRINT '09 visit documents for Popova by membership from 2025-08-01 to cutoff';

SELECT
    m._Number AS membership_number,
    prod._Description AS membership_name,
    d._Number AS visit_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS visit_ref,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS visit_datetime,
    d._Posted AS posted,
    d._Marked AS marked,
    c989._Code AS client_989_id,
    c989._Description AS client_989_fio,
    c990._Code AS client_990_id,
    c990._Description AS client_990_fio
FROM dbo._Document150 AS d
LEFT JOIN dbo._Reference64 AS c989
  ON d._Fld989_RTRef = 0x00000040
 AND c989._IDRRef = d._Fld989_RRRef
LEFT JOIN dbo._Reference64 AS c990
  ON c990._IDRRef = d._Fld990RRef
LEFT JOIN dbo._Document163 AS m
  ON d._Fld991_RTRef = 0x000000A3
 AND m._IDRRef = d._Fld991_RRRef
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = m._Fld1446RRef
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
  AND (c989._Code = @target_client_id OR c990._Code = @target_client_id)
  AND CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
      END >= '2025-08-01'
  AND CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
      END <= @cutoff_at
ORDER BY visit_datetime;

PRINT '10 visit summary for Popova by membership from 2025-08-01 to cutoff';

SELECT
    COALESCE(m._Number, N'<no membership>') AS membership_number,
    COALESCE(prod._Description, N'<no membership>') AS membership_name,
    COUNT_BIG(*) AS visit_docs,
    MIN(CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END) AS min_visit,
    MAX(CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END) AS max_visit
FROM dbo._Document150 AS d
LEFT JOIN dbo._Reference64 AS c989
  ON d._Fld989_RTRef = 0x00000040
 AND c989._IDRRef = d._Fld989_RRRef
LEFT JOIN dbo._Reference64 AS c990
  ON c990._IDRRef = d._Fld990RRef
LEFT JOIN dbo._Document163 AS m
  ON d._Fld991_RTRef = 0x000000A3
 AND m._IDRRef = d._Fld991_RRRef
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = m._Fld1446RRef
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
  AND (c989._Code = @target_client_id OR c990._Code = @target_client_id)
  AND CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
      END >= '2025-08-01'
  AND CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
      END <= @cutoff_at
GROUP BY COALESCE(m._Number, N'<no membership>'), COALESCE(prod._Description, N'<no membership>')
ORDER BY min_visit;

PRINT '11 active full membership overlaps for Popova at cutoff';

SELECT
    f.document_number,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.status,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    f.days_to_end
FROM fitbase_part2.membership_import_facts AS f
WHERE f.client_id = @target_client_id
  AND f.is_full_subscription = 1
  AND f.start_date <= CAST(@cutoff_at AS date)
  AND f.end_date >= CAST(@cutoff_at AS date)
ORDER BY f.start_date, f.end_date, f.document_number;
