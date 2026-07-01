SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

DROP TABLE IF EXISTS #targets;
DROP TABLE IF EXISTS #facts;
DROP TABLE IF EXISTS #target_sales;
DROP TABLE IF EXISTS #sale_lines;
DROP TABLE IF EXISTS #target_payments;
DROP TABLE IF EXISTS #client_register_window;

CREATE TABLE #targets (
    contract_id nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    final_price decimal(15, 2) NOT NULL,
    final_paid decimal(15, 2) NOT NULL,
    final_left decimal(15, 2) NOT NULL,
    pattern_note nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL
);

-- 5 active non-named payment_left examples from final membership import.
INSERT INTO #targets(contract_id, final_price, final_paid, final_left, pattern_note)
VALUES
    (N'00000145694', 15990, 7995, 7995, N'known manual case: 50% paid, manager mentioned auxiliary sale/emulator'),
    (N'00000150191', 11990, 5995, 5995, N'common half-left pattern 5995'),
    (N'00000148983', 11990, 2997, 8993, N'common quarter-paid pattern 8993'),
    (N'00000133458', 15990, 3997, 11993, N'large quarter-paid pattern 11993'),
    (N'00000147501', 11990, 2, 11988, N'suspicious paid=2 pattern');

SELECT
    t.pattern_note,
    t.final_price,
    t.final_paid,
    t.final_left,
    f.document_number AS contract_id,
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    f.client_ref,
    CONVERT(binary(16), f.client_ref, 2) AS client_ref_bin,
    f.client_id,
    f.effective_client_fio AS client_fio,
    f.subscription_name,
    f.product_class,
    f.status,
    f.sale_datetime,
    CAST(f.start_date AS date) AS start_date,
    CAST(f.end_date AS date) AS end_date,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_ref,
    CONVERT(binary(16), NULLIF(f.matched_payment_ref, ''), 2) AS matched_payment_ref_bin,
    f.matched_payment_datetime,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source
INTO #facts
FROM #targets AS t
JOIN fitbase_part2.membership_import_facts AS f
  ON f.document_number = t.contract_id;

SELECT
    f.contract_id,
    d._IDRRef AS sale_doc_ref_bin,
    CONVERT(varchar(32), d._IDRRef, 2) AS sale_doc_ref,
    d._Number AS sale_number,
    CASE WHEN d._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END AS sale_datetime,
    d._Posted AS sale_posted,
    d._Marked AS sale_marked,
    SUM(CAST(l._Fld1160 AS decimal(15, 2))) AS sale_line_sum,
    COUNT_BIG(*) AS sale_line_count
INTO #target_sales
FROM #facts AS f
JOIN dbo._Document154_VT1137 AS l
  ON l._Fld1148_RTRef = 0x000000A3
 AND l._Fld1148_RRRef = f.subscription_ref_bin
JOIN dbo._Document154 AS d
  ON d._IDRRef = l._Document154_IDRRef
GROUP BY
    f.contract_id,
    d._IDRRef,
    CONVERT(varchar(32), d._IDRRef, 2),
    d._Number,
    CASE WHEN d._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END,
    d._Posted,
    d._Marked;

SELECT
    d._IDRRef AS sale_doc_ref_bin,
    d._Number AS sale_number,
    CASE WHEN d._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END AS sale_datetime,
    sale_client._Code AS sale_client_id,
    sale_client._Description AS sale_client_fio,
    SUM(CAST(l._Fld1160 AS decimal(15, 2))) AS sale_line_sum,
    STRING_AGG(CONCAT(prod._Description, N' [', CAST(l._Fld1160 AS decimal(15, 2)), N']'), N'; ') AS sale_lines
INTO #sale_lines
FROM dbo._Document154 AS d
JOIN dbo._Document154_VT1137 AS l
  ON l._Document154_IDRRef = d._IDRRef
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = l._Fld1146RRef
LEFT JOIN dbo._Reference64 AS sale_client
  ON sale_client._IDRRef = d._Fld1119RRef
GROUP BY
    d._IDRRef,
    d._Number,
    CASE WHEN d._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END,
    sale_client._Code,
    sale_client._Description;

SELECT DISTINCT
    ts.contract_id,
    p._IDRRef AS payment_ref_bin,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    p._Number AS payment_number,
    CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    CAST(p._Fld1080 AS decimal(15, 2)) AS payment_total,
    pm._Description AS payment_method,
    op._Description AS payment_operation
