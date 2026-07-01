SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @target_client_id nvarchar(20) = N'000017489';
DECLARE @target_fio nvarchar(200) = N'Тарасенко Александр Сергеевич';
DECLARE @target_contract nvarchar(20) = N'00000100483';

PRINT '01 final membership facts for target client';

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
    f.product_class,
    f.status,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_ref,
    f.matched_payment_datetime,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_operation,
    f.matched_payment_match_source,
    f.owner_change_number,
    f.owner_change_datetime,
    f.owner_change_count_for_membership,
    f.client_role_source,
    f.raw_source,
    f.subscription_ref
FROM fitbase_part2.membership_import_facts AS f
WHERE f.client_id = @target_client_id
   OR f.effective_client_fio = @target_fio
ORDER BY f.sale_datetime, f.document_number;

PRINT '02 owner changes for suspicious and adjacent transferred contracts';

SELECT
    oc.membership_number,
    oc.membership_name,
    oc.owner_change_number,
    oc.owner_change_datetime,
    oc.old_client_id,
    oc.old_client_fio,
    oc.new_client_id,
    oc.new_client_fio,
    oc.modifier_name,
    oc.is_effective_owner_change_on_cutoff,
    oc.raw_source
FROM fitbase_part2.stg_membership_owner_changes AS oc
WHERE oc.membership_number IN (@target_contract, N'00000109874')
ORDER BY oc.membership_number, oc.owner_change_datetime;

PRINT '03 raw Document163 target contract with decoded key references';

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
    d._Fld1458,
    d._Fld1461,
    d._Fld1463,
    d._Fld1464,
    d._Fld1465,
    d._Fld1466,
    d._Fld1467,
    d._Fld1468,
    d._Fld1474,
    d._Fld1481,
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
WHERE d._Number = @target_contract;

PRINT '04 subscription register rows for target contract';

SELECT
    d._Number AS document_number,
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
    r._Fld8007 AS visits_candidate_8007,
    r._Fld8008 AS visits_candidate_8008,
    r._Fld8009 AS visits_candidate_8009,
    st._Description AS status_name,
    book_st._Description AS booking_status_name
FROM dbo._InfoRg3060 AS r
JOIN dbo._Document163 AS d
  ON d._IDRRef = r._Fld3061RRef
LEFT JOIN dbo._Reference5062 AS st
  ON st._IDRRef = r._Fld5960RRef
LEFT JOIN dbo._Reference5062 AS book_st
  ON book_st._IDRRef = r._Fld5960RRef
WHERE d._Number = @target_contract
ORDER BY r._Fld3062;

PRINT '05 Document154 sale lines directly linked to target contract';

SELECT
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
WHERE m._Number = @target_contract
ORDER BY sale_doc_datetime, vt._LineNo1138;

PRINT '06 Payment Document152 rows linked through Document154 sale docs';

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
WHERE m._Number = @target_contract
ORDER BY payment_datetime;

PRINT '07 payment docs around target date for involved clients';

WITH involved_clients AS (
    SELECT old_client_id AS client_id, old_client_fio AS client_fio
    FROM fitbase_part2.stg_membership_owner_changes
    WHERE membership_number = @target_contract
    UNION
    SELECT new_client_id, new_client_fio
    FROM fitbase_part2.stg_membership_owner_changes
    WHERE membership_number = @target_contract
    UNION
    SELECT original_client_id, original_client_fio
    FROM fitbase_part2.membership_import_facts
    WHERE document_number = @target_contract
)
SELECT
    ic.client_id,
    ic.client_fio,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    op._Description AS operation_name,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_total
FROM involved_clients AS ic
JOIN dbo._Reference64 AS c
  ON c._Code = ic.client_id
JOIN dbo._Document152 AS p
  ON (
      p._Fld1057_RTRef = 0x00000040
      AND p._Fld1057_RRRef = c._IDRRef
  )
  OR p._Fld1058RRef = c._IDRRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Fld1080 > 0
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END >= '2022-06-01'
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END < '2022-07-10'
ORDER BY payment_datetime, ic.client_id, payment_number;

PRINT '08 nearby memberships for target client and owner-change involved clients';

WITH involved_clients AS (
    SELECT old_client_id AS client_id, old_client_fio AS client_fio
    FROM fitbase_part2.stg_membership_owner_changes
    WHERE membership_number = @target_contract
    UNION
    SELECT new_client_id, new_client_fio
    FROM fitbase_part2.stg_membership_owner_changes
    WHERE membership_number = @target_contract
    UNION
    SELECT original_client_id, original_client_fio
    FROM fitbase_part2.membership_import_facts
    WHERE document_number = @target_contract
)
SELECT
    ic.client_id AS involved_client_id,
    ic.client_fio AS involved_client_fio,
    f.document_number,
    f.client_id AS final_client_id,
    f.effective_client_fio,
    f.original_client_id,
    f.original_client_fio,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.rg_price,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.owner_change_number,
    f.status
