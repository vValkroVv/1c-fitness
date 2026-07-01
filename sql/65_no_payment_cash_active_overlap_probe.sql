SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_date date = '2026-05-25';

IF OBJECT_ID('tempdb..#targets') IS NOT NULL DROP TABLE #targets;
IF OBJECT_ID('tempdb..#visit_counts') IS NOT NULL DROP TABLE #visit_counts;
IF OBJECT_ID('tempdb..#fulls') IS NOT NULL DROP TABLE #fulls;
IF OBJECT_ID('tempdb..#target_fulls') IS NOT NULL DROP TABLE #target_fulls;
IF OBJECT_ID('tempdb..#near_payment_details') IS NOT NULL DROP TABLE #near_payment_details;
IF OBJECT_ID('tempdb..#near_payments') IS NOT NULL DROP TABLE #near_payments;
IF OBJECT_ID('tempdb..#sale_lines') IS NOT NULL DROP TABLE #sale_lines;
IF OBJECT_ID('tempdb..#best_other') IS NOT NULL DROP TABLE #best_other;

CREATE TABLE #targets (
    contract_id nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
);

INSERT INTO #targets(contract_id)
VALUES
    (N'00000149776'),
    (N'00000149604'),
    (N'00000140968'),
    (N'00000150179'),
    (N'00000150454'),
    (N'00000150455'),
    (N'00000149796'),
    (N'00000149798'),
    (N'00000150481'),
    (N'00000150482'),
    (N'00000149797'),
    (N'00000150540'),
    (N'00000150459'),
    (N'00000150563'),
    (N'00000150564'),
    (N'00000150571'),
    (N'00000150267'),
    (N'00000143904'),
    (N'00000141247'),
    (N'00000136145'),
    (N'00000140044'),
    (N'00000150584'),
    (N'00000143662'),
    (N'00000144853'),
    (N'00000149570'),
    (N'00000134419'),
    (N'00000145106'),
    (N'00000145690'),
    (N'00000133975'),
    (N'00000135279'),
    (N'00000146707'),
    (N'00000146848'),
    (N'00000148185'),
    (N'00000137483'),
    (N'00000142474'),
    (N'00000139729'),
    (N'00000134451'),
    (N'00000141880'),
    (N'00000135990'),
    (N'00000142688'),
    (N'00000142922'),
    (N'00000135799'),
    (N'00000138232'),
    (N'00000142446'),
    (N'00000147104'),
    (N'00000138089'),
    (N'00000138382'),
    (N'00000135095'),
    (N'00000149228'),
    (N'00000143556'),
    (N'00000147462'),
    (N'00000141562'),
    (N'00000143227'),
    (N'00000149024'),
    (N'00000146315'),
    (N'00000146316'),
    (N'00000136315'),
    (N'00000149621'),
    (N'00000139630'),
    (N'00000139631'),
    (N'00000147096'),
    (N'00000148336'),
    (N'00000148487');

SELECT
    CONVERT(varchar(32), m._IDRRef, 2) AS subscription_ref,
    m._Number AS contract_id,
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
GROUP BY
    CONVERT(varchar(32), m._IDRRef, 2),
    m._Number;

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
    f.rg_payment_count_candidate,
    f.matched_payment_ref,
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
    v.last_visit,
    f.doc_posted,
    f.doc_marked,
    f.normalized_club
INTO #fulls
FROM fitbase_part2.membership_import_facts AS f
LEFT JOIN #visit_counts AS v
  ON v.subscription_ref = f.subscription_ref
WHERE f.is_full_subscription = 1;

CREATE INDEX IX_fulls_client ON #fulls(client_id);
CREATE INDEX IX_fulls_doc ON #fulls(document_number);

SELECT f.*
INTO #target_fulls
FROM #fulls AS f
JOIN #targets AS t
  ON t.contract_id = f.document_number;

CREATE INDEX IX_target_fulls_doc ON #target_fulls(document_number);
CREATE INDEX IX_target_fulls_client ON #target_fulls(client_id);

SELECT DISTINCT
    t.document_number,
    p._Number AS payment_number,
    CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS payment_datetime,
    p._Fld1080 AS payment_total,
    op._Description AS operation_name,
    pm._Description AS payment_method,
    cp1._Code AS client_1057_id,
    cp2._Code AS client_1058_id
INTO #near_payment_details
FROM #target_fulls AS t
JOIN dbo._Document152 AS p
  ON p._Posted = 0x01
 AND p._Marked = 0x00
LEFT JOIN dbo._Reference64 AS cp1
  ON p._Fld1057_RTRef = 0x00000040
 AND cp1._IDRRef = p._Fld1057_RRRef
LEFT JOIN dbo._Reference64 AS cp2
  ON cp2._IDRRef = p._Fld1058RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
WHERE (cp1._Code = t.client_id OR cp2._Code = t.client_id)
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END >= DATEADD(day, -14, t.sale_datetime)
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END < DATEADD(day, 15, t.sale_datetime);

SELECT
    document_number,
    COUNT_BIG(*) AS nearby_payment_docs_14d,
    SUM(payment_total) AS nearby_payment_total_14d,
    MIN(payment_datetime) AS first_nearby_payment,
    MAX(payment_datetime) AS last_nearby_payment,
    MAX(payment_method) AS sample_nearby_payment_method,
    MAX(operation_name) AS sample_nearby_operation
INTO #near_payments
FROM #near_payment_details
GROUP BY document_number;