INTO #target_payments
FROM #target_sales AS ts
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = 0x0000009A
 AND vt._Fld1087_RRRef = ts.sale_doc_ref_bin
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00;

SELECT
    f.contract_id,
    f.final_left,
    f.sale_datetime AS target_sale_datetime,
    CASE WHEN rg._Period > '3000-01-01'
         THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END AS movement_datetime,
    CONVERT(varchar(8), rg._RecorderTRef, 2) AS recorder_tref,
    rg._RecorderRRef AS recorder_ref_bin,
    CASE
        WHEN rg._RecorderTRef = 0x00000098 THEN p._Number
        WHEN rg._RecorderTRef = 0x0000009A THEN s._Number
        WHEN rg._RecorderTRef = 0x00000083 THEN r._Number
        ELSE CONVERT(varchar(32), rg._RecorderRRef, 2)
    END AS recorder_number,
    rg._RecordKind AS record_kind,
    rg._Fld3308_RTRef AS linked_doc_tref_bin,
    CONVERT(varchar(8), rg._Fld3308_RTRef, 2) AS linked_doc_tref,
    rg._Fld3308_RRRef AS linked_doc_ref_bin,
    linked_sale._Number AS linked_sale_number,
    CAST(rg._Fld3311 AS decimal(15, 2)) AS amount_3311,
    pm._Description AS payment_method_if_payment_recorder
INTO #client_register_window
FROM #facts AS f
JOIN dbo._AccumRg3305 AS rg
  ON rg._Fld3307_RTRef = 0x00000040
 AND rg._Fld3307_RRRef = f.client_ref_bin
 AND CASE WHEN rg._Period > '3000-01-01'
          THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END >= DATEADD(day, -30, f.sale_datetime)
 AND CASE WHEN rg._Period > '3000-01-01'
          THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END <= @cutoff_at
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

PRINT '01 targets';
SELECT
    f.contract_id,
    f.client_id,
    f.client_fio,
    f.subscription_name,
    f.status,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.final_price,
    f.final_paid,
    f.final_left,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.pattern_note
FROM #facts AS f
ORDER BY f.contract_id;

PRINT '02 target sale docs and direct payments';
SELECT
    f.contract_id,
    ts.sale_number,
    ts.sale_datetime,
    ts.sale_line_sum,
    tp.payment_number,
    tp.payment_datetime,
    tp.payment_total,
    tp.payment_method,
    tp.payment_operation
FROM #facts AS f
LEFT JOIN #target_sales AS ts
  ON ts.contract_id = f.contract_id
LEFT JOIN #target_payments AS tp
  ON tp.contract_id = f.contract_id
ORDER BY f.contract_id, tp.payment_datetime;

PRINT '03 target sale register movements';
SELECT
    crw.contract_id,
    crw.movement_datetime,
    crw.recorder_tref,
    crw.recorder_number,
    crw.record_kind,
    crw.linked_sale_number,
    crw.amount_3311,
    crw.payment_method_if_payment_recorder
FROM #client_register_window AS crw
JOIN #target_sales AS ts
  ON crw.linked_doc_tref_bin = 0x0000009A
 AND crw.linked_doc_ref_bin = ts.sale_doc_ref_bin
ORDER BY crw.contract_id, crw.movement_datetime, crw.record_kind;

PRINT '04 exact/near amount movements by same client after target sale';
SELECT
    crw.contract_id,
    crw.final_left,
    crw.movement_datetime,
    crw.recorder_tref,
    crw.recorder_number,
    crw.record_kind,
    crw.linked_sale_number,
    crw.amount_3311,
    crw.payment_method_if_payment_recorder,
    sl.sale_lines,
    DATEDIFF(day, crw.target_sale_datetime, crw.movement_datetime) AS days_from_target_sale,
    ABS(crw.amount_3311 - crw.final_left) AS amount_diff
FROM #client_register_window AS crw
LEFT JOIN #sale_lines AS sl
  ON sl.sale_doc_ref_bin = crw.linked_doc_ref_bin
WHERE crw.movement_datetime >= crw.target_sale_datetime
  AND ABS(crw.amount_3311 - crw.final_left) <= 5
ORDER BY crw.contract_id, amount_diff, crw.movement_datetime, crw.record_kind;

