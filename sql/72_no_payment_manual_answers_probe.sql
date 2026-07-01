SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#targets') IS NOT NULL DROP TABLE #targets;
IF OBJECT_ID('tempdb..#facts') IS NOT NULL DROP TABLE #facts;
IF OBJECT_ID('tempdb..#sale_docs') IS NOT NULL DROP TABLE #sale_docs;

CREATE TABLE #targets (
    contract_id nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    manual_answer nvarchar(1000) COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #targets(contract_id, manual_answer)
VALUES
    (N'00000149776', N'Платеж есть и по активному и по будущему членству. Перенести два членства. Не стояла дата активации нового членства.'),
    (N'00000150179', N'Платеж есть. Оплачено 50% от рассрочки.'),
    (N'00000134419', N'На клиенте была лишняя продажа. Удалила.'),
    (N'00000143904', N'На клиенте была лишняя продажа. Удалила.'),
    (N'00000150540', N'Платеж есть.'),
    (N'00000149797', N'На клиенте была лишняя продажа. Удалила.'),
    (N'00000142446', N'На клиенте была лишняя продажа. Удалила.');

SELECT
    t.contract_id,
    t.manual_answer,
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
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    f.client_ref,
    f.original_client_ref,
    f.holder_client_ref,
    f.payer_client_ref,
    f.subscription_ref
INTO #facts
FROM #targets AS t
JOIN fitbase_part2.membership_import_facts AS f
  ON f.document_number = t.contract_id;

PRINT '01 target facts from membership_import_facts';
SELECT
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
    manual_answer
FROM #facts
ORDER BY contract_id;

SELECT
    f.contract_id,
    CONVERT(varchar(32), sale_doc._IDRRef, 2) AS sale_doc_ref,
    sale_doc._Number AS sale_number,
    CASE
        WHEN sale_doc._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, sale_doc._Date_Time)
        ELSE sale_doc._Date_Time
    END AS sale_doc_datetime,
    SUM(CAST(sale_line._Fld1160 AS decimal(15, 2))) AS sale_line_sum,
    COUNT_BIG(*) AS sale_line_count
INTO #sale_docs
FROM #facts AS f
JOIN dbo._Document154_VT1137 AS sale_line
  ON sale_line._Fld1148_RTRef = 0x000000A3
 AND sale_line._Fld1148_RRRef = CONVERT(binary(16), f.subscription_ref, 2)
JOIN dbo._Document154 AS sale_doc
  ON sale_doc._IDRRef = sale_line._Document154_IDRRef
GROUP BY
    f.contract_id,
    CONVERT(varchar(32), sale_doc._IDRRef, 2),
    sale_doc._Number,
    CASE
        WHEN sale_doc._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, sale_doc._Date_Time)
        ELSE sale_doc._Date_Time
    END;

PRINT '02 linked sale docs / membership sale lines';
SELECT *
FROM #sale_docs
ORDER BY contract_id, sale_doc_datetime;

PRINT '03 payments linked through sale doc VT1083 -> Document154';
SELECT
    sd.contract_id,
    p._Number AS payment_number,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    CAST(p._Fld1080 AS decimal(15, 2)) AS payment_total,
    pm._Description AS payment_method,
    op._Description AS operation_name,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    sd.sale_number,
    sd.sale_line_sum
FROM #sale_docs AS sd
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = 0x0000009A
 AND vt._Fld1087_RRRef = CONVERT(binary(16), sd.sale_doc_ref, 2)
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
ORDER BY sd.contract_id, payment_datetime;

PRINT '04 all client Document152 payments around target sale date (+/- 180 days, through cutoff)';
SELECT
    f.contract_id,
    p.sale_ref,
    p.sale_datetime,
    p.product_name,
    p.product_class,
    p.amount,
    p.payment_method,
    p.operation_name,
    p.client_ref AS payment_client_ref,
    DATEDIFF(day, f.sale_datetime, p.sale_datetime) AS days_from_target_sale
