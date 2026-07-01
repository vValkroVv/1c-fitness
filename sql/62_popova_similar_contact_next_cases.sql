SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_date date = CAST(@cutoff_at AS date);

IF OBJECT_ID('tempdb..#visit_counts') IS NOT NULL DROP TABLE #visit_counts;
IF OBJECT_ID('tempdb..#fulls') IS NOT NULL DROP TABLE #fulls;
IF OBJECT_ID('tempdb..#next_full_pairs') IS NOT NULL DROP TABLE #next_full_pairs;

SELECT
    CONVERT(varchar(32), m._IDRRef, 2) AS subscription_ref,
    COUNT_BIG(*) AS visit_docs,
    MIN(CASE
            WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time)
            ELSE v._Date_Time
        END) AS first_visit,
    MAX(CASE
            WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time)
            ELSE v._Date_Time
        END) AS last_visit
INTO #visit_counts
FROM dbo._Document150 AS v
JOIN dbo._Document163 AS m
  ON v._Fld991_RTRef = 0x000000A3
 AND m._IDRRef = v._Fld991_RRRef
WHERE v._Posted = 0x01
  AND v._Marked = 0x00
GROUP BY CONVERT(varchar(32), m._IDRRef, 2);

SELECT
    f.client_id,
    f.effective_client_fio AS client_fio,
    f.document_number,
    f.subscription_ref,
    f.subscription_name,
    f.sale_datetime,
    CAST(f.start_date AS date) AS start_date,
    CAST(f.end_date AS date) AS end_date,
    COALESCE(NULLIF(LTRIM(RTRIM(f.status)), N''), N'<blank>') AS status_name,
    f.is_active_on_cutoff,
    f.rg_price,
    f.rg_paid_candidate,
    f.matched_payment_ref,
    f.matched_payment_datetime,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.matched_payment_match_source,
    CASE
        WHEN f.matched_payment_ref IS NOT NULL
          OR COALESCE(f.matched_payment_amount, 0) > 0
        THEN 1 ELSE 0
    END AS has_matched_payment,
    COALESCE(v.visit_docs, 0) AS visit_docs,
    v.first_visit,
    v.last_visit
INTO #fulls
FROM fitbase_part2.membership_import_facts AS f
LEFT JOIN #visit_counts AS v
  ON v.subscription_ref = f.subscription_ref
WHERE f.is_full_subscription = 1
  AND f.sale_datetime <= @cutoff_at;

CREATE INDEX IX_fulls_client ON #fulls(client_id);
CREATE INDEX IX_fulls_doc ON #fulls(document_number);

PRINT '01 all full rows status distribution';

