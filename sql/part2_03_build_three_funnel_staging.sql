USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_date date = '$(cutoff_date)';
DECLARE @cutoff_sql_date date = DATEADD(year, 2000, @cutoff_date);
DECLARE @backup_finish_at datetime2 = '$(backup_finish_at)';
DECLARE @backup_finish_sql_at datetime2 = DATEADD(year, 2000, @backup_finish_at);
DECLARE @output_run_label nvarchar(100) = N'$(output_run_label)';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'fitbase_part2')
    EXEC(N'CREATE SCHEMA fitbase_part2');

DROP TABLE IF EXISTS fitbase_part2.final_funnel_clients;
DROP TABLE IF EXISTS fitbase_part2.selected_cards;
DROP TABLE IF EXISTS fitbase_part2.selected_subscriptions;
DROP TABLE IF EXISTS fitbase_part2.subscription_candidates_ranked;
DROP TABLE IF EXISTS fitbase_part2.client_history_summary;
DROP TABLE IF EXISTS fitbase_part2.stg_plastic_cards;
DROP TABLE IF EXISTS fitbase_part2.stg_sales_all;
DROP TABLE IF EXISTS fitbase_part2.stg_subscriptions_all;
DROP TABLE IF EXISTS fitbase_part2.stg_products;
DROP TABLE IF EXISTS fitbase_part2.stg_client_contacts;
DROP TABLE IF EXISTS fitbase_part2.stg_clients;
DROP TABLE IF EXISTS fitbase_part2.staging_run_metadata;

DROP TABLE IF EXISTS #document163_docs;
DROP TABLE IF EXISTS #subscription_raw;
GO

DECLARE @cutoff_date date = '$(cutoff_date)';
DECLARE @cutoff_sql_date date = DATEADD(year, 2000, @cutoff_date);
DECLARE @backup_finish_at datetime2 = '$(backup_finish_at)';
DECLARE @backup_finish_sql_at datetime2 = DATEADD(year, 2000, @backup_finish_at);
DECLARE @output_run_label nvarchar(100) = N'$(output_run_label)';

CREATE TABLE fitbase_part2.staging_run_metadata (
    cutoff_date date NOT NULL,
    backup_finish_at datetime2 NOT NULL,
    cutoff_sql_date date NOT NULL,
    backup_finish_sql_at datetime2 NOT NULL,
    output_run_label nvarchar(100) NOT NULL,
    built_at datetime2 NOT NULL,
    source_database sysname NOT NULL
);

INSERT INTO fitbase_part2.staging_run_metadata (
    cutoff_date,
    backup_finish_at,
    cutoff_sql_date,
    backup_finish_sql_at,
    output_run_label,
    built_at,
    source_database
)
VALUES (
    @cutoff_date,
    @backup_finish_at,
    @cutoff_sql_date,
    @backup_finish_sql_at,
    @output_run_label,
    SYSDATETIME(),
    DB_NAME()
);

CREATE TABLE fitbase_part2.stg_clients (
    client_ref varchar(32) NOT NULL,
    client_id nvarchar(50) NULL,
    client_fio nvarchar(250) NULL,
    client_created_at date NULL,
    client_marked int NOT NULL,
    raw_client_club nvarchar(250) NULL,
    client_normalized_club nvarchar(100) NULL,
    client_club_source nvarchar(200) NULL,
    raw_source_table nvarchar(100) NOT NULL
);

INSERT INTO fitbase_part2.stg_clients (
    client_ref,
    client_id,
    client_fio,
    client_created_at,
    client_marked,
    raw_client_club,
    client_normalized_club,
    client_club_source,
    raw_source_table
)
SELECT
    CONVERT(varchar(32), c._IDRRef, 2) AS client_ref,
    c._Code AS client_id,
    c._Description AS client_fio,
    CASE
        WHEN c._Fld3822 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, c._Fld3822))
        WHEN c._Fld3822 > '1900-01-01' THEN CONVERT(date, c._Fld3822)
        ELSE NULL
    END AS client_created_at,
    CASE WHEN c._Marked = 0x00 THEN 0 ELSE 1 END AS client_marked,
    org._Description AS raw_client_club,
    CASE
        WHEN org._Description LIKE N'%Гоголев%' THEN N'Коммунальная, 20'
        WHEN org._Description LIKE N'%Столиц%' THEN N'Лососинское шоссе, 26'
        WHEN org._Description LIKE N'%Карель%' THEN N'Карельский (закрыт)'
        WHEN org._Description LIKE N'%Промышлен%' THEN N'Промышленная, 10'
        WHEN org._Description LIKE N'%Ровио%' THEN N'Ровио, 3'
        WHEN org._Description LIKE N'%Коммуналь%' THEN N'Коммунальная, 20'
        WHEN org._Description LIKE N'%Лососин%' THEN N'Лососинское шоссе, 26'
        ELSE NULL
    END AS client_normalized_club,
    CASE
        WHEN org._Description IS NOT NULL THEN N'dbo._Reference64._Fld3831RRef -> dbo._Reference105'
        ELSE NULL
    END AS client_club_source,
    N'dbo._Reference64' AS raw_source_table
FROM dbo._Reference64 AS c
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = c._Fld3831RRef;

CREATE INDEX IX_part2_stg_clients_client_ref ON fitbase_part2.stg_clients(client_ref);

SELECT
    CONVERT(varchar(32), c._IDRRef, 2) AS client_ref,
    N'phone' AS contact_type,
    c._Fld3832 AS raw_value,
    c._Fld3832 AS normalized_value,
    N'dbo._Reference64._Fld3832' AS raw_source
INTO fitbase_part2.stg_client_contacts
FROM dbo._Reference64 AS c
WHERE NULLIF(LTRIM(RTRIM(c._Fld3832)), N'') IS NOT NULL

UNION ALL

SELECT DISTINCT
    CONVERT(varchar(32), e._Fld5256RRef, 2) AS client_ref,
    N'email' AS contact_type,
    LOWER(LTRIM(RTRIM(e._Fld5257))) AS raw_value,
    LOWER(LTRIM(RTRIM(e._Fld5257))) AS normalized_value,
    N'dbo._InfoRg5255._Fld5257' AS raw_source
