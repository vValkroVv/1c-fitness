USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';
DECLARE @active_segment_ref binary(16) = 0xB071000C29D830FD11F01B610376A948;

IF OBJECT_ID('tempdb..#active_segment') IS NOT NULL DROP TABLE #active_segment;
IF OBJECT_ID('tempdb..#membership_roles') IS NOT NULL DROP TABLE #membership_roles;
IF OBJECT_ID('tempdb..#membership_role_flags') IS NOT NULL DROP TABLE #membership_role_flags;
IF OBJECT_ID('tempdb..#client_flags') IS NOT NULL DROP TABLE #client_flags;

CREATE TABLE #active_segment (
    client_ref binary(16) NOT NULL PRIMARY KEY
);

INSERT INTO #active_segment (client_ref)
SELECT DISTINCT r._Fld2880_RRRef
FROM dbo._InfoRg2878 AS r
WHERE r._Fld2879_RTRef = 0x0000005B
  AND r._Fld2879_RRRef = @active_segment_ref
  AND r._Fld2880_RTRef = 0x00000040;

CREATE TABLE #membership_roles (
    doc_ref binary(16) NOT NULL,
    client_ref binary(16) NOT NULL,
    client_role varchar(20) NOT NULL,
    doc_number nvarchar(22) NULL,
    doc_date datetime2 NOT NULL,
    doc_marked binary(1) NOT NULL,
    doc_posted binary(1) NOT NULL,
    product_ref binary(16) NOT NULL,
    product_code nvarchar(22) NULL,
    product_name nvarchar(200) NULL,
    doc_end_date datetime2 NULL,
    reg_start_date datetime2 NULL,
    reg_end_date datetime2 NULL,
    reg_valid_until datetime2 NULL,
    duration_days numeric(10, 0) NULL,
    status_ref binary(16) NULL,
    status_code nvarchar(18) NULL,
    status_name nvarchar(100) NULL
);

INSERT INTO #membership_roles (
    doc_ref,
    client_ref,
    client_role,
    doc_number,
    doc_date,
    doc_marked,
    doc_posted,
    product_ref,
    product_code,
    product_name,
    doc_end_date,
    reg_start_date,
    reg_end_date,
    reg_valid_until,
    duration_days,
    status_ref,
    status_code,
    status_name
)
SELECT
    d._IDRRef AS doc_ref,
    v.client_ref,
    v.client_role,
    d._Number,
    d._Date_Time,
    d._Marked,
    d._Posted,
    d._Fld1446RRef,
    p._Code,
    p._Description,
    d._Fld1450,
    r._Fld3062,
    r._Fld3063,
    r._Fld3064,
    r._Fld3065,
    r._Fld5960RRef,
    st._Code,
    st._Description
FROM dbo._Document163 AS d
LEFT JOIN dbo._InfoRg3060 AS r
    ON r._Fld3061RRef = d._IDRRef
LEFT JOIN dbo._Reference72 AS p
    ON d._Fld1446RRef = p._IDRRef
LEFT JOIN dbo._Reference5062 AS st
    ON r._Fld5960RRef = st._IDRRef
CROSS APPLY (
    SELECT d._Fld1447_RRRef AS client_ref, 'fld1447' AS client_role
    WHERE d._Fld1447_RTRef = 0x00000040
    UNION ALL
    SELECT d._Fld9152RRef AS client_ref, 'fld9152' AS client_role
    WHERE d._Fld9152RRef <> 0x00000000000000000000000000000000
      AND EXISTS (
          SELECT 1
          FROM dbo._Reference64 AS c
          WHERE c._IDRRef = d._Fld9152RRef
      )
) AS v;

CREATE INDEX IX_membership_roles_client ON #membership_roles(client_ref);
CREATE INDEX IX_membership_roles_doc ON #membership_roles(doc_ref);
CREATE INDEX IX_membership_roles_role ON #membership_roles(client_role);

