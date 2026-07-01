SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF OBJECT_ID('tempdb..#zero_direct_full') IS NOT NULL DROP TABLE #zero_direct_full;
IF OBJECT_ID('tempdb..#sale_docs') IS NOT NULL DROP TABLE #sale_docs;
IF OBJECT_ID('tempdb..#payment_sums') IS NOT NULL DROP TABLE #payment_sums;

SELECT
    f.document_number,
    f.effective_client_fio AS client_fio,
    f.subscription_name,
    f.is_active_on_cutoff,
    f.status,
    f.membership_sale_line_amount,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    f.document131_posted_unmarked_refund_count,
    f.subscription_ref
INTO #zero_direct_full
FROM fitbase_part2.membership_import_facts AS f
WHERE f.is_full_subscription = 1
  AND ISNULL(f.rg_price, 0) = 0
  AND ISNULL(f.matched_payment_amount, 0) > 0
  AND f.matched_payment_match_source LIKE N'direct%'
  AND ISNULL(f.document131_posted_unmarked_refund_count, 0) = 0;

SELECT
    z.document_number,
    sale_doc._IDRRef AS sale_doc_ref
INTO #sale_docs
FROM #zero_direct_full AS z
JOIN dbo._Document154_VT1137 AS sale_line
  ON sale_line._Fld1148_RTRef = 0x000000A3
 AND sale_line._Fld1148_RRRef = CONVERT(binary(16), z.subscription_ref, 2)
JOIN dbo._Document154 AS sale_doc
  ON sale_doc._IDRRef = sale_line._Document154_IDRRef;

SELECT
    sd.document_number,
    SUM(CAST(p._Fld1080 AS decimal(15, 2))) AS direct_payment_sum,
    COUNT_BIG(*) AS direct_payment_docs
INTO #payment_sums
FROM #sale_docs AS sd
JOIN dbo._Document152_VT1083 AS vt
  ON vt._Fld1087_RTRef = 0x0000009A
 AND vt._Fld1087_RRRef = sd.sale_doc_ref
JOIN dbo._Document152 AS p
  ON p._IDRRef = vt._Document152_IDRRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
GROUP BY sd.document_number;

PRINT '01 full zero-direct without Document131 refund: payment sum vs sale line';
SELECT
    COUNT_BIG(*) AS rows_total,
    SUM(CASE WHEN z.is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_rows,
    SUM(CASE
        WHEN ABS(ISNULL(ps.direct_payment_sum, 0) - ISNULL(z.membership_sale_line_amount, 0)) <= 0.01
        THEN 1 ELSE 0
    END) AS direct_sum_eq_sale_line,
    SUM(CASE
        WHEN ABS(ISNULL(ps.direct_payment_sum, 0) - ISNULL(z.membership_sale_line_amount, 0)) > 0.01
        THEN 1 ELSE 0
    END) AS direct_sum_diff_sale_line,
    SUM(CASE
        WHEN ABS(ISNULL(z.matched_payment_amount, 0) - ISNULL(z.membership_sale_line_amount, 0)) > 0.01
        THEN 1 ELSE 0
    END) AS matched_single_diff_sale_line
FROM #zero_direct_full AS z
LEFT JOIN #payment_sums AS ps
  ON ps.document_number = z.document_number;

PRINT '02 rows where direct payment sum differs from membership sale line';
SELECT
    z.document_number AS contract_id,
    z.client_fio,
    z.subscription_name,
    z.is_active_on_cutoff,
    z.status,
    z.membership_sale_line_amount,
    z.matched_payment_amount,
    ps.direct_payment_sum,
    ps.direct_payment_docs,
    z.matched_payment_method
FROM #zero_direct_full AS z
LEFT JOIN #payment_sums AS ps
  ON ps.document_number = z.document_number
WHERE ABS(ISNULL(ps.direct_payment_sum, 0) - ISNULL(z.membership_sale_line_amount, 0)) > 0.01
ORDER BY
    z.is_active_on_cutoff DESC,
    z.document_number;