FROM dbo._InfoRg5255 AS e
JOIN dbo._Reference64 AS c
  ON c._IDRRef = e._Fld5256RRef
WHERE e._Fld5257 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%';

CREATE INDEX IX_part2_stg_client_contacts_client_ref ON fitbase_part2.stg_client_contacts(client_ref);

SELECT
    d._IDRRef AS sale_ref_bin,
    CASE
        WHEN holder._IDRRef IS NOT NULL THEN d._Fld9152RRef
        WHEN d._Fld1447_RTRef = 0x00000040 THEN d._Fld1447_RRRef
        ELSE NULL
    END AS client_ref_bin,
    d._Fld9152RRef AS holder_client_ref_bin,
    CASE WHEN d._Fld1447_RTRef = 0x00000040 THEN d._Fld1447_RRRef END AS payer_client_ref_bin,
    CASE
        WHEN holder._IDRRef IS NOT NULL THEN N'holder_9152'
        WHEN d._Fld1447_RTRef = 0x00000040 THEN N'payer_1447_fallback'
        ELSE N'unknown'
    END AS client_role_source,
    d._Fld1446RRef AS product_ref_bin,
    p._Code AS product_code,
    p._Description AS product_name,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, d._Date_Time))
        ELSE CONVERT(date, d._Date_Time)
    END AS sale_date,
    d._Posted AS doc_posted,
    d._Marked AS doc_marked,
    CASE WHEN d._Posted = 0x01 THEN 1 ELSE 0 END AS is_posted,
    CASE WHEN d._Marked = 0x00 THEN 0 ELSE 1 END AS is_marked,
    org._Description AS direct_org_name,
    CASE
        WHEN org._Description LIKE N'%Гоголев%' THEN N'Коммунальная, 20'
        WHEN org._Description LIKE N'%Столиц%' THEN N'Лососинское шоссе, 26'
        WHEN org._Description LIKE N'%Карель%' THEN N'Карельский (закрыт)'
        WHEN org._Description LIKE N'%Промышлен%' THEN N'Промышленная, 10'
        WHEN org._Description LIKE N'%Ровио%' THEN N'Ровио, 3'
        WHEN org._Description LIKE N'%Коммуналь%' THEN N'Коммунальная, 20'
        WHEN org._Description LIKE N'%Лососин%' THEN N'Лососинское шоссе, 26'
        WHEN p._Description LIKE N'%Гоголев%' THEN N'Коммунальная, 20'
        WHEN p._Description LIKE N'%Столиц%' THEN N'Лососинское шоссе, 26'
        WHEN p._Description LIKE N'%Карель%' THEN N'Карельский (закрыт)'
        WHEN p._Description LIKE N'%Промышлен%' THEN N'Промышленная, 10'
        WHEN p._Description LIKE N'%Ровио%' THEN N'Ровио, 3'
        WHEN p._Description LIKE N'%Коммуналь%' THEN N'Коммунальная, 20'
        WHEN p._Description LIKE N'%Лососин%' THEN N'Лососинское шоссе, 26'
        ELSE NULL
    END AS normalized_club,
    CASE
        WHEN org._Description LIKE N'%Гоголев%'
          OR org._Description LIKE N'%Столиц%'
          OR org._Description LIKE N'%Карель%'
          OR org._Description LIKE N'%Промышлен%'
          OR org._Description LIKE N'%Ровио%'
          OR org._Description LIKE N'%Коммуналь%'
          OR org._Description LIKE N'%Лососин%' THEN N'dbo._Document163._Fld1443RRef -> dbo._Reference105'
        WHEN p._Description LIKE N'%Гоголев%'
          OR p._Description LIKE N'%Столиц%'
          OR p._Description LIKE N'%Карель%'
          OR p._Description LIKE N'%Промышлен%'
          OR p._Description LIKE N'%Ровио%'
          OR p._Description LIKE N'%Коммуналь%'
          OR p._Description LIKE N'%Лососин%' THEN N'dbo._Reference72._Description'
        ELSE NULL
    END AS club_source
INTO #document163_docs
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference64 AS holder
  ON holder._IDRRef = d._Fld9152RRef
LEFT JOIN dbo._Reference72 AS p
  ON p._IDRRef = d._Fld1446RRef
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = d._Fld1443RRef
WHERE d._Date_Time <= @backup_finish_sql_at;

CREATE INDEX IX_doc163_docs_sale_ref ON #document163_docs(sale_ref_bin);
CREATE INDEX IX_doc163_docs_client_ref ON #document163_docs(client_ref_bin);
CREATE INDEX IX_doc163_docs_product_ref ON #document163_docs(product_ref_bin);

SELECT
    d.client_ref_bin,
    d.sale_ref_bin AS subscription_ref_bin,
    d.holder_client_ref_bin,
    d.payer_client_ref_bin,
    d.client_role_source,
    d.product_ref_bin,
    d.product_code,
    d.product_name AS subscription_name,
    d.sale_date,
    CASE
        WHEN r._Fld3063 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3063))
        ELSE CONVERT(date, r._Fld3063)
    END AS start_date,
    CASE
        WHEN r._Fld3064 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3064))
        ELSE CONVERT(date, r._Fld3064)
    END AS end_date,
    st._Description AS status,
    d.doc_posted,
    d.doc_marked,
    d.is_posted,
    d.is_marked,
    r._Fld3065 AS register_duration_days,
    r._Fld5960RRef AS booking_status_ref_bin,
    book_st._Description AS booking_status_name,
    d.direct_org_name AS raw_club,
    d.normalized_club,
    d.club_source
INTO #subscription_raw
FROM dbo._InfoRg3060 AS r
JOIN #document163_docs AS d
  ON d.sale_ref_bin = r._Fld3061RRef
LEFT JOIN dbo._Reference5062 AS st
  ON st._IDRRef = r._Fld5960RRef
LEFT JOIN dbo._Reference5062 AS book_st
  ON book_st._IDRRef = r._Fld5960RRef
WHERE d.is_posted = 1
  AND d.is_marked = 0
  AND d.product_name IS NOT NULL
  AND d.client_ref_bin IS NOT NULL;

CREATE INDEX IX_subscription_raw_client_ref ON #subscription_raw(client_ref_bin);
CREATE INDEX IX_subscription_raw_product_ref ON #subscription_raw(product_ref_bin);