CREATE TABLE #membership_role_flags (
    doc_ref binary(16) NOT NULL,
    client_ref binary(16) NOT NULL,
    client_role varchar(20) NOT NULL,
    doc_number nvarchar(22) NULL,
    doc_date datetime2 NOT NULL,
    product_code nvarchar(22) NULL,
    product_name nvarchar(200) NULL,
    status_name nvarchar(100) NULL,
    doc_end_date datetime2 NULL,
    reg_end_date datetime2 NULL,
    reg_valid_until datetime2 NULL,
    duration_days numeric(10, 0) NULL,
    is_posted_not_marked bit NOT NULL,
    is_membership_like_product bit NOT NULL,
    has_duration_30 bit NOT NULL,
    active_by_doc_end bit NOT NULL,
    active_by_reg_end bit NOT NULL,
    active_by_valid_until bit NOT NULL,
    active_by_any_end bit NOT NULL,
    current_filter_candidate bit NOT NULL
);

INSERT INTO #membership_role_flags (
    doc_ref,
    client_ref,
    client_role,
    doc_number,
    doc_date,
    product_code,
    product_name,
    status_name,
    doc_end_date,
    reg_end_date,
    reg_valid_until,
    duration_days,
    is_posted_not_marked,
    is_membership_like_product,
    has_duration_30,
    active_by_doc_end,
    active_by_reg_end,
    active_by_valid_until,
    active_by_any_end,
    current_filter_candidate
)
SELECT
    doc_ref,
    client_ref,
    client_role,
    doc_number,
    doc_date,
    product_code,
    product_name,
    status_name,
    doc_end_date,
    reg_end_date,
    reg_valid_until,
    duration_days,
    CASE WHEN doc_posted = 0x01 AND doc_marked = 0x00 THEN 1 ELSE 0 END AS is_posted_not_marked,
    CASE
        WHEN product_name LIKE N'%Абонемент%'
          OR product_name LIKE N'%абонемент%'
          OR product_name LIKE N'%МУЛЬТИ%'
          OR product_name LIKE N'%УЛЬТРА%'
          OR product_name LIKE N'%членств%'
          OR product_name LIKE N'%Членств%'
        THEN 1 ELSE 0
    END AS is_membership_like_product,
    CASE WHEN duration_days >= 30 THEN 1 ELSE 0 END AS has_duration_30,
    CASE WHEN doc_end_date >= @cutoff THEN 1 ELSE 0 END AS active_by_doc_end,
    CASE WHEN reg_end_date >= @cutoff THEN 1 ELSE 0 END AS active_by_reg_end,
    CASE WHEN reg_valid_until >= @cutoff THEN 1 ELSE 0 END AS active_by_valid_until,
    CASE WHEN doc_end_date >= @cutoff OR reg_end_date >= @cutoff OR reg_valid_until >= @cutoff THEN 1 ELSE 0 END AS active_by_any_end,
    CASE
        WHEN doc_posted = 0x01
         AND doc_marked = 0x00
         AND duration_days >= 30
         AND reg_valid_until >= @cutoff
         AND (
              product_name LIKE N'%Абонемент%'
           OR product_name LIKE N'%абонемент%'
           OR product_name LIKE N'%МУЛЬТИ%'
           OR product_name LIKE N'%УЛЬТРА%'
           OR product_name LIKE N'%членств%'
           OR product_name LIKE N'%Членств%'
         )
        THEN 1 ELSE 0
    END AS current_filter_candidate
FROM #membership_roles;

CREATE INDEX IX_membership_flags_client ON #membership_role_flags(client_ref);
CREATE INDEX IX_membership_flags_candidate ON #membership_role_flags(current_filter_candidate, client_ref);

CREATE TABLE #client_flags (
    client_ref binary(16) NOT NULL PRIMARY KEY,
    in_active_segment bit NOT NULL,
    has_doc_fld1447 bit NOT NULL,
    has_doc_fld9152 bit NOT NULL,
    has_doc_any_role bit NOT NULL,
    has_posted_any_role bit NOT NULL,
    has_membership_product_any_role bit NOT NULL,
    has_duration30_any_role bit NOT NULL,
    active_by_doc_end_any_role bit NOT NULL,
    active_by_reg_end_any_role bit NOT NULL,
    active_by_valid_until_any_role bit NOT NULL,
    active_by_current_filter_fld1447 bit NOT NULL,
    active_by_current_filter_fld9152 bit NOT NULL,
    active_by_current_filter_any_role bit NOT NULL,
    has_booking_status_any_role bit NOT NULL
);

