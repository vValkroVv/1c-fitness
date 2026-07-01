SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF OBJECT_ID('tempdb..#enriched_zero_direct_active') IS NOT NULL
    DROP TABLE #enriched_zero_direct_active;

WITH zero_direct_active AS (
    SELECT f.*
    FROM fitbase_part2.membership_import_facts AS f
    WHERE f.rg_price = 0
      AND f.matched_payment_ref IS NOT NULL
      AND f.matched_payment_match_source LIKE N'direct%'
      AND f.matched_payment_method IS NOT NULL
      AND LTRIM(RTRIM(f.matched_payment_method)) <> N''
      AND f.product_class = N'full_subscription'
      AND f.is_active_on_cutoff = 1
),
enriched AS (
    SELECT
        z.document_number,
        z.client_id,
        z.effective_client_fio,
        z.subscription_name,
        z.sale_datetime,
        z.start_date,
        z.end_date,
        COALESCE(NULLIF(z.status, N''), N'blank') AS status_name,
        z.rg_price,
        z.rg_paid_candidate,
        z.matched_payment_amount,
        z.matched_payment_method,
        z.subscription_ref,
        COALESCE(visits.visit_docs, 0) AS visit_docs,
        COALESCE(sale_lines.sale_line_docs, 0) AS sale_line_docs,
        COALESCE(sale_lines.sale_line_sum, 0) AS sale_line_sum,
        fc.selected_subscription_ref,
        fc.selected_subscription_name,
        CASE WHEN fc.selected_subscription_ref = z.subscription_ref THEN 1 ELSE 0 END AS is_selected_subscription
    FROM zero_direct_active AS z
    OUTER APPLY (
        SELECT COUNT_BIG(*) AS visit_docs
        FROM dbo._Document150 AS d
        WHERE d._Fld991_RTRef = 0x000000A3
          AND d._Fld991_RRRef = CONVERT(binary(16), z.subscription_ref, 2)
          AND d._Posted = 0x01
          AND d._Marked = 0x00
    ) AS visits
    OUTER APPLY (
        SELECT
            COUNT_BIG(DISTINCT d154._IDRRef) AS sale_line_docs,
            SUM(CAST(vt._Fld1140 AS decimal(15, 2))) AS sale_line_sum
        FROM dbo._Document154_VT1137 AS vt
        JOIN dbo._Document154 AS d154
          ON d154._IDRRef = vt._Document154_IDRRef
        WHERE vt._Fld1148_RTRef = 0x000000A3
          AND vt._Fld1148_RRRef = CONVERT(binary(16), z.subscription_ref, 2)
          AND d154._Posted = 0x01
          AND d154._Marked = 0x00
    ) AS sale_lines
    LEFT JOIN fitbase_part2.final_funnel_clients AS fc
      ON fc.client_id = z.client_id
)
SELECT
    *
INTO #enriched_zero_direct_active
FROM enriched;

SELECT
    N'summary' AS block_name,
    COUNT(*) AS rows_count,
    SUM(CASE WHEN visit_docs > 0 THEN 1 ELSE 0 END) AS with_visits,
    SUM(CASE WHEN sale_line_sum > 0 THEN 1 ELSE 0 END) AS with_positive_sale_line,
    SUM(CASE WHEN matched_payment_amount > 0 THEN 1 ELSE 0 END) AS with_positive_matched_payment,
    SUM(is_selected_subscription) AS selected_in_funnel
FROM #enriched_zero_direct_active
UNION ALL
SELECT
    N'status=' + status_name AS block_name,
    COUNT(*) AS rows_count,
    SUM(CASE WHEN visit_docs > 0 THEN 1 ELSE 0 END) AS with_visits,
    SUM(CASE WHEN sale_line_sum > 0 THEN 1 ELSE 0 END) AS with_positive_sale_line,
    SUM(CASE WHEN matched_payment_amount > 0 THEN 1 ELSE 0 END) AS with_positive_matched_payment,
    SUM(is_selected_subscription) AS selected_in_funnel
FROM #enriched_zero_direct_active
GROUP BY status_name
ORDER BY block_name;

SELECT
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    status_name,
    matched_payment_amount,
    matched_payment_method,
    visit_docs,
    sale_line_sum,
    is_selected_subscription,
    selected_subscription_name
FROM #enriched_zero_direct_active
ORDER BY is_selected_subscription DESC, visit_docs DESC, sale_datetime, document_number;