WITH document_product_stats AS (
    SELECT
        CONVERT(varchar(32), product_ref_bin, 2) AS product_ref,
        COUNT(DISTINCT CONVERT(varchar(32), client_ref_bin, 2)) AS observed_clients,
        COUNT(DISTINCT CONVERT(varchar(32), sale_ref_bin, 2)) AS observed_sale_rows
    FROM #document163_docs
    WHERE is_posted = 1
      AND is_marked = 0
      AND product_ref_bin IS NOT NULL
    GROUP BY CONVERT(varchar(32), product_ref_bin, 2)
),
subscription_product_stats AS (
    SELECT
        CONVERT(varchar(32), product_ref_bin, 2) AS product_ref,
        COUNT(*) AS observed_subscription_rows,
        MIN(DATEDIFF(day, start_date, end_date) + 1) AS min_duration_days,
        MAX(DATEDIFF(day, start_date, end_date) + 1) AS max_duration_days,
        AVG(CAST(DATEDIFF(day, start_date, end_date) + 1 AS decimal(15, 2))) AS avg_duration_days
    FROM #subscription_raw
    WHERE product_ref_bin IS NOT NULL
    GROUP BY CONVERT(varchar(32), product_ref_bin, 2)
),
product_base AS (
    SELECT
        CONVERT(varchar(32), p._IDRRef, 2) AS product_ref,
        p._Code AS product_code,
        p._Description AS product_name,
        LOWER(LTRIM(RTRIM(COALESCE(p._Description, N'')))) AS product_name_norm,
        COALESCE(dps.observed_clients, 0) AS observed_clients,
        COALESCE(dps.observed_sale_rows, 0) AS observed_sale_rows,
        COALESCE(sps.observed_subscription_rows, 0) AS observed_subscription_rows,
        sps.min_duration_days,
        sps.max_duration_days,
        sps.avg_duration_days
    FROM dbo._Reference72 AS p
    LEFT JOIN document_product_stats AS dps
      ON dps.product_ref = CONVERT(varchar(32), p._IDRRef, 2)
    LEFT JOIN subscription_product_stats AS sps
      ON sps.product_ref = CONVERT(varchar(32), p._IDRRef, 2)
),
product_flags AS (
    SELECT
        *,
        CASE
            WHEN product_name_norm LIKE N'%абонемент%'
              OR product_name_norm LIKE N'%мульти%'
              OR product_name_norm LIKE N'%ультра%'
              OR product_name_norm LIKE N'%членств%' THEN 1
            ELSE 0
        END AS has_full_keyword,
        CASE
            WHEN product_name_norm LIKE N'%гост%'
              OR product_name_norm LIKE N'%проб%'
              OR product_name_norm LIKE N'%тест%'
              OR product_name_norm LIKE N'%разов%'
              OR product_name_norm LIKE N'%1 день%'
              OR product_name_norm LIKE N'%один день%'
              OR product_name_norm LIKE N'%7 дней%'
              OR product_name_norm LIKE N'%недел%' THEN 1
            ELSE 0
        END AS has_trial_keyword,
        CASE
            WHEN product_name_norm LIKE N'%переоформ%'
              OR product_name_norm LIKE N'%перенос%' THEN 1
            ELSE 0
        END AS has_full_exclude_keyword
    FROM product_base
)
SELECT
    product_ref,
    product_code,
    product_name,
    product_name_norm,
    observed_clients,
    observed_sale_rows,
    observed_subscription_rows,
    min_duration_days,
    max_duration_days,
    avg_duration_days,
    CASE
        WHEN has_full_keyword = 1
         AND COALESCE(max_duration_days, 0) >= 30
         AND has_trial_keyword = 0
         AND has_full_exclude_keyword = 0 THEN 1
        ELSE 0
    END AS is_full_subscription_candidate,
    CASE
        WHEN has_trial_keyword = 1
          OR (COALESCE(max_duration_days, 0) BETWEEN 1 AND 14) THEN 1
        ELSE 0
    END AS is_trial_or_guest_candidate,
    CASE
        WHEN has_full_keyword = 1
         AND COALESCE(max_duration_days, 0) >= 30
         AND has_trial_keyword = 0
         AND has_full_exclude_keyword = 0 THEN N'full_subscription'
        WHEN has_trial_keyword = 1
          OR (COALESCE(max_duration_days, 0) BETWEEN 1 AND 14) THEN N'trial_or_guest'
        WHEN observed_subscription_rows > 0 THEN N'unknown_review_required'
        ELSE N'other_sale'
    END AS product_class,
    CASE
        WHEN has_full_keyword = 1
         AND COALESCE(max_duration_days, 0) >= 30
         AND has_trial_keyword = 0
         AND has_full_exclude_keyword = 0 THEN N'full keyword + duration >= 30 + no trial/exclude keyword'
        WHEN has_trial_keyword = 1 THEN N'trial/guest/short keyword'
        WHEN COALESCE(max_duration_days, 0) BETWEEN 1 AND 14 THEN N'short observed duration <= 14 days'
        WHEN observed_subscription_rows > 0 THEN N'observed in subscription register but no automatic rule matched'
        ELSE N'not observed as subscription product'
    END AS classification_reason,
    CASE
        WHEN observed_subscription_rows > 0
         AND NOT (
            has_full_keyword = 1
            AND COALESCE(max_duration_days, 0) >= 30
            AND has_trial_keyword = 0
            AND has_full_exclude_keyword = 0
         )
         AND NOT (
            has_trial_keyword = 1
            OR (COALESCE(max_duration_days, 0) BETWEEN 1 AND 14)
         ) THEN 1
        WHEN product_name_norm LIKE N'%замороз%' THEN 1
        ELSE 0
    END AS needs_manual_review
INTO fitbase_part2.stg_products
FROM product_flags;

CREATE INDEX IX_part2_stg_products_ref ON fitbase_part2.stg_products(product_ref);