INSERT INTO #client_flags (
    client_ref,
    in_active_segment,
    has_doc_fld1447,
    has_doc_fld9152,
    has_doc_any_role,
    has_posted_any_role,
    has_membership_product_any_role,
    has_duration30_any_role,
    active_by_doc_end_any_role,
    active_by_reg_end_any_role,
    active_by_valid_until_any_role,
    active_by_current_filter_fld1447,
    active_by_current_filter_fld9152,
    active_by_current_filter_any_role,
    has_booking_status_any_role
)
SELECT
    c._IDRRef AS client_ref,
    CASE WHEN s.client_ref IS NOT NULL THEN 1 ELSE 0 END AS in_active_segment,
    MAX(CASE WHEN f.client_role = 'fld1447' THEN 1 ELSE 0 END) AS has_doc_fld1447,
    MAX(CASE WHEN f.client_role = 'fld9152' THEN 1 ELSE 0 END) AS has_doc_fld9152,
    MAX(CASE WHEN f.client_ref IS NOT NULL THEN 1 ELSE 0 END) AS has_doc_any_role,
    MAX(CASE WHEN f.is_posted_not_marked = 1 THEN 1 ELSE 0 END) AS has_posted_any_role,
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.is_membership_like_product = 1 THEN 1 ELSE 0 END) AS has_membership_product_any_role,
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.has_duration_30 = 1 THEN 1 ELSE 0 END) AS has_duration30_any_role,
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.active_by_doc_end = 1 THEN 1 ELSE 0 END) AS active_by_doc_end_any_role,
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.active_by_reg_end = 1 THEN 1 ELSE 0 END) AS active_by_reg_end_any_role,
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.active_by_valid_until = 1 THEN 1 ELSE 0 END) AS active_by_valid_until_any_role,
    MAX(CASE WHEN f.client_role = 'fld1447' AND f.current_filter_candidate = 1 THEN 1 ELSE 0 END) AS active_by_current_filter_fld1447,
    MAX(CASE WHEN f.client_role = 'fld9152' AND f.current_filter_candidate = 1 THEN 1 ELSE 0 END) AS active_by_current_filter_fld9152,
    MAX(CASE WHEN f.current_filter_candidate = 1 THEN 1 ELSE 0 END) AS active_by_current_filter_any_role,
    MAX(CASE WHEN f.status_name LIKE N'%Брон%' OR f.status_name LIKE N'%брон%' THEN 1 ELSE 0 END) AS has_booking_status_any_role
FROM dbo._Reference64 AS c
LEFT JOIN #active_segment AS s
    ON c._IDRRef = s.client_ref
LEFT JOIN #membership_role_flags AS f
    ON c._IDRRef = f.client_ref
WHERE s.client_ref IS NOT NULL
   OR f.client_ref IS NOT NULL
GROUP BY c._IDRRef, CASE WHEN s.client_ref IS NOT NULL THEN 1 ELSE 0 END;

SELECT
    '01_role_coverage' AS probe,
    COUNT_BIG(*) AS active_segment_clients,
    SUM(CASE WHEN has_doc_fld1447 = 1 THEN 1 ELSE 0 END) AS segment_has_doc_fld1447,
    SUM(CASE WHEN has_doc_fld9152 = 1 THEN 1 ELSE 0 END) AS segment_has_doc_fld9152,
    SUM(CASE WHEN has_doc_any_role = 1 THEN 1 ELSE 0 END) AS segment_has_doc_any_role,
    SUM(CASE WHEN active_by_current_filter_fld1447 = 1 THEN 1 ELSE 0 END) AS segment_current_filter_fld1447,
    SUM(CASE WHEN active_by_current_filter_fld9152 = 1 THEN 1 ELSE 0 END) AS segment_current_filter_fld9152,
    SUM(CASE WHEN active_by_current_filter_any_role = 1 THEN 1 ELSE 0 END) AS segment_current_filter_any_role
FROM #client_flags
WHERE in_active_segment = 1;