SELECT
    status_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS clients_count,
    SUM(CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_on_cutoff_rows,
    SUM(CASE WHEN has_matched_payment = 0 THEN 1 ELSE 0 END) AS no_payment_rows
FROM #fulls
GROUP BY status_name
ORDER BY rows_count DESC;

PRINT '02 all active full rows on cutoff status distribution';

SELECT
    status_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS clients_count,
    SUM(CASE WHEN has_matched_payment = 0 THEN 1 ELSE 0 END) AS no_payment_rows
FROM #fulls
WHERE is_active_on_cutoff = 1
GROUP BY status_name
ORDER BY rows_count DESC;

PRINT '03 next/later full rows for clients that already have another active full on cutoff';

SELECT
    next_f.status_name,
    COUNT_BIG(DISTINCT next_f.document_number) AS next_rows,
    COUNT_BIG(DISTINCT next_f.client_id) AS clients_count,
    SUM(CASE WHEN next_f.has_matched_payment = 0 THEN 1 ELSE 0 END) AS no_payment_pair_rows,
    SUM(CASE WHEN next_f.visit_docs = 0 THEN 1 ELSE 0 END) AS zero_visit_pair_rows
FROM #fulls AS current_f
JOIN #fulls AS next_f
  ON next_f.client_id = current_f.client_id
 AND next_f.document_number <> current_f.document_number
 AND next_f.sale_datetime >= current_f.sale_datetime
 AND next_f.start_date >= current_f.start_date
 AND next_f.end_date >= @cutoff_date
WHERE current_f.is_active_on_cutoff = 1
GROUP BY next_f.status_name
ORDER BY next_rows DESC;

PRINT '04 contact rows with another active full on cutoff';

WITH contact_rows AS (
    SELECT DISTINCT
        next_f.document_number,
        next_f.client_id,
        next_f.client_fio,
        next_f.subscription_name,
        next_f.sale_datetime,
        next_f.start_date,
        next_f.end_date,
        next_f.rg_price,
        next_f.rg_paid_candidate,
        next_f.has_matched_payment,
        next_f.matched_payment_amount,
        next_f.matched_payment_method,
        next_f.visit_docs,
        next_f.is_active_on_cutoff
    FROM #fulls AS current_f
    JOIN #fulls AS next_f
      ON next_f.client_id = current_f.client_id
     AND next_f.document_number <> current_f.document_number
     AND next_f.sale_datetime >= current_f.sale_datetime
     AND next_f.start_date >= current_f.start_date
     AND next_f.end_date >= @cutoff_date
    WHERE current_f.is_active_on_cutoff = 1
      AND next_f.status_name = N'Контакт с клиентом'
)
SELECT
    COUNT_BIG(*) AS contact_rows_with_current_active_full,
    COUNT(DISTINCT client_id) AS clients_count,
    SUM(CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS contact_rows_active_on_cutoff,
    SUM(CASE WHEN start_date > @cutoff_date THEN 1 ELSE 0 END) AS contact_rows_future_start,
    SUM(CASE WHEN has_matched_payment = 0 THEN 1 ELSE 0 END) AS contact_rows_no_payment,
    SUM(CASE WHEN has_matched_payment = 0 AND visit_docs = 0 THEN 1 ELSE 0 END) AS contact_rows_no_payment_no_visits
FROM contact_rows;

PRINT '05 contact rows where another full covers the contact start date';

WITH contact_rows AS (
    SELECT DISTINCT
        next_f.document_number,
        next_f.client_id,
        next_f.client_fio,
        next_f.subscription_name,
        next_f.sale_datetime,
        next_f.start_date,
        next_f.end_date,
        next_f.rg_price,
        next_f.rg_paid_candidate,
        next_f.has_matched_payment,
        next_f.matched_payment_amount,
        next_f.matched_payment_method,
        next_f.visit_docs,
        next_f.is_active_on_cutoff
    FROM #fulls AS existing_f
    JOIN #fulls AS next_f
      ON next_f.client_id = existing_f.client_id
     AND next_f.document_number <> existing_f.document_number
     AND next_f.sale_datetime >= existing_f.sale_datetime
     AND next_f.start_date >= existing_f.start_date
     AND existing_f.start_date <= next_f.start_date
     AND existing_f.end_date >= next_f.start_date
    WHERE next_f.status_name = N'Контакт с клиентом'
      AND next_f.end_date >= @cutoff_date
)
SELECT
    COUNT_BIG(*) AS contact_rows_with_existing_full_on_contact_start,
    COUNT(DISTINCT client_id) AS clients_count,
    SUM(CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS contact_rows_active_on_cutoff,
    SUM(CASE WHEN start_date > @cutoff_date THEN 1 ELSE 0 END) AS contact_rows_future_start,
    SUM(CASE WHEN has_matched_payment = 0 THEN 1 ELSE 0 END) AS contact_rows_no_payment,
    SUM(CASE WHEN has_matched_payment = 0 AND visit_docs = 0 THEN 1 ELSE 0 END) AS contact_rows_no_payment_no_visits
FROM contact_rows;

PRINT '06 contact rows with existing full on start date: examples';

WITH paired AS (
    SELECT
        next_f.document_number,
        next_f.client_id,
        next_f.client_fio,
        next_f.subscription_name,
        next_f.sale_datetime,
        next_f.start_date,
        next_f.end_date,
        next_f.rg_price,
        next_f.rg_paid_candidate,
        next_f.has_matched_payment,
        next_f.matched_payment_amount,
        next_f.matched_payment_method,
        next_f.visit_docs,
        existing_f.document_number AS existing_document_number,
        existing_f.subscription_name AS existing_subscription_name,
        existing_f.start_date AS existing_start_date,
        existing_f.end_date AS existing_end_date,
        existing_f.status_name AS existing_status,
        existing_f.has_matched_payment AS existing_has_payment,
        existing_f.matched_payment_amount AS existing_payment_amount,
        existing_f.matched_payment_method AS existing_payment_method,
        existing_f.visit_docs AS existing_visit_docs,
        ROW_NUMBER() OVER (
            PARTITION BY next_f.document_number
            ORDER BY
                CASE WHEN existing_f.has_matched_payment = 1 THEN 0 ELSE 1 END,
                existing_f.visit_docs DESC,
                existing_f.end_date DESC,
                existing_f.document_number
        ) AS rn
    FROM #fulls AS existing_f
    JOIN #fulls AS next_f
      ON next_f.client_id = existing_f.client_id
     AND next_f.document_number <> existing_f.document_number
     AND next_f.sale_datetime >= existing_f.sale_datetime
     AND next_f.start_date >= existing_f.start_date
     AND existing_f.start_date <= next_f.start_date
     AND existing_f.end_date >= next_f.start_date
    WHERE next_f.status_name = N'Контакт с клиентом'
      AND next_f.end_date >= @cutoff_date
)
SELECT TOP (50)
    document_number,
    client_id,
    client_fio,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    rg_price,
    rg_paid_candidate,
    has_matched_payment,
    matched_payment_amount,
    matched_payment_method,
    visit_docs,
    existing_document_number,
    existing_subscription_name,
    existing_start_date,
    existing_end_date,
    existing_status,
    existing_has_payment,
    existing_payment_amount,
    existing_payment_method,
    existing_visit_docs
FROM paired
WHERE rn = 1
ORDER BY sale_datetime DESC, document_number;

PRINT '07 strongest Popova-like contact cases: no payment, no visits, existing full has payment or visits';

WITH paired AS (
    SELECT
        next_f.document_number,
        next_f.client_id,
        next_f.client_fio,
        next_f.subscription_name,
        next_f.sale_datetime,
        next_f.start_date,
        next_f.end_date,
        next_f.rg_price,
        next_f.rg_paid_candidate,
        next_f.has_matched_payment,
        next_f.visit_docs,
        next_f.is_active_on_cutoff,
        existing_f.document_number AS existing_document_number,
        existing_f.subscription_name AS existing_subscription_name,
        existing_f.start_date AS existing_start_date,
        existing_f.end_date AS existing_end_date,
        existing_f.status_name AS existing_status,
        existing_f.has_matched_payment AS existing_has_payment,
        existing_f.matched_payment_amount AS existing_payment_amount,
        existing_f.matched_payment_method AS existing_payment_method,
        existing_f.visit_docs AS existing_visit_docs,
        ROW_NUMBER() OVER (
            PARTITION BY next_f.document_number
            ORDER BY
                CASE WHEN existing_f.has_matched_payment = 1 THEN 0 ELSE 1 END,
                existing_f.visit_docs DESC,
                existing_f.end_date DESC,
                existing_f.document_number
        ) AS rn
    FROM #fulls AS existing_f
    JOIN #fulls AS next_f
      ON next_f.client_id = existing_f.client_id
     AND next_f.document_number <> existing_f.document_number
     AND next_f.sale_datetime >= existing_f.sale_datetime
     AND next_f.start_date >= existing_f.start_date
     AND existing_f.start_date <= next_f.start_date
     AND existing_f.end_date >= next_f.start_date
    WHERE next_f.status_name = N'Контакт с клиентом'
      AND next_f.end_date >= @cutoff_date
      AND next_f.has_matched_payment = 0
      AND next_f.visit_docs = 0
      AND (existing_f.has_matched_payment = 1 OR existing_f.visit_docs > 0)
)
SELECT
    COUNT_BIG(*) AS strongest_rows,
    COUNT(DISTINCT client_id) AS clients_count,
    SUM(CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_on_cutoff_rows
FROM paired
WHERE rn = 1;

PRINT '08 strongest examples';

WITH paired AS (
    SELECT
        next_f.document_number,
        next_f.client_id,
        next_f.client_fio,
        next_f.subscription_name,
        next_f.sale_datetime,
        next_f.start_date,
        next_f.end_date,
        next_f.rg_price,
        next_f.rg_paid_candidate,
        next_f.has_matched_payment,
        next_f.visit_docs,
        next_f.is_active_on_cutoff,
        existing_f.document_number AS existing_document_number,
        existing_f.subscription_name AS existing_subscription_name,
        existing_f.start_date AS existing_start_date,
        existing_f.end_date AS existing_end_date,
        existing_f.status_name AS existing_status,
        existing_f.has_matched_payment AS existing_has_payment,
        existing_f.matched_payment_amount AS existing_payment_amount,
        existing_f.matched_payment_method AS existing_payment_method,
        existing_f.visit_docs AS existing_visit_docs,
        ROW_NUMBER() OVER (
            PARTITION BY next_f.document_number
            ORDER BY
                CASE WHEN existing_f.has_matched_payment = 1 THEN 0 ELSE 1 END,
                existing_f.visit_docs DESC,
                existing_f.end_date DESC,
                existing_f.document_number
        ) AS rn
    FROM #fulls AS existing_f
    JOIN #fulls AS next_f
      ON next_f.client_id = existing_f.client_id
     AND next_f.document_number <> existing_f.document_number
     AND next_f.sale_datetime >= existing_f.sale_datetime
     AND next_f.start_date >= existing_f.start_date
     AND existing_f.start_date <= next_f.start_date
     AND existing_f.end_date >= next_f.start_date
    WHERE next_f.status_name = N'Контакт с клиентом'
      AND next_f.end_date >= @cutoff_date
      AND next_f.has_matched_payment = 0
      AND next_f.visit_docs = 0
      AND (existing_f.has_matched_payment = 1 OR existing_f.visit_docs > 0)
)
SELECT TOP (50)
    document_number,
    client_id,
    client_fio,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    rg_price,
    rg_paid_candidate,
    is_active_on_cutoff,
    existing_document_number,
    existing_subscription_name,
    existing_start_date,
    existing_end_date,
    existing_status,
    existing_has_payment,
    existing_payment_amount,
    existing_payment_method,
    existing_visit_docs
FROM paired
WHERE rn = 1
ORDER BY sale_datetime DESC, document_number;