SELECT
    CONVERT(varchar(32), sr.client_ref_bin, 2) AS client_ref,
    c.client_id,
    CONVERT(varchar(32), sr.subscription_ref_bin, 2) AS subscription_ref,
    CONVERT(varchar(32), sr.holder_client_ref_bin, 2) AS holder_client_ref,
    CONVERT(varchar(32), sr.payer_client_ref_bin, 2) AS payer_client_ref,
    sr.client_role_source,
    CONVERT(varchar(32), sr.product_ref_bin, 2) AS product_ref,
    sr.product_code,
    sr.subscription_name,
    sp.product_class,
    CASE WHEN sp.product_class = N'full_subscription' THEN 1 ELSE 0 END AS is_full_subscription,
    CASE WHEN sp.product_class = N'trial_or_guest' THEN 1 ELSE 0 END AS is_trial_or_guest,
    sr.sale_date,
    sr.start_date,
    sr.end_date,
    DATEDIFF(day, sr.start_date, sr.end_date) + 1 AS duration_days,
    sr.status,
    CONVERT(varchar(32), sr.booking_status_ref_bin, 2) AS booking_status_ref,
    sr.booking_status_name,
    sr.doc_posted,
    sr.doc_marked,
    sr.register_duration_days,
    CASE
        WHEN sp.product_class = N'full_subscription'
         AND sr.sale_date <= @cutoff_date
         AND sr.end_date >= @cutoff_date THEN 1
        ELSE 0
    END AS is_active_on_cutoff,
    CASE
        WHEN sp.product_class = N'full_subscription'
         AND sr.sale_date <= @cutoff_date
         AND sr.end_date < @cutoff_date THEN 1
        ELSE 0
    END AS is_finished_before_cutoff,
    DATEDIFF(day, @cutoff_date, sr.end_date) AS days_to_end,
    DATEDIFF(day, sr.end_date, @cutoff_date) AS days_since_end,
    sr.raw_club,
    sr.normalized_club,
    sr.club_source,
    N'dbo._InfoRg3060 + dbo._Document163' AS raw_source
INTO fitbase_part2.stg_subscriptions_all
FROM #subscription_raw AS sr
JOIN fitbase_part2.stg_clients AS c
  ON c.client_ref = CONVERT(varchar(32), sr.client_ref_bin, 2)
LEFT JOIN fitbase_part2.stg_products AS sp
  ON sp.product_ref = CONVERT(varchar(32), sr.product_ref_bin, 2);

CREATE INDEX IX_part2_stg_subscriptions_client_ref ON fitbase_part2.stg_subscriptions_all(client_ref);
CREATE INDEX IX_part2_stg_subscriptions_full_active ON fitbase_part2.stg_subscriptions_all(is_full_subscription, is_active_on_cutoff, client_ref);

WITH payment_sales AS (
    SELECT
        CASE
            WHEN d._Fld1057_RTRef = 0x00000040 AND c1057._IDRRef IS NOT NULL THEN d._Fld1057_RRRef
            WHEN c1058._IDRRef IS NOT NULL THEN d._Fld1058RRef
            ELSE NULL
        END AS client_ref_bin,
        d._IDRRef AS sale_ref_bin,
        CASE
            WHEN d._Date_Time > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, d._Date_Time))
            ELSE CONVERT(date, d._Date_Time)
        END AS sale_date,
        CAST(NULL AS binary(16)) AS product_ref_bin,
        CAST(NULL AS nvarchar(200)) AS product_name,
        N'other_sale' AS product_class,
        CAST(d._Fld1080 AS decimal(15, 2)) AS amount,
        op._Description AS operation_name,
        pm._Description AS payment_method,
        org._Description AS raw_club,
        CASE
            WHEN org._Description LIKE N'%Гоголев%' THEN N'Коммунальная, 20'
            WHEN org._Description LIKE N'%Столиц%' THEN N'Лососинское шоссе, 26'
            WHEN org._Description LIKE N'%Карель%' THEN N'Карельский (закрыт)'
            WHEN org._Description LIKE N'%Промышлен%' THEN N'Промышленная, 10'
            WHEN org._Description LIKE N'%Ровио%' THEN N'Ровио, 3'
            WHEN org._Description LIKE N'%Коммуналь%' THEN N'Коммунальная, 20'
            WHEN org._Description LIKE N'%Лососин%' THEN N'Лососинское шоссе, 26'
            ELSE NULL
        END AS normalized_club,
        CASE
            WHEN org._Description LIKE N'%Гоголев%'
              OR org._Description LIKE N'%Столиц%'
              OR org._Description LIKE N'%Карель%'
              OR org._Description LIKE N'%Промышлен%'
              OR org._Description LIKE N'%Ровио%'
              OR org._Description LIKE N'%Коммуналь%'
              OR org._Description LIKE N'%Лососин%' THEN N'dbo._Document152._Fld1051RRef -> dbo._Reference105'
            ELSE NULL
        END AS club_source,
        N'dbo._Document152' AS sale_source
    FROM dbo._Document152 AS d
    LEFT JOIN dbo._Reference64 AS c1057
      ON c1057._IDRRef = d._Fld1057_RRRef
     AND d._Fld1057_RTRef = 0x00000040
    LEFT JOIN dbo._Reference64 AS c1058
      ON c1058._IDRRef = d._Fld1058RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = d._Fld1072RRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = d._Fld1074RRef
    LEFT JOIN dbo._Reference105 AS org
      ON org._IDRRef = d._Fld1051RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND d._Date_Time <= @backup_finish_sql_at
),
product_sales AS (
    SELECT
        d.client_ref_bin,
        d.sale_ref_bin,
        d.sale_date,
        d.product_ref_bin,
        d.product_name,
        COALESCE(sp.product_class, N'other_sale') AS product_class,
        CAST(NULL AS decimal(15, 2)) AS amount,
        CAST(NULL AS nvarchar(200)) AS operation_name,
        CAST(NULL AS nvarchar(200)) AS payment_method,
        d.direct_org_name AS raw_club,
        d.normalized_club,
        d.club_source,
        N'dbo._Document163' AS sale_source
    FROM #document163_docs AS d
    LEFT JOIN fitbase_part2.stg_products AS sp
      ON sp.product_ref = CONVERT(varchar(32), d.product_ref_bin, 2)
    WHERE d.is_posted = 1
      AND d.is_marked = 0
      AND d.client_ref_bin IS NOT NULL
)
SELECT
    CONVERT(varchar(32), client_ref_bin, 2) AS client_ref,
    CONVERT(varchar(32), sale_ref_bin, 2) AS sale_ref,
    sale_date,
    CONVERT(varchar(32), product_ref_bin, 2) AS product_ref,
    product_name,
    product_class,
    amount,
    operation_name,
    payment_method,
    raw_club,
    normalized_club,
    club_source,
    sale_source