SELECT
    '02_filter_overlap_by_role' AS probe,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE in_active_segment = 1) AS active_segment_clients,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE active_by_current_filter_fld1447 = 1) AS current_filter_fld1447_clients,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE active_by_current_filter_fld9152 = 1) AS current_filter_fld9152_clients,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE active_by_current_filter_any_role = 1) AS current_filter_any_role_clients,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE in_active_segment = 1 AND active_by_current_filter_fld1447 = 1) AS intersection_fld1447,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE in_active_segment = 1 AND active_by_current_filter_fld9152 = 1) AS intersection_fld9152,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE in_active_segment = 1 AND active_by_current_filter_any_role = 1) AS intersection_any_role,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE in_active_segment = 1 AND active_by_current_filter_any_role = 0) AS segment_without_any_role_filter,
    (SELECT COUNT_BIG(*) FROM #client_flags WHERE in_active_segment = 0 AND active_by_current_filter_any_role = 1) AS any_role_filter_without_segment;

SELECT
    '03_segment_filter_ladder' AS probe,
    COUNT_BIG(*) AS active_segment_clients,
    SUM(CASE WHEN has_doc_any_role = 1 THEN 1 ELSE 0 END) AS has_any_doc163_role,
    SUM(CASE WHEN has_posted_any_role = 1 THEN 1 ELSE 0 END) AS has_posted_not_marked,
    SUM(CASE WHEN has_membership_product_any_role = 1 THEN 1 ELSE 0 END) AS has_membership_like_product,
    SUM(CASE WHEN has_duration30_any_role = 1 THEN 1 ELSE 0 END) AS has_duration_30,
    SUM(CASE WHEN active_by_doc_end_any_role = 1 THEN 1 ELSE 0 END) AS active_by_doc163_fld1450,
    SUM(CASE WHEN active_by_reg_end_any_role = 1 THEN 1 ELSE 0 END) AS active_by_inforg3060_fld3063,
    SUM(CASE WHEN active_by_valid_until_any_role = 1 THEN 1 ELSE 0 END) AS active_by_inforg3060_fld3064,
    SUM(CASE WHEN active_by_current_filter_any_role = 1 THEN 1 ELSE 0 END) AS active_by_full_current_filter
FROM #client_flags
WHERE in_active_segment = 1;

SELECT
    '04_segment_missing_reason' AS probe,
    CASE
        WHEN has_doc_any_role = 0 THEN 'no_document163_by_fld1447_or_fld9152'
        WHEN has_posted_any_role = 0 THEN 'only_unposted_or_marked_documents'
        WHEN has_membership_product_any_role = 0 THEN 'no_membership_like_product_by_keywords'
        WHEN has_duration30_any_role = 0 THEN 'no_duration_30_candidate'
        WHEN active_by_valid_until_any_role = 0 THEN 'no_active_fld3064_valid_until'
        WHEN active_by_current_filter_any_role = 0 THEN 'combination_not_on_same_row'
        ELSE 'in_current_filter'
    END AS reason,
    COUNT_BIG(*) AS clients_count
FROM #client_flags
WHERE in_active_segment = 1
GROUP BY
    CASE
        WHEN has_doc_any_role = 0 THEN 'no_document163_by_fld1447_or_fld9152'
        WHEN has_posted_any_role = 0 THEN 'only_unposted_or_marked_documents'
        WHEN has_membership_product_any_role = 0 THEN 'no_membership_like_product_by_keywords'
        WHEN has_duration30_any_role = 0 THEN 'no_duration_30_candidate'
        WHEN active_by_valid_until_any_role = 0 THEN 'no_active_fld3064_valid_until'
        WHEN active_by_current_filter_any_role = 0 THEN 'combination_not_on_same_row'
        ELSE 'in_current_filter'
    END
ORDER BY clients_count DESC;

WITH best_rows AS (
    SELECT
        f.*,
        CASE WHEN s.client_ref IS NOT NULL THEN 1 ELSE 0 END AS in_active_segment,
        ROW_NUMBER() OVER (
            PARTITION BY f.client_ref
            ORDER BY
                f.current_filter_candidate DESC,
                f.is_posted_not_marked DESC,
                f.active_by_valid_until DESC,
                f.reg_valid_until DESC,
                f.reg_end_date DESC,
                f.doc_end_date DESC,
                f.doc_date DESC
        ) AS rn
    FROM #membership_role_flags AS f
    LEFT JOIN #active_segment AS s
        ON f.client_ref = s.client_ref
)
SELECT
    '05_best_row_date_status_by_group' AS probe,
    CASE
        WHEN in_active_segment = 1 AND current_filter_candidate = 1 THEN 'intersection'
        WHEN in_active_segment = 1 AND current_filter_candidate = 0 THEN 'segment_only_best_row'
        WHEN in_active_segment = 0 AND current_filter_candidate = 1 THEN 'register_filter_only'
        ELSE 'other'
    END AS group_name,
    COUNT_BIG(*) AS clients_count,
    SUM(CASE WHEN doc_end_date >= @cutoff THEN 1 ELSE 0 END) AS best_doc_end_after_cutoff,
    SUM(CASE WHEN reg_end_date >= @cutoff THEN 1 ELSE 0 END) AS best_reg_end_after_cutoff,
    SUM(CASE WHEN reg_valid_until >= @cutoff THEN 1 ELSE 0 END) AS best_valid_until_after_cutoff,
    SUM(CASE WHEN status_name LIKE N'%Брон%' OR status_name LIKE N'%брон%' THEN 1 ELSE 0 END) AS best_booking_status,
    MIN(doc_date) AS min_doc_date,
    MAX(doc_date) AS max_doc_date,
    MIN(doc_end_date) AS min_doc_end,
    MAX(doc_end_date) AS max_doc_end,
    MIN(reg_end_date) AS min_reg_end,
    MAX(reg_end_date) AS max_reg_end,
    MIN(reg_valid_until) AS min_valid_until,
    MAX(reg_valid_until) AS max_valid_until
FROM best_rows
WHERE rn = 1
  AND (
        in_active_segment = 1
     OR current_filter_candidate = 1
  )
GROUP BY
    CASE
        WHEN in_active_segment = 1 AND current_filter_candidate = 1 THEN 'intersection'
        WHEN in_active_segment = 1 AND current_filter_candidate = 0 THEN 'segment_only_best_row'
        WHEN in_active_segment = 0 AND current_filter_candidate = 1 THEN 'register_filter_only'
        ELSE 'other'
    END
ORDER BY clients_count DESC;

WITH best_rows AS (
    SELECT
        f.*,
        CASE WHEN s.client_ref IS NOT NULL THEN 1 ELSE 0 END AS in_active_segment,
        ROW_NUMBER() OVER (
            PARTITION BY f.client_ref
            ORDER BY
                f.current_filter_candidate DESC,
                f.is_posted_not_marked DESC,
                f.active_by_valid_until DESC,
                f.reg_valid_until DESC,
                f.reg_end_date DESC,
                f.doc_end_date DESC,
                f.doc_date DESC
        ) AS rn
    FROM #membership_role_flags AS f
    LEFT JOIN #active_segment AS s
        ON f.client_ref = s.client_ref
)
SELECT TOP 50
    '06_register_filter_only_products' AS probe,
    product_code,
    product_name,
    status_name,
    COUNT_BIG(*) AS clients_count,
    MIN(doc_end_date) AS min_doc_end,
    MAX(doc_end_date) AS max_doc_end,
    MIN(reg_end_date) AS min_reg_end,
    MAX(reg_end_date) AS max_reg_end,
    MIN(reg_valid_until) AS min_valid_until,
    MAX(reg_valid_until) AS max_valid_until
FROM best_rows
WHERE rn = 1
  AND in_active_segment = 0
  AND current_filter_candidate = 1
GROUP BY product_code, product_name, status_name
ORDER BY clients_count DESC, product_name;

WITH best_rows AS (
    SELECT
        f.*,
        CASE WHEN s.client_ref IS NOT NULL THEN 1 ELSE 0 END AS in_active_segment,
        ROW_NUMBER() OVER (
            PARTITION BY f.client_ref
            ORDER BY
                f.current_filter_candidate DESC,
                f.is_posted_not_marked DESC,
                f.active_by_valid_until DESC,
                f.reg_valid_until DESC,
                f.reg_end_date DESC,
                f.doc_end_date DESC,
                f.doc_date DESC
        ) AS rn
    FROM #membership_role_flags AS f
    LEFT JOIN #active_segment AS s
        ON f.client_ref = s.client_ref
)
SELECT
    '07_valid_until_gap_buckets' AS probe,
    CASE
        WHEN in_active_segment = 1 AND current_filter_candidate = 1 THEN 'intersection'
        WHEN in_active_segment = 0 AND current_filter_candidate = 1 THEN 'register_filter_only'
        WHEN in_active_segment = 1 AND current_filter_candidate = 0 THEN 'segment_only_best_row'
        ELSE 'other'
    END AS group_name,
    CASE
        WHEN reg_end_date IS NULL OR reg_valid_until IS NULL THEN 'missing_date'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) < 0 THEN 'negative'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 7 THEN '0-7'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 30 THEN '8-30'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 90 THEN '31-90'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 180 THEN '91-180'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 365 THEN '181-365'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 730 THEN '366-730'
        ELSE '731+'
    END AS reg_end_to_valid_until_gap,
    COUNT_BIG(*) AS clients_count