PRINT '05 paired sale/payment candidates on same linked sale';
WITH grouped AS (
    SELECT
        crw.contract_id,
        crw.final_left,
        crw.linked_doc_ref_bin,
        crw.linked_sale_number,
        MIN(crw.movement_datetime) AS first_movement_datetime,
        MAX(crw.movement_datetime) AS last_movement_datetime,
        SUM(CASE WHEN crw.record_kind = 1 THEN crw.amount_3311 ELSE 0 END) AS sale_amount,
        SUM(CASE WHEN crw.record_kind = 0 THEN crw.amount_3311 ELSE 0 END) AS payment_amount,
        COUNT(CASE WHEN crw.record_kind = 1 THEN 1 END) AS sale_movements,
        COUNT(CASE WHEN crw.record_kind = 0 THEN 1 END) AS payment_movements
    FROM #client_register_window AS crw
    WHERE crw.linked_doc_tref_bin = 0x0000009A
      AND crw.movement_datetime >= crw.target_sale_datetime
    GROUP BY
        crw.contract_id,
        crw.final_left,
        crw.linked_doc_ref_bin,
        crw.linked_sale_number
)
SELECT
    g.contract_id,
    g.final_left,
    g.linked_sale_number,
    g.first_movement_datetime,
    g.last_movement_datetime,
    g.sale_amount,
    g.payment_amount,
    g.sale_movements,
    g.payment_movements,
    sl.sale_lines,
    ABS(g.sale_amount - g.final_left) AS sale_minus_left_abs,
    ABS(g.payment_amount - g.final_left) AS payment_minus_left_abs
FROM grouped AS g
LEFT JOIN #sale_lines AS sl
  ON sl.sale_doc_ref_bin = g.linked_doc_ref_bin
WHERE ABS(g.sale_amount - g.final_left) <= 5
   OR ABS(g.payment_amount - g.final_left) <= 5
ORDER BY g.contract_id, g.first_movement_datetime;

PRINT '06 auxiliary product name candidates';
SELECT
    f.contract_id,
    f.final_left,
    sl.sale_number,
    sl.sale_datetime,
    sl.sale_line_sum,
    sl.sale_lines,
    sale_rg.sale_amount,
    pay_rg.payment_amount,
    ABS(COALESCE(sale_rg.sale_amount, sl.sale_line_sum) - f.final_left) AS amount_diff_to_left
FROM #facts AS f
JOIN #sale_lines AS sl
  ON sl.sale_client_id = f.client_id
 AND sl.sale_datetime >= DATEADD(day, -30, f.sale_datetime)
 AND sl.sale_datetime <= @cutoff_at
OUTER APPLY (
    SELECT SUM(crw.amount_3311) AS sale_amount
    FROM #client_register_window AS crw
    WHERE crw.contract_id = f.contract_id
      AND crw.linked_doc_ref_bin = sl.sale_doc_ref_bin
      AND crw.record_kind = 1
) AS sale_rg
OUTER APPLY (
    SELECT SUM(crw.amount_3311) AS payment_amount
    FROM #client_register_window AS crw
    WHERE crw.contract_id = f.contract_id
      AND crw.linked_doc_ref_bin = sl.sale_doc_ref_bin
      AND crw.record_kind = 0
) AS pay_rg
WHERE LOWER(sl.sale_lines) LIKE N'%абонемент на фитнес%'
   OR LOWER(sl.sale_lines) LIKE N'%доплата%'
   OR LOWER(sl.sale_lines) LIKE N'%эмулятор%'
ORDER BY f.contract_id, sl.sale_datetime;

PRINT '07 all non-small client register movements after target sale';
SELECT
    crw.contract_id,
    crw.final_left,
    crw.movement_datetime,
    crw.recorder_tref,
    crw.recorder_number,
    crw.record_kind,
    crw.linked_sale_number,
    crw.amount_3311,
    crw.payment_method_if_payment_recorder,
    sl.sale_lines,
    DATEDIFF(day, crw.target_sale_datetime, crw.movement_datetime) AS days_from_target_sale
FROM #client_register_window AS crw
LEFT JOIN #sale_lines AS sl
  ON sl.sale_doc_ref_bin = crw.linked_doc_ref_bin
WHERE crw.movement_datetime >= crw.target_sale_datetime
  AND crw.amount_3311 >= 1000
ORDER BY crw.contract_id, crw.movement_datetime, crw.record_kind;