INTO fitbase_part2.stg_sales_all
FROM (
    SELECT * FROM payment_sales
    UNION ALL
    SELECT * FROM product_sales
) AS sales
WHERE client_ref_bin IS NOT NULL;

CREATE INDEX IX_part2_stg_sales_client_date ON fitbase_part2.stg_sales_all(client_ref, sale_date);

SELECT
    CONVERT(varchar(32), card._Fld3750_RRRef, 2) AS client_ref,
    CONVERT(varchar(32), card._IDRRef, 2) AS card_ref,
    NULLIF(LTRIM(RTRIM(COALESCE(NULLIF(card._Fld3753, N''), card._Fld3756))), N'') AS plastic_card_number,
    NULLIF(LTRIM(RTRIM(card._Fld3753)), N'') AS plastic_card_number_primary,
    NULLIF(LTRIM(RTRIM(card._Fld3756)), N'') AS plastic_card_number_secondary,
    CASE WHEN card._Marked = 0x00 THEN N'unmarked' ELSE N'marked' END AS card_status,
    CASE WHEN card._Marked = 0x00 THEN 1 ELSE 0 END AS is_unmarked,
    CASE
        WHEN card._Fld3751 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, card._Fld3751))
        WHEN card._Fld3751 > '1900-01-01' THEN CONVERT(date, card._Fld3751)
        ELSE NULL
    END AS issue_date,
    CASE
        WHEN card._Fld3751 > DATEADD(year, 2000, @cutoff_date) THEN 1
        WHEN card._Fld3751 > @cutoff_date AND card._Fld3751 < '3000-01-01' THEN 1
        ELSE 0
    END AS is_future_issue_date,
    N'dbo._Reference59' AS raw_source
INTO fitbase_part2.stg_plastic_cards
FROM dbo._Reference59 AS card
JOIN dbo._Reference64 AS c
  ON c._IDRRef = card._Fld3750_RRRef
WHERE card._Fld3750_RTRef = 0x00000040;

CREATE INDEX IX_part2_stg_plastic_cards_client_ref ON fitbase_part2.stg_plastic_cards(client_ref);

WITH phones AS (
    SELECT
        client_ref,
        STRING_AGG(CAST(raw_value AS nvarchar(max)), N', ') AS phones
    FROM (
        SELECT DISTINCT client_ref, raw_value
        FROM fitbase_part2.stg_client_contacts
        WHERE contact_type = N'phone'
          AND NULLIF(LTRIM(RTRIM(raw_value)), N'') IS NOT NULL
    ) AS x
    GROUP BY client_ref
),
emails AS (
    SELECT
        client_ref,
        STRING_AGG(CAST(raw_value AS nvarchar(max)), N', ') AS email
    FROM (
        SELECT DISTINCT client_ref, raw_value
        FROM fitbase_part2.stg_client_contacts
        WHERE contact_type = N'email'
          AND NULLIF(LTRIM(RTRIM(raw_value)), N'') IS NOT NULL
    ) AS x
    GROUP BY client_ref
),
sale_stats AS (
    SELECT
        client_ref,
        MIN(CASE WHEN sale_date <= @cutoff_date THEN sale_date END) AS first_sale_date,
        MIN(CASE WHEN sale_date <= @cutoff_date AND product_class = N'trial_or_guest' THEN sale_date END) AS first_trial_or_guest_product_date,
        MIN(CASE WHEN sale_date <= @cutoff_date AND product_class <> N'full_subscription' THEN sale_date END) AS first_non_full_sale_date,
        MAX(CASE WHEN sale_date <= @cutoff_date THEN sale_date END) AS last_sale_date,
        COUNT(CASE WHEN sale_date <= @cutoff_date THEN 1 END) AS sale_count,
        COUNT(CASE WHEN sale_date <= @cutoff_date AND product_class = N'trial_or_guest' THEN 1 END) AS trial_or_guest_sale_count
    FROM fitbase_part2.stg_sales_all
    GROUP BY client_ref
),
last_sale AS (
    SELECT *
    FROM (
        SELECT
            s.*,
            ROW_NUMBER() OVER (
                PARTITION BY s.client_ref
                ORDER BY s.sale_date DESC, s.sale_ref DESC
            ) AS rn
        FROM fitbase_part2.stg_sales_all AS s
        WHERE s.sale_date <= @cutoff_date
    ) AS ranked
    WHERE rn = 1
),
full_stats AS (
    SELECT
        client_ref,
        COUNT(CASE WHEN is_full_subscription = 1 AND sale_date <= @cutoff_date THEN 1 END) AS full_subscription_count,
        COUNT(CASE WHEN is_full_subscription = 1 AND is_active_on_cutoff = 1 THEN 1 END) AS active_full_subscription_count,
        COUNT(CASE WHEN is_full_subscription = 1 AND is_finished_before_cutoff = 1 THEN 1 END) AS finished_full_subscription_count,
        MAX(CASE WHEN is_full_subscription = 1 AND sale_date <= @cutoff_date THEN 1 ELSE 0 END) AS has_any_full_subscription,
        MAX(CASE WHEN is_full_subscription = 1 AND is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS has_active_full_subscription,
        MAX(CASE WHEN is_full_subscription = 1 AND is_finished_before_cutoff = 1 THEN 1 ELSE 0 END) AS has_finished_full_subscription
    FROM fitbase_part2.stg_subscriptions_all
    GROUP BY client_ref
)
SELECT
    c.client_ref,
    c.client_id,
    c.client_fio,
    p.phones,
    e.email,
    ss.first_sale_date,
    CASE
        WHEN ss.first_sale_date IS NOT NULL THEN N'first_sale'
        ELSE NULL
    END AS first_sale_source,
    c.client_created_at,
    CASE WHEN COALESCE(ss.sale_count, 0) > 0 THEN 1 ELSE 0 END AS has_any_sale,
    COALESCE(fs.has_any_full_subscription, 0) AS has_any_full_subscription,
    COALESCE(fs.has_active_full_subscription, 0) AS has_active_full_subscription,
    COALESCE(fs.has_finished_full_subscription, 0) AS has_finished_full_subscription,
    COALESCE(fs.full_subscription_count, 0) AS full_subscription_count,
    COALESCE(fs.active_full_subscription_count, 0) AS active_full_subscription_count,
    COALESCE(fs.finished_full_subscription_count, 0) AS finished_full_subscription_count,
    COALESCE(ss.trial_or_guest_sale_count, 0) AS trial_or_guest_sale_count,
    ss.first_trial_or_guest_product_date,
    ss.first_non_full_sale_date,
    ss.last_sale_date,
    ls.product_name AS last_sale_product_name,
    ls.normalized_club AS last_sale_club,
    ls.club_source AS last_sale_club_source,
    c.raw_client_club,
    c.client_normalized_club,
    c.client_club_source,
    c.client_marked
INTO fitbase_part2.client_history_summary
FROM fitbase_part2.stg_clients AS c
LEFT JOIN phones AS p
  ON p.client_ref = c.client_ref
LEFT JOIN emails AS e
  ON e.client_ref = c.client_ref
LEFT JOIN sale_stats AS ss
  ON ss.client_ref = c.client_ref
LEFT JOIN last_sale AS ls
  ON ls.client_ref = c.client_ref
LEFT JOIN full_stats AS fs
  ON fs.client_ref = c.client_ref;

CREATE INDEX IX_part2_client_history_client_ref ON fitbase_part2.client_history_summary(client_ref);

WITH candidates AS (
    SELECT
        s.*,
        CASE
            WHEN s.is_full_subscription = 1 AND s.is_active_on_cutoff = 1 THEN N'active'
            WHEN s.is_full_subscription = 1 AND s.is_finished_before_cutoff = 1 THEN N'reactivation'
            ELSE NULL
        END AS candidate_for_funnel
    FROM fitbase_part2.stg_subscriptions_all AS s
    WHERE s.is_full_subscription = 1
      AND s.sale_date <= @cutoff_date
      AND (s.is_active_on_cutoff = 1 OR s.is_finished_before_cutoff = 1)
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY client_ref, candidate_for_funnel
            ORDER BY end_date DESC, start_date DESC, sale_date DESC, subscription_ref DESC
        ) AS rank_number,
        COUNT(*) OVER (PARTITION BY client_ref, candidate_for_funnel) AS candidate_count
    FROM candidates
)
SELECT
    client_ref,
    client_id,
    subscription_ref,
    candidate_for_funnel,
    rank_number,
    N'end_date DESC, start_date DESC, sale_date DESC, subscription_ref DESC' AS auto_rank_reason,
    CAST(0 AS int) AS manual_override_applied,
    CASE WHEN rank_number = 1 THEN N'selected' ELSE N'not_selected' END AS selection_status,
    CASE WHEN rank_number = 1 THEN N'top-ranked candidate' ELSE N'lower-ranked candidate' END AS selection_reason,
    candidate_count