FROM best_rows
WHERE rn = 1
  AND (
        in_active_segment = 1
     OR current_filter_candidate = 1
  )
GROUP BY
    CASE
        WHEN in_active_segment = 1 AND current_filter_candidate = 1 THEN 'intersection'
        WHEN in_active_segment = 0 AND current_filter_candidate = 1 THEN 'register_filter_only'
        WHEN in_active_segment = 1 AND current_filter_candidate = 0 THEN 'segment_only_best_row'
        ELSE 'other'
    END,
    CASE
        WHEN reg_end_date IS NULL OR reg_valid_until IS NULL THEN 'missing_date'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) < 0 THEN 'negative'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 7 THEN '0-7'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 30 THEN '8-30'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 90 THEN '31-90'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 180 THEN '91-180'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 365 THEN '181-365'
        WHEN DATEDIFF(day, reg_end_date, reg_valid_until) <= 730 THEN '366-730'
        ELSE '731+'
    END
ORDER BY group_name, clients_count DESC;

WITH best_rows AS (
    SELECT
        f.*,
        CASE WHEN s.client_ref IS NOT NULL THEN 1 ELSE 0 END AS in_active_segment,
        ROW_NUMBER() OVER (
            PARTITION BY f.client_ref
            ORDER BY
                f.current_filter_candidate DESC,
                f.is_posted_not_marked DESC,
                f.active_by_valid_until DESC,
                f.reg_valid_until DESC,
                f.reg_end_date DESC,
                f.doc_end_date DESC,
                f.doc_date DESC
        ) AS rn
    FROM #membership_role_flags AS f
    LEFT JOIN #active_segment AS s
        ON f.client_ref = s.client_ref
)
SELECT TOP 80
    '08_segment_without_filter_samples' AS probe,
    c._Code AS client_code,
    c._Description AS client_fio,
    c._Fld3832 AS phone,
    b.client_role,
    b.doc_number,
    b.doc_date,
    b.product_code,
    b.product_name,
    b.status_name,
    b.doc_end_date,
    b.reg_end_date,
    b.reg_valid_until,
    b.duration_days,
    b.is_posted_not_marked,
    b.is_membership_like_product,
    b.has_duration_30,
    b.active_by_doc_end,
    b.active_by_reg_end,
    b.active_by_valid_until