FROM involved_clients AS ic
JOIN fitbase_part2.membership_import_facts AS f
  ON f.client_id = ic.client_id
  OR f.original_client_id = ic.client_id
  OR f.effective_client_id = ic.client_id
WHERE f.sale_datetime >= '2021-12-01'
  AND f.sale_datetime < '2023-03-01'
ORDER BY ic.client_id, f.sale_datetime, f.document_number;

PRINT '09 all posted payment docs for involved clients from 2022-01-01 to 2023-07-01';

WITH involved_clients AS (
    SELECT N'000017489' AS client_id, N'Тарасенко Александр Сергеевич' AS client_fio
    UNION ALL SELECT N'000010033', N'Ли Сергей Вячеславович'
    UNION ALL SELECT N'000054013', N'Коновалов Никита Витальевич'
)
SELECT
    ic.client_id,
    ic.client_fio,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    op._Description AS operation_name,
    pm._Description AS payment_method,
    p._Fld1080 AS payment_total
FROM involved_clients AS ic
JOIN dbo._Reference64 AS c
  ON c._Code = ic.client_id
JOIN dbo._Document152 AS p
  ON (
      p._Fld1057_RTRef = 0x00000040
      AND p._Fld1057_RRRef = c._IDRRef
  )
  OR p._Fld1058RRef = c._IDRRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Fld1080 > 0
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END >= '2022-01-01'
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END < '2023-07-01'
ORDER BY ic.client_id, payment_datetime, payment_number;

PRINT '10 visit documents for target contract';

DECLARE @target_subscription_ref binary(16) =
    CONVERT(binary(16), 'AC80A4BF01266AD411ECF22FC10B0403', 2);
DECLARE @target_owner_change_at datetime2(0) = '2023-02-01 16:46:09';

SELECT TOP (100)
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
    c990._Description AS client_990_fio,
    d._Fld995 AS duration_seconds,
    d._Fld999,
    d._Fld1000
FROM dbo._Document150 AS d
LEFT JOIN dbo._Reference64 AS c989
  ON d._Fld989_RTRef = 0x00000040
 AND c989._IDRRef = d._Fld989_RRRef
LEFT JOIN dbo._Reference64 AS c990
  ON c990._IDRRef = d._Fld990RRef
WHERE d._Fld991_RRRef = @target_subscription_ref
ORDER BY visit_datetime, visit_number;

PRINT '11 visit document counts before/after owner change';

SELECT
    CASE
        WHEN CASE
                WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
                ELSE d._Date_Time
             END < @target_owner_change_at
        THEN N'before_owner_change'
        ELSE N'after_owner_change'
    END AS period_group,
    COUNT_BIG(*) AS visit_docs,
    MIN(CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END) AS min_visit_datetime,
    MAX(CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END) AS max_visit_datetime
FROM dbo._Document150 AS d
WHERE d._Fld991_RRRef = @target_subscription_ref
  AND d._Posted = 0x01
  AND d._Marked = 0x00
GROUP BY
    CASE
        WHEN CASE
                WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
                ELSE d._Date_Time
             END < @target_owner_change_at
        THEN N'before_owner_change'
        ELSE N'after_owner_change'
    END
ORDER BY min_visit_datetime;

PRINT '12 AccumRg3336 movements before/after owner change';

SELECT
    CASE
        WHEN DATEADD(year, -2000, r._Period) < @target_owner_change_at
        THEN N'before_owner_change'
        ELSE N'after_owner_change'
    END AS period_group,
    COUNT_BIG(*) AS movement_rows,
    SUM(CASE WHEN r._RecordKind = 0 THEN r._Fld3339 ELSE 0 END) AS receipt_qty,
    SUM(CASE WHEN r._RecordKind = 1 THEN r._Fld3339 ELSE 0 END) AS expense_qty,
    SUM(CASE
        WHEN r._RecordKind = 0 THEN r._Fld3339
        WHEN r._RecordKind = 1 THEN -r._Fld3339
        ELSE 0
    END) AS signed_balance,
    MIN(DATEADD(year, -2000, r._Period)) AS min_period,
    MAX(DATEADD(year, -2000, r._Period)) AS max_period
FROM dbo._AccumRg3336 AS r
WHERE r._Fld3337_RRRef = @target_subscription_ref
  AND r._Active = 0x01
GROUP BY
    CASE
        WHEN DATEADD(year, -2000, r._Period) < @target_owner_change_at
        THEN N'before_owner_change'
        ELSE N'after_owner_change'
    END
ORDER BY min_period;