INTO fitbase_part2.subscription_candidates_ranked
FROM ranked;

CREATE INDEX IX_part2_subscription_candidates_client_ref ON fitbase_part2.subscription_candidates_ranked(client_ref);

SELECT
    r.client_ref,
    r.subscription_ref AS selected_subscription_ref,
    r.candidate_for_funnel AS selected_for_funnel,
    s.subscription_name AS selected_subscription_name,
    s.sale_date AS selected_sale_date,
    s.start_date AS selected_start_date,
    s.end_date AS selected_end_date,
    s.duration_days AS selected_duration_days,
    s.days_to_end,
    s.days_since_end,
    s.raw_club AS selected_raw_club,
    s.normalized_club AS selected_normalized_club,
    s.club_source AS selected_club_source,
    r.selection_reason,
    r.manual_override_applied,
    r.candidate_count
INTO fitbase_part2.selected_subscriptions
FROM fitbase_part2.subscription_candidates_ranked AS r
JOIN fitbase_part2.stg_subscriptions_all AS s
  ON s.client_ref = r.client_ref
 AND s.subscription_ref = r.subscription_ref
WHERE r.rank_number = 1;

CREATE INDEX IX_part2_selected_subscriptions_client_ref ON fitbase_part2.selected_subscriptions(client_ref, selected_for_funnel);

WITH card_candidates AS (
    SELECT
        pc.*,
        COUNT(*) OVER (PARTITION BY pc.client_ref) AS active_card_count,
        ROW_NUMBER() OVER (
            PARTITION BY pc.client_ref
            ORDER BY
                CASE WHEN pc.issue_date IS NULL THEN 0 ELSE 1 END DESC,
                pc.issue_date DESC,
                pc.card_ref DESC
        ) AS rn,
        COUNT(*) OVER (PARTITION BY pc.client_ref, pc.issue_date) AS issue_date_tie_count,
        MAX(pc.is_future_issue_date) OVER (PARTITION BY pc.client_ref) AS has_future_issue_date_candidate
    FROM fitbase_part2.stg_plastic_cards AS pc
    WHERE pc.is_unmarked = 1
      AND NULLIF(LTRIM(RTRIM(pc.plastic_card_number)), N'') IS NOT NULL
),
card_audit AS (
    SELECT
        client_ref,
        STRING_AGG(CAST(card_ref AS nvarchar(max)), N', ') AS all_card_refs,
        STRING_AGG(CAST(plastic_card_number AS nvarchar(max)), N', ') AS all_card_numbers_for_audit
    FROM card_candidates
    GROUP BY client_ref
),
selected AS (
    SELECT *
    FROM card_candidates
    WHERE rn = 1
)
SELECT
    c.client_ref,
    s.card_ref AS selected_card_ref,
    s.plastic_card_number AS selected_card_number,
    s.issue_date AS selected_issue_date,
    CASE
        WHEN s.card_ref IS NULL THEN N'no unmarked non-empty card'
        ELSE N'issue_date DESC, card_ref DESC'
    END AS card_selection_reason,
    COALESCE(s.active_card_count, 0) AS active_card_count,
    ca.all_card_refs,
    ca.all_card_numbers_for_audit,
    COALESCE(s.has_future_issue_date_candidate, 0) AS has_future_issue_date_candidate,
    CASE WHEN COALESCE(s.issue_date_tie_count, 0) > 1 THEN 1 ELSE 0 END AS has_issue_date_tie