FROM #active_segment AS s
JOIN dbo._Reference64 AS c
    ON s.client_ref = c._IDRRef
LEFT JOIN best_rows AS b
    ON s.client_ref = b.client_ref
   AND b.rn = 1
WHERE NOT EXISTS (
    SELECT 1
    FROM #membership_role_flags AS f
    WHERE f.client_ref = s.client_ref
      AND f.current_filter_candidate = 1
)
ORDER BY c._Code;

SELECT
    '09_document163_client_role_relationship' AS probe,
    CASE
        WHEN d._Fld1447_RTRef <> 0x00000040
         AND d._Fld9152RRef = 0x00000000000000000000000000000000
            THEN 'no_client_in_either_field'
        WHEN d._Fld1447_RTRef = 0x00000040
         AND d._Fld9152RRef = 0x00000000000000000000000000000000
            THEN 'payer_1447_only'
        WHEN d._Fld1447_RTRef <> 0x00000040
         AND d._Fld9152RRef <> 0x00000000000000000000000000000000
         AND c9152._IDRRef IS NOT NULL
            THEN 'member_9152_only'
        WHEN d._Fld1447_RTRef = 0x00000040
         AND d._Fld9152RRef = d._Fld1447_RRRef
         AND c9152._IDRRef IS NOT NULL
            THEN 'payer_equals_member'
        WHEN d._Fld1447_RTRef = 0x00000040
         AND d._Fld9152RRef <> d._Fld1447_RRRef
         AND d._Fld9152RRef <> 0x00000000000000000000000000000000
         AND c9152._IDRRef IS NOT NULL
            THEN 'payer_differs_from_member'
        WHEN d._Fld9152RRef <> 0x00000000000000000000000000000000
         AND c9152._IDRRef IS NULL
            THEN 'fld9152_not_reference64'
        ELSE 'other'
    END AS relationship,
    COUNT_BIG(*) AS document_rows,
    COUNT(DISTINCT CONVERT(varchar(32), d._IDRRef, 2)) AS distinct_documents,
    COUNT(DISTINCT CASE WHEN d._Fld1447_RTRef = 0x00000040 THEN CONVERT(varchar(32), d._Fld1447_RRRef, 2) END) AS distinct_fld1447_clients,
    COUNT(DISTINCT CASE WHEN c9152._IDRRef IS NOT NULL THEN CONVERT(varchar(32), d._Fld9152RRef, 2) END) AS distinct_fld9152_clients
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference64 AS c9152
    ON d._Fld9152RRef = c9152._IDRRef
