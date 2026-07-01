SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

WITH zero_direct_trial AS (
    SELECT f.*
    FROM fitbase_part2.membership_import_facts AS f
    WHERE f.rg_price = 0
      AND f.matched_payment_ref IS NOT NULL
      AND f.matched_payment_match_source LIKE N'direct%'
      AND f.product_class = N'trial_or_guest'
)
SELECT
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    COALESCE(NULLIF(f.status, N''), N'blank') AS status_name,
    f.matched_payment_amount,
    f.matched_payment_method,
    COALESCE(sale_lines.sale_line_sum, 0) AS sale_line_sum,
    COALESCE(visits.visit_docs, 0) AS visit_docs
FROM zero_direct_trial AS f
OUTER APPLY (
    SELECT SUM(CAST(vt._Fld1140 AS decimal(15, 2))) AS sale_line_sum
    FROM dbo._Document154_VT1137 AS vt
    JOIN dbo._Document154 AS d154
      ON d154._IDRRef = vt._Document154_IDRRef
    WHERE vt._Fld1148_RTRef = 0x000000A3
      AND vt._Fld1148_RRRef = CONVERT(binary(16), f.subscription_ref, 2)
      AND d154._Posted = 0x01
      AND d154._Marked = 0x00
) AS sale_lines
OUTER APPLY (
    SELECT COUNT_BIG(*) AS visit_docs
    FROM dbo._Document150 AS d
    WHERE d._Fld991_RTRef = 0x000000A3
      AND d._Fld991_RRRef = CONVERT(binary(16), f.subscription_ref, 2)
      AND d._Posted = 0x01
      AND d._Marked = 0x00
) AS visits
ORDER BY f.sale_datetime, f.document_number;