FROM #facts AS f
JOIN fitbase_part2.stg_sales_all AS p
  ON p.sale_source = N'dbo._Document152'
 AND p.amount IS NOT NULL
 AND p.amount > 0
 AND p.sale_datetime <= @cutoff_at
 AND p.client_ref IN (
    f.client_ref,
    f.original_client_ref,
    f.holder_client_ref,
    f.payer_client_ref
 )
 AND p.sale_datetime >= DATEADD(day, -180, f.sale_datetime)
 AND p.sale_datetime < DATEADD(day, 181, f.sale_datetime)
ORDER BY f.contract_id, ABS(DATEDIFF(day, f.sale_datetime, p.sale_datetime)), p.sale_datetime;

PRINT '05 all active/not-finished full memberships for target clients';
SELECT
    f.contract_id AS target_contract_id,
    o.document_number AS other_contract_id,
    o.effective_client_fio AS client_fio,
    o.subscription_name,
    o.status,
    o.sale_datetime,
    CAST(o.start_date AS date) AS start_date,
    CAST(o.end_date AS date) AS end_date,
    o.rg_price,
    o.rg_paid_candidate,
    o.matched_payment_amount,
    o.matched_payment_method,
    o.matched_payment_match_source
FROM #facts AS f
JOIN fitbase_part2.membership_import_facts AS o
  ON o.client_id = f.client_id
 AND o.is_full_subscription = 1
 AND CAST(o.end_date AS date) >= CAST(@cutoff_at AS date)
ORDER BY f.contract_id, o.end_date, o.start_date, o.document_number;

PRINT '06 raw Document152 payments by target client code, 2026-04-01..cutoff';
WITH raw_client_payments AS (
    SELECT
        f.contract_id,
        f.client_id,
        f.client_fio,
        p._Number AS payment_number,
        CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
        END AS payment_datetime,
        CAST(p._Fld1080 AS decimal(15, 2)) AS payment_total,
        pm._Description AS payment_method,
        op._Description AS operation_name,
        cp1._Code AS client_1057_id,
        cp2._Code AS client_1058_id
    FROM #facts AS f
    JOIN dbo._Reference64 AS c
      ON c._Code = f.client_id
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
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = p._Fld1072RRef
    WHERE p._Posted = 0x01
      AND p._Marked = 0x00
      AND CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
          END >= '2026-04-01'
      AND CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
          END <= @cutoff_at
)
SELECT
    contract_id,
    client_id,
    COUNT_BIG(*) AS payment_docs,
    SUM(payment_total) AS payment_total_sum,
    MIN(payment_datetime) AS first_payment_datetime,
    MAX(payment_datetime) AS last_payment_datetime
FROM raw_client_payments
GROUP BY contract_id, client_id
ORDER BY contract_id;

PRINT '07 raw Document152 payment details by target client code, 2026-04-01..cutoff';
WITH raw_client_payments AS (
    SELECT
        f.contract_id,
        f.client_id,
        f.client_fio,
        p._Number AS payment_number,
        CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
        END AS payment_datetime,
        CAST(p._Fld1080 AS decimal(15, 2)) AS payment_total,
        pm._Description AS payment_method,
        op._Description AS operation_name,
        cp1._Code AS client_1057_id,
        cp2._Code AS client_1058_id
    FROM #facts AS f
    JOIN dbo._Reference64 AS c
      ON c._Code = f.client_id
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
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = p._Fld1072RRef
    WHERE p._Posted = 0x01
      AND p._Marked = 0x00
      AND CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
          END >= '2026-04-01'
      AND CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
          END <= @cutoff_at
)
SELECT
    contract_id,
    payment_number,
    payment_datetime,
    payment_total,
    payment_method,
    operation_name,
    client_1057_id,
    client_1058_id
FROM raw_client_payments
ORDER BY contract_id, payment_datetime;
