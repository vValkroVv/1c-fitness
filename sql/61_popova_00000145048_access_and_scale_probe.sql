SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @target_contract nvarchar(20) = N'00000145048';
DECLARE @paid_contract nvarchar(20) = N'00000139985';
DECLARE @target_client_id nvarchar(20) = N'000014308';
DECLARE @target_fio nvarchar(200) = N'Попова Ирина Борисовна';
DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

PRINT '01 final funnel client selected membership';

SELECT
    client_id,
    client_fio,
    phones,
    funnel,
    funnel_step,
    normalized_club,
    selected_subscription_name,
    selected_subscription_start_date,
    selected_subscription_end_date,
    selected_subscription_sale_date,
    selected_subscription_ref,
    active_full_subscription_count,
    finished_full_subscription_count,
    full_subscription_count,
    selected_card_number,
    selection_reason,
    validation_status
FROM fitbase_part2.final_funnel_clients
WHERE client_id = @target_client_id
   OR client_fio = @target_fio;

PRINT '02 all visits for target suspicious membership only';

SELECT
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
JOIN dbo._Document163 AS m
  ON d._Fld991_RTRef = 0x000000A3
 AND m._IDRRef = d._Fld991_RRRef
WHERE m._Number = @target_contract
  AND d._Posted = 0x01
  AND d._Marked = 0x00;

PRINT '03 all visits for paid overlapping membership only';

SELECT
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
JOIN dbo._Document163 AS m
  ON d._Fld991_RTRef = 0x000000A3
 AND m._IDRRef = d._Fld991_RRRef
WHERE m._Number = @paid_contract
  AND d._Posted = 0x01
  AND d._Marked = 0x00;

PRINT '04 active full memberships for Popova on suspicious start date 2026-02-05';

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
    f.matched_payment_match_source
FROM fitbase_part2.membership_import_facts AS f
WHERE f.client_id = @target_client_id
  AND f.is_full_subscription = 1
  AND f.start_date <= '2026-02-05'
  AND f.end_date >= '2026-02-05'
ORDER BY f.start_date, f.end_date, f.document_number;

PRINT '05 active full memberships for Popova on cutoff';

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
    f.matched_payment_match_source
FROM fitbase_part2.membership_import_facts AS f
WHERE f.client_id = @target_client_id
  AND f.is_full_subscription = 1
  AND f.start_date <= CAST(@cutoff_at AS date)
  AND f.end_date >= CAST(@cutoff_at AS date)
ORDER BY f.start_date, f.end_date, f.document_number;

PRINT '06 payment search around suspicious sale using any client role fields';

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
FROM dbo._Document152 AS p
LEFT JOIN dbo._Reference64 AS cp1
  ON p._Fld1057_RTRef = 0x00000040
 AND cp1._IDRRef = p._Fld1057_RRRef
LEFT JOIN dbo._Reference64 AS cp2
  ON cp2._IDRRef = p._Fld1058RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND (cp1._Code = @target_client_id OR cp2._Code = @target_client_id)
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END >= '2025-12-20'
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END < '2026-02-20'
ORDER BY payment_datetime, p._Number;

PRINT '07 sales docs around suspicious date for Popova';

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
    CASE WHEN vt._Fld1148_RTRef = 0x000000A3 THEN m._Number ELSE NULL END AS linked_membership_number,
    vt._Fld1140,
    vt._Fld1154,
    vt._Fld1160
FROM dbo._Document154 AS d154
LEFT JOIN dbo._Reference64 AS c
  ON c._IDRRef = d154._Fld1119RRef
LEFT JOIN dbo._Document154_VT1137 AS vt
  ON vt._Document154_IDRRef = d154._IDRRef
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = vt._Fld1146RRef
LEFT JOIN dbo._Document163 AS m
  ON vt._Fld1148_RTRef = 0x000000A3
 AND m._IDRRef = vt._Fld1148_RRRef
WHERE c._Code = @target_client_id
  AND CASE
        WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time)
        ELSE d154._Date_Time
      END >= '2025-12-20'
  AND CASE
        WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time)
        ELSE d154._Date_Time
      END < '2026-02-20'