INTO fitbase_part2.selected_cards
FROM fitbase_part2.stg_clients AS c
LEFT JOIN selected AS s
  ON s.client_ref = c.client_ref
LEFT JOIN card_audit AS ca
  ON ca.client_ref = c.client_ref;

CREATE INDEX IX_part2_selected_cards_client_ref ON fitbase_part2.selected_cards(client_ref);

WITH final_base AS (
    SELECT
        h.*,
        CASE
            WHEN h.has_active_full_subscription = 1 THEN N'Действующие клиенты'
            WHEN h.has_any_full_subscription = 1 AND h.has_finished_full_subscription = 1 THEN N'Реактивация'
            WHEN h.has_any_full_subscription = 1 AND h.has_finished_full_subscription = 0 THEN N'Реактивация'
            ELSE N'Новые заявки'
        END AS funnel,
        active_sub.selected_subscription_ref AS active_selected_subscription_ref,
        active_sub.selected_subscription_name AS active_selected_subscription_name,
        active_sub.selected_sale_date AS active_selected_sale_date,
        active_sub.selected_start_date AS active_selected_start_date,
        active_sub.selected_end_date AS active_selected_end_date,
        active_sub.days_to_end AS active_days_to_end,
        active_sub.days_since_end AS active_days_since_end,
        active_sub.selected_raw_club AS active_raw_club,
        active_sub.selected_normalized_club AS active_normalized_club,
        active_sub.selected_club_source AS active_club_source,
        active_sub.selection_reason AS active_selection_reason,
        active_sub.candidate_count AS active_candidate_count,
        react_sub.selected_subscription_ref AS react_selected_subscription_ref,
        react_sub.selected_subscription_name AS react_selected_subscription_name,
        react_sub.selected_sale_date AS react_selected_sale_date,
        react_sub.selected_start_date AS react_selected_start_date,
        react_sub.selected_end_date AS react_selected_end_date,
        react_sub.days_to_end AS react_days_to_end,
        react_sub.days_since_end AS react_days_since_end,
        react_sub.selected_raw_club AS react_raw_club,
        react_sub.selected_normalized_club AS react_normalized_club,
        react_sub.selected_club_source AS react_club_source,
        react_sub.selection_reason AS react_selection_reason,
        react_sub.candidate_count AS react_candidate_count
    FROM fitbase_part2.client_history_summary AS h
    LEFT JOIN fitbase_part2.selected_subscriptions AS active_sub
      ON active_sub.client_ref = h.client_ref
     AND active_sub.selected_for_funnel = N'active'
    LEFT JOIN fitbase_part2.selected_subscriptions AS react_sub
      ON react_sub.client_ref = h.client_ref
     AND react_sub.selected_for_funnel = N'reactivation'
)
SELECT
    fb.client_ref,
    fb.client_id,
    fb.client_fio,
    fb.phones,
    fb.email,
    fb.funnel,
    CASE
        WHEN fb.funnel = N'Действующие клиенты'
         AND fb.active_days_to_end BETWEEN 31 AND 60 THEN N'60-31 день до окончания'
        WHEN fb.funnel = N'Действующие клиенты'
         AND fb.active_days_to_end BETWEEN 8 AND 30 THEN N'30-8 дней до окончания'
        WHEN fb.funnel = N'Действующие клиенты'
         AND fb.active_days_to_end BETWEEN 0 AND 7 THEN N'7-0 день до окончания'
        WHEN fb.funnel = N'Действующие клиенты' THEN N'Действующие клиенты'
        WHEN fb.funnel = N'Новые заявки' THEN N'Неразобранные'
        WHEN fb.funnel = N'Реактивация'
         AND fb.react_days_since_end BETWEEN 1 AND 6 THEN N'1-6 дней'
        WHEN fb.funnel = N'Реактивация'
         AND fb.react_days_since_end BETWEEN 7 AND 29 THEN N'7-29 дней'
        WHEN fb.funnel = N'Реактивация'
         AND fb.react_days_since_end BETWEEN 30 AND 59 THEN N'30-59 дней'
        WHEN fb.funnel = N'Реактивация'
         AND fb.react_days_since_end BETWEEN 60 AND 89 THEN N'60-89 дней'
        WHEN fb.funnel = N'Реактивация'
         AND fb.react_days_since_end >= 90 THEN N'более 90 дней'
        ELSE N'более 90 дней'
    END AS funnel_step,
    CAST(0 AS int) AS budget,
    CASE
        WHEN fb.funnel = N'Новые заявки' AND fb.first_trial_or_guest_product_date IS NOT NULL
            THEN fb.first_trial_or_guest_product_date
        WHEN fb.funnel = N'Новые заявки' AND fb.first_non_full_sale_date IS NOT NULL
            THEN fb.first_non_full_sale_date
        WHEN fb.funnel = N'Новые заявки'
            THEN COALESCE(fb.client_created_at, @cutoff_date)
        WHEN fb.funnel = N'Действующие клиенты'
            THEN COALESCE(fb.first_sale_date, fb.active_selected_sale_date, fb.client_created_at, @cutoff_date)
        ELSE COALESCE(fb.first_sale_date, fb.react_selected_sale_date, fb.client_created_at, @cutoff_date)
    END AS create_date,
    CASE
        WHEN fb.funnel = N'Новые заявки' AND fb.first_trial_or_guest_product_date IS NOT NULL
            THEN N'first_trial_or_guest_product'
        WHEN fb.funnel = N'Новые заявки' AND fb.first_non_full_sale_date IS NOT NULL
            THEN N'first_non_full_sale_requires_review'
        WHEN fb.funnel = N'Новые заявки'
            THEN N'client_created_at_no_sales'
        WHEN fb.first_sale_date IS NOT NULL
            THEN N'first_sale'
        WHEN fb.funnel = N'Действующие клиенты' AND fb.active_selected_sale_date IS NOT NULL
            THEN N'selected_subscription_sale_date'
        WHEN fb.funnel = N'Реактивация' AND fb.react_selected_sale_date IS NOT NULL
            THEN N'selected_subscription_sale_date'
        ELSE N'client_created_at_fallback'
    END AS create_date_source,
    CAST(N'' AS nvarchar(200)) AS manager,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_normalized_club
        WHEN fb.funnel = N'Реактивация' THEN fb.react_normalized_club
        ELSE COALESCE(fb.last_sale_club, fb.client_normalized_club, N'Клуб не определен (fallback)')
    END AS normalized_club,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_club_source
        WHEN fb.funnel = N'Реактивация' THEN fb.react_club_source
        ELSE COALESCE(fb.last_sale_club_source, fb.client_club_source, N'fallback_no_sale_or_client_club')
    END AS club_source,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_selected_subscription_ref
        WHEN fb.funnel = N'Реактивация' THEN fb.react_selected_subscription_ref
        ELSE NULL
    END AS selected_subscription_ref,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_selected_subscription_name
        WHEN fb.funnel = N'Реактивация' THEN fb.react_selected_subscription_name
        ELSE NULL
    END AS selected_subscription_name,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_selected_start_date
        WHEN fb.funnel = N'Реактивация' THEN fb.react_selected_start_date
        ELSE NULL
    END AS selected_subscription_start_date,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_selected_end_date
        WHEN fb.funnel = N'Реактивация' THEN fb.react_selected_end_date
        ELSE NULL
    END AS selected_subscription_end_date,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_selected_sale_date
        WHEN fb.funnel = N'Реактивация' THEN fb.react_selected_sale_date
        ELSE NULL
    END AS selected_subscription_sale_date,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_days_to_end
        WHEN fb.funnel = N'Реактивация' THEN fb.react_days_to_end
        ELSE NULL
    END AS days_to_end,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_days_since_end
        WHEN fb.funnel = N'Реактивация' THEN fb.react_days_since_end
        ELSE NULL
    END AS days_since_end,
    sc.selected_card_number,
    sc.selected_card_ref,
    fb.active_full_subscription_count,
    fb.finished_full_subscription_count,
    fb.full_subscription_count,
    fb.trial_or_guest_sale_count,
    CASE
        WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_selection_reason
        WHEN fb.funnel = N'Реактивация' THEN fb.react_selection_reason
        ELSE N'no full subscription'
    END AS selection_reason,
    CONCAT(
        CASE WHEN NULLIF(LTRIM(RTRIM(COALESCE(fb.client_fio, N''))), N'') IS NULL THEN N'missing_fio;' ELSE N'' END,
        CASE WHEN NULLIF(LTRIM(RTRIM(COALESCE(fb.phones, N''))), N'') IS NULL THEN N'missing_phone;' ELSE N'' END,
        CASE WHEN NULLIF(LTRIM(RTRIM(COALESCE(
            CASE
                WHEN fb.funnel = N'Действующие клиенты' THEN fb.active_normalized_club
                WHEN fb.funnel = N'Реактивация' THEN fb.react_normalized_club
                ELSE COALESCE(fb.last_sale_club, fb.client_normalized_club, N'Клуб не определен (fallback)')
            END, N''))), N'') IS NULL THEN N'missing_club;' ELSE N'' END,
        CASE WHEN NULLIF(LTRIM(RTRIM(COALESCE(sc.selected_card_number, N''))), N'') IS NULL THEN N'missing_card;' ELSE N'' END,
        CASE WHEN fb.funnel = N'Действующие клиенты' AND COALESCE(fb.active_candidate_count, 0) > 1 THEN N'multiple_active_subscriptions;' ELSE N'' END,
        CASE WHEN fb.funnel = N'Реактивация' AND COALESCE(fb.react_candidate_count, 0) > 1 THEN N'multiple_finished_subscriptions;' ELSE N'' END,
        CASE WHEN COALESCE(sc.active_card_count, 0) > 1 THEN N'multiple_cards;' ELSE N'' END,
        CASE WHEN fb.funnel = N'Реактивация' AND COALESCE(fb.react_days_since_end, 1) <= 0 THEN N'reactivation_boundary_anomaly;' ELSE N'' END,
        CASE WHEN fb.client_marked = 1 THEN N'client_marked;' ELSE N'' END
    ) AS validation_status,
    @cutoff_date AS cutoff_date