GROUP BY
    CASE
        WHEN d._Fld1447_RTRef <> 0x00000040
         AND d._Fld9152RRef = 0x00000000000000000000000000000000
            THEN 'no_client_in_either_field'
        WHEN d._Fld1447_RTRef = 0x00000040
         AND d._Fld9152RRef = 0x00000000000000000000000000000000
            THEN 'payer_1447_only'
        WHEN d._Fld1447_RTRef <> 0x00000040
         AND d._Fld9152RRef <> 0x00000000000000000000000000000000
         AND c9152._IDRRef IS NOT NULL
            THEN 'member_9152_only'
        WHEN d._Fld1447_RTRef = 0x00000040
         AND d._Fld9152RRef = d._Fld1447_RRRef
         AND c9152._IDRRef IS NOT NULL
            THEN 'payer_equals_member'
        WHEN d._Fld1447_RTRef = 0x00000040
         AND d._Fld9152RRef <> d._Fld1447_RRRef
         AND d._Fld9152RRef <> 0x00000000000000000000000000000000
         AND c9152._IDRRef IS NOT NULL
            THEN 'payer_differs_from_member'
        WHEN d._Fld9152RRef <> 0x00000000000000000000000000000000
         AND c9152._IDRRef IS NULL
            THEN 'fld9152_not_reference64'
        ELSE 'other'
    END
ORDER BY document_rows DESC;

SELECT TOP 80
    '10_payer_differs_from_member_samples' AS probe,
    d._Number AS doc_number,
    d._Date_Time AS doc_date,
    payer._Code AS payer_code,
    payer._Description AS payer_fio,
    payer._Fld3832 AS payer_phone,
    member._Code AS member_code,
    member._Description AS member_fio,
    member._Fld3832 AS member_phone,
    p._Code AS product_code,
    p._Description AS product_name,
    r._Fld3063 AS reg_end_date,
    r._Fld3064 AS reg_valid_until,
    r._Fld3065 AS duration_days,
    st._Description AS status_name
FROM dbo._Document163 AS d
JOIN dbo._Reference64 AS payer
    ON d._Fld1447_RTRef = 0x00000040
   AND d._Fld1447_RRRef = payer._IDRRef
JOIN dbo._Reference64 AS member
    ON d._Fld9152RRef = member._IDRRef
LEFT JOIN dbo._InfoRg3060 AS r
    ON r._Fld3061RRef = d._IDRRef
LEFT JOIN dbo._Reference72 AS p
    ON d._Fld1446RRef = p._IDRRef
LEFT JOIN dbo._Reference5062 AS st
    ON r._Fld5960RRef = st._IDRRef
WHERE d._Fld9152RRef <> 0x00000000000000000000000000000000
  AND d._Fld9152RRef <> d._Fld1447_RRRef
ORDER BY d._Date_Time DESC, d._Number;
GO