ORDER BY sale_doc_datetime, sale_doc_number, vt._LineNo1138;

PRINT '08 scale: D_positive_no_payment_cash_327 rows with Contact/Booking/Refusal statuses and overlap';

WITH d_rows AS (
    SELECT
        f.document_number,
        f.client_id,
        f.effective_client_fio,
        f.subscription_name,
        f.sale_datetime,
        f.start_date,
        f.end_date,
        f.status,
        f.rg_price,
        f.rg_paid_candidate,
        f.matched_payment_ref,
        f.is_active_on_cutoff
    FROM fitbase_part2.membership_import_facts AS f
    WHERE f.rg_price > 0
      AND f.matched_payment_ref IS NULL
      AND f.is_full_subscription = 1
      AND f.start_date <= CAST(@cutoff_at AS date)
      AND f.end_date >= CAST(@cutoff_at AS date)
),
overlaps AS (
    SELECT
        d.document_number,
        COUNT_BIG(*) AS overlapping_active_full_count
    FROM d_rows AS d
    JOIN fitbase_part2.membership_import_facts AS other_f
      ON other_f.client_id = d.client_id
     AND other_f.document_number <> d.document_number
     AND other_f.is_full_subscription = 1
     AND other_f.start_date <= CAST(@cutoff_at AS date)
     AND other_f.end_date >= CAST(@cutoff_at AS date)
    GROUP BY d.document_number
)
SELECT
    COALESCE(NULLIF(d.status, N''), N'<blank>') AS status,
    CASE WHEN COALESCE(o.overlapping_active_full_count, 0) > 0 THEN 1 ELSE 0 END AS has_other_active_full,
    COUNT_BIG(*) AS rows_count
FROM d_rows AS d
LEFT JOIN overlaps AS o
  ON o.document_number = d.document_number
GROUP BY
    COALESCE(NULLIF(d.status, N''), N'<blank>'),
    CASE WHEN COALESCE(o.overlapping_active_full_count, 0) > 0 THEN 1 ELSE 0 END
ORDER BY rows_count DESC;

PRINT '09 scale: first 30 active no-payment full overlaps';

WITH d_rows AS (
    SELECT
        f.document_number,
        f.client_id,
        f.effective_client_fio,
        f.subscription_name,
        f.sale_datetime,
        f.start_date,
        f.end_date,
        f.status,
        f.rg_price,
        f.rg_paid_candidate
    FROM fitbase_part2.membership_import_facts AS f
    WHERE f.rg_price > 0
      AND f.matched_payment_ref IS NULL
      AND f.is_full_subscription = 1
      AND f.start_date <= CAST(@cutoff_at AS date)
      AND f.end_date >= CAST(@cutoff_at AS date)
),
overlap_examples AS (
    SELECT
        d.document_number,
        d.client_id,
        d.effective_client_fio,
        d.subscription_name,
        d.sale_datetime,
        d.start_date,
        d.end_date,
        d.status,
        d.rg_price,
        other_f.document_number AS other_document_number,
        other_f.subscription_name AS other_subscription_name,
        other_f.start_date AS other_start_date,
        other_f.end_date AS other_end_date,
        other_f.status AS other_status,
        other_f.matched_payment_amount AS other_payment_amount,
        other_f.matched_payment_method AS other_payment_method,
        ROW_NUMBER() OVER (
            PARTITION BY d.document_number
            ORDER BY other_f.end_date DESC, other_f.document_number
        ) AS rn
    FROM d_rows AS d
    JOIN fitbase_part2.membership_import_facts AS other_f
      ON other_f.client_id = d.client_id
     AND other_f.document_number <> d.document_number
     AND other_f.is_full_subscription = 1
     AND other_f.start_date <= CAST(@cutoff_at AS date)
     AND other_f.end_date >= CAST(@cutoff_at AS date)
)
SELECT TOP (30)
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    status,
    rg_price,
    other_document_number,
    other_subscription_name,
    other_start_date,
    other_end_date,
    other_status,
    other_payment_amount,
    other_payment_method
FROM overlap_examples
WHERE rn = 1
ORDER BY sale_datetime DESC, document_number;