INTO fitbase_part2.final_funnel_clients
FROM final_base AS fb
LEFT JOIN fitbase_part2.selected_cards AS sc
  ON sc.client_ref = fb.client_ref;

UPDATE fitbase_part2.final_funnel_clients
SET validation_status = N'ok'
WHERE validation_status = N'';

CREATE INDEX IX_part2_final_funnel_clients_ref ON fitbase_part2.final_funnel_clients(client_ref);
CREATE INDEX IX_part2_final_funnel_clients_funnel ON fitbase_part2.final_funnel_clients(funnel, funnel_step);

SELECT 'stg_clients' AS table_name, COUNT_BIG(*) AS rows_count FROM fitbase_part2.stg_clients
UNION ALL SELECT 'stg_client_contacts', COUNT_BIG(*) FROM fitbase_part2.stg_client_contacts
UNION ALL SELECT 'stg_products', COUNT_BIG(*) FROM fitbase_part2.stg_products
UNION ALL SELECT 'stg_subscriptions_all', COUNT_BIG(*) FROM fitbase_part2.stg_subscriptions_all
UNION ALL SELECT 'stg_sales_all', COUNT_BIG(*) FROM fitbase_part2.stg_sales_all
UNION ALL SELECT 'stg_plastic_cards', COUNT_BIG(*) FROM fitbase_part2.stg_plastic_cards
UNION ALL SELECT 'client_history_summary', COUNT_BIG(*) FROM fitbase_part2.client_history_summary
UNION ALL SELECT 'subscription_candidates_ranked', COUNT_BIG(*) FROM fitbase_part2.subscription_candidates_ranked
UNION ALL SELECT 'selected_subscriptions', COUNT_BIG(*) FROM fitbase_part2.selected_subscriptions
UNION ALL SELECT 'selected_cards', COUNT_BIG(*) FROM fitbase_part2.selected_cards
UNION ALL SELECT 'final_funnel_clients', COUNT_BIG(*) FROM fitbase_part2.final_funnel_clients
ORDER BY table_name;
GO