SELECT
    t.document_number,
    COUNT_BIG(DISTINCT d154._IDRRef) AS linked_sale_docs,
    MIN(CASE
            WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time)
            ELSE d154._Date_Time
        END) AS first_linked_sale_datetime,
    MAX(CASE
            WHEN d154._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d154._Date_Time)
            ELSE d154._Date_Time
        END) AS last_linked_sale_datetime,
    SUM(COALESCE(vt._Fld1140, 0)) AS linked_sale_sum_fld1140,
    SUM(COALESCE(vt._Fld1154, 0)) AS linked_sale_sum_fld1154,
    SUM(COALESCE(vt._Fld1160, 0)) AS linked_sale_sum_fld1160
INTO #sale_lines
FROM #target_fulls AS t
JOIN dbo._Document163 AS m
  ON m._Number = t.document_number
LEFT JOIN dbo._Document154_VT1137 AS vt
  ON vt._Fld1148_RTRef = 0x000000A3
 AND vt._Fld1148_RRRef = m._IDRRef
LEFT JOIN dbo._Document154 AS d154
  ON d154._IDRRef = vt._Document154_IDRRef
GROUP BY t.document_number;

WITH pairs AS (
    SELECT
        t.document_number AS target_document_number,
        o.document_number AS other_document_number,
        o.subscription_name AS other_subscription_name,
        o.status_name AS other_status_name,
        o.start_date AS other_start_date,
        o.end_date AS other_end_date,
        o.rg_price AS other_rg_price,
        o.rg_paid_candidate AS other_rg_paid_candidate,
        o.has_matched_payment AS other_has_payment,
        o.matched_payment_amount AS other_payment_amount,
        o.matched_payment_method AS other_payment_method,
        o.visit_docs AS other_visit_docs,
        o.first_visit AS other_first_visit,
        o.last_visit AS other_last_visit,
        ROW_NUMBER() OVER (
            PARTITION BY t.document_number
            ORDER BY
                CASE WHEN o.has_matched_payment = 1 THEN 0 ELSE 1 END,
                o.visit_docs DESC,
                o.end_date DESC,
                o.start_date DESC,
                o.document_number
        ) AS rn
    FROM #target_fulls AS t
    JOIN #fulls AS o
      ON o.client_id = t.client_id
     AND o.document_number <> t.document_number
     AND o.end_date >= @cutoff_date
     AND o.document_number NOT IN (
        N'00000145048',
        N'00000142081',
        N'00000138047',
        N'00000137201'
     )
)
SELECT *
INTO #best_other
FROM pairs
WHERE rn = 1;

PRINT '01 summary by status/visits/nearby payments';

SELECT
    t.status_name,
    CASE WHEN t.visit_docs > 0 THEN 1 ELSE 0 END AS target_has_visits,
    CASE WHEN COALESCE(np.nearby_payment_docs_14d, 0) > 0 THEN 1 ELSE 0 END AS has_nearby_payment_14d,
    COUNT_BIG(*) AS rows_count
FROM #target_fulls AS t
LEFT JOIN #near_payments AS np
  ON np.document_number = t.document_number
GROUP BY
    t.status_name,
    CASE WHEN t.visit_docs > 0 THEN 1 ELSE 0 END,
    CASE WHEN COALESCE(np.nearby_payment_docs_14d, 0) > 0 THEN 1 ELSE 0 END
ORDER BY rows_count DESC;

PRINT '02 target details';

SELECT
    t.document_number,
    t.client_id,
    t.client_fio,
    t.subscription_name,
    t.status_name,
    t.sale_datetime,
    t.start_date,
    t.end_date,
    t.rg_price,
    t.rg_paid_candidate,
    t.rg_payment_count_candidate,
    t.matched_payment_ref,
    t.visit_docs,
    t.first_visit,
    t.last_visit,
    COALESCE(np.nearby_payment_docs_14d, 0) AS nearby_payment_docs_14d,
    COALESCE(np.nearby_payment_total_14d, 0) AS nearby_payment_total_14d,
    np.first_nearby_payment,
    np.last_nearby_payment,
    np.sample_nearby_payment_method,
    np.sample_nearby_operation,
    COALESCE(sl.linked_sale_docs, 0) AS linked_sale_docs,
    sl.linked_sale_sum_fld1140,
    sl.linked_sale_sum_fld1154,
    sl.linked_sale_sum_fld1160,
    bo.other_document_number,
    bo.other_subscription_name,
    bo.other_status_name,
    bo.other_start_date,
    bo.other_end_date,
    bo.other_has_payment,
    bo.other_payment_amount,
    bo.other_payment_method,
    bo.other_visit_docs,
    bo.other_first_visit,
    bo.other_last_visit,
    t.doc_posted,
    t.doc_marked,
    t.normalized_club
FROM #target_fulls AS t
LEFT JOIN #near_payments AS np
  ON np.document_number = t.document_number
LEFT JOIN #sale_lines AS sl
  ON sl.document_number = t.document_number
LEFT JOIN #best_other AS bo
  ON bo.target_document_number = t.document_number
ORDER BY
    t.status_name,
    t.client_id,
    t.document_number;

PRINT '03 nearby payment details';

SELECT
    document_number,
    payment_number,
    payment_ref,
    payment_datetime,
    payment_total,
    operation_name,
    payment_method,
    client_1057_id,
    client_1058_id
FROM #near_payment_details
ORDER BY
    document_number,
    payment_datetime,
    payment_number;
