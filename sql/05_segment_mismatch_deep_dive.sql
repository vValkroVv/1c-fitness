USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';
DECLARE @target_segment_ref binary(16) = 0xB071000C29D830FD11F01B610376A948;
DECLARE @target_segment_created_at datetime2 = '4025-04-17';
DECLARE @chk_kk_segment_ref binary(16) = 0xB071000C29D830FD11F01B670DA8E617;

IF OBJECT_ID('tempdb..#active_segment') IS NOT NULL DROP TABLE #active_segment;
IF OBJECT_ID('tempdb..#chk_kk_segment') IS NOT NULL DROP TABLE #chk_kk_segment;
IF OBJECT_ID('tempdb..#role_rows') IS NOT NULL DROP TABLE #role_rows;
IF OBJECT_ID('tempdb..#flags') IS NOT NULL DROP TABLE #flags;
IF OBJECT_ID('tempdb..#client_rollup') IS NOT NULL DROP TABLE #client_rollup;

CREATE TABLE #active_segment (
    client_ref binary(16) NOT NULL PRIMARY KEY
);

INSERT INTO #active_segment (client_ref)
SELECT DISTINCT r._Fld2880_RRRef
FROM dbo._InfoRg2878 AS r
WHERE r._Fld2879_RTRef = 0x0000005B
  AND r._Fld2879_RRRef = @target_segment_ref
  AND r._Fld2880_RTRef = 0x00000040;

CREATE TABLE #chk_kk_segment (
    client_ref binary(16) NOT NULL PRIMARY KEY
);

INSERT INTO #chk_kk_segment (client_ref)
SELECT DISTINCT r._Fld2880_RRRef
FROM dbo._InfoRg2878 AS r
WHERE r._Fld2879_RTRef = 0x0000005B
  AND r._Fld2879_RRRef = @chk_kk_segment_ref
  AND r._Fld2880_RTRef = 0x00000040;

CREATE TABLE #role_rows (
    client_ref binary(16) NOT NULL,
    doc_ref binary(16) NOT NULL,
    client_role varchar(20) NOT NULL,
    doc_number nvarchar(22) NULL,
    doc_date datetime2 NOT NULL,
    doc_marked binary(1) NOT NULL,
    doc_posted binary(1) NOT NULL,
    product_code nvarchar(22) NULL,
    product_name nvarchar(200) NULL,
    status_name nvarchar(100) NULL,
    reg_end_date datetime2 NULL,
    reg_valid_until datetime2 NULL,
    duration_days numeric(10, 0) NULL
);

INSERT INTO #role_rows (
    client_ref,
    doc_ref,
    client_role,
    doc_number,
    doc_date,
    doc_marked,
    doc_posted,
    product_code,
    product_name,
    status_name,
    reg_end_date,
    reg_valid_until,
    duration_days
)
SELECT
    v.client_ref,
    d._IDRRef,
    v.client_role,
    d._Number,
    d._Date_Time,
    d._Marked,
    d._Posted,
    p._Code,
    p._Description,
    st._Description,
    r._Fld3063,
    r._Fld3064,
    r._Fld3065
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
    UNION
    SELECT d._Fld9152RRef AS client_ref, 'fld9152' AS client_role
    WHERE d._Fld9152RRef <> 0x00000000000000000000000000000000
      AND EXISTS (
          SELECT 1
          FROM dbo._Reference64 AS c
          WHERE c._IDRRef = d._Fld9152RRef
      )
) AS v;

CREATE INDEX IX_role_rows_client ON #role_rows(client_ref);

CREATE TABLE #flags (
    client_ref binary(16) NOT NULL,
    doc_ref binary(16) NOT NULL,
    client_role varchar(20) NOT NULL,
    doc_number nvarchar(22) NULL,
    doc_date datetime2 NOT NULL,
    product_code nvarchar(22) NULL,
    product_name nvarchar(200) NULL,
    status_name nvarchar(100) NULL,
    reg_end_date datetime2 NULL,
    reg_valid_until datetime2 NULL,
    duration_days numeric(10, 0) NULL,
    is_posted_not_marked bit NOT NULL,
    is_membership_product bit NOT NULL,
    is_active_valid_until bit NOT NULL,
    is_duration_30 bit NOT NULL,
    is_current_candidate bit NOT NULL
);

INSERT INTO #flags (
    client_ref,
    doc_ref,
    client_role,
    doc_number,
    doc_date,
    product_code,
    product_name,
    status_name,
    reg_end_date,
    reg_valid_until,
    duration_days,
    is_posted_not_marked,
    is_membership_product,
    is_active_valid_until,
    is_duration_30,
    is_current_candidate
)
SELECT
    client_ref,
    doc_ref,
    client_role,
    doc_number,
    doc_date,
    product_code,
    product_name,
    status_name,
    reg_end_date,
    reg_valid_until,
    duration_days,
    CASE WHEN doc_posted = 0x01 AND doc_marked = 0x00 THEN 1 ELSE 0 END,
    CASE
        WHEN product_name LIKE N'%Абонемент%'
          OR product_name LIKE N'%абонемент%'
          OR product_name LIKE N'%МУЛЬТИ%'
          OR product_name LIKE N'%УЛЬТРА%'
          OR product_name LIKE N'%членств%'
          OR product_name LIKE N'%Членств%'
        THEN 1 ELSE 0
    END,
    CASE WHEN reg_valid_until >= @cutoff THEN 1 ELSE 0 END,
    CASE WHEN duration_days >= 30 THEN 1 ELSE 0 END,
    CASE
        WHEN doc_posted = 0x01
         AND doc_marked = 0x00
         AND reg_valid_until >= @cutoff
         AND duration_days >= 30
         AND (
              product_name LIKE N'%Абонемент%'
           OR product_name LIKE N'%абонемент%'
           OR product_name LIKE N'%МУЛЬТИ%'
           OR product_name LIKE N'%УЛЬТРА%'
           OR product_name LIKE N'%членств%'
           OR product_name LIKE N'%Членств%'
         )
        THEN 1 ELSE 0
    END
FROM #role_rows;

CREATE INDEX IX_flags_client ON #flags(client_ref);
CREATE INDEX IX_flags_candidate ON #flags(is_current_candidate, client_ref);

CREATE TABLE #client_rollup (
    client_ref binary(16) NOT NULL PRIMARY KEY,
    in_target_segment bit NOT NULL,
    in_chk_kk_segment bit NOT NULL,
    has_any_doc bit NOT NULL,
    has_posted_doc bit NOT NULL,
    has_membership_product bit NOT NULL,
    has_active_membership_product bit NOT NULL,
    has_active_duration30_membership bit NOT NULL,
    in_current_candidate bit NOT NULL
);

INSERT INTO #client_rollup (
    client_ref,
    in_target_segment,
    in_chk_kk_segment,
    has_any_doc,
    has_posted_doc,
    has_membership_product,
    has_active_membership_product,
    has_active_duration30_membership,
    in_current_candidate
)
SELECT
    c._IDRRef,
    CASE WHEN s.client_ref IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN chk.client_ref IS NOT NULL THEN 1 ELSE 0 END,
    MAX(CASE WHEN f.client_ref IS NOT NULL THEN 1 ELSE 0 END),
    MAX(CASE WHEN f.is_posted_not_marked = 1 THEN 1 ELSE 0 END),
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.is_membership_product = 1 THEN 1 ELSE 0 END),
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.is_membership_product = 1 AND f.is_active_valid_until = 1 THEN 1 ELSE 0 END),
    MAX(CASE WHEN f.is_posted_not_marked = 1 AND f.is_membership_product = 1 AND f.is_active_valid_until = 1 AND f.is_duration_30 = 1 THEN 1 ELSE 0 END),
    MAX(CASE WHEN f.is_current_candidate = 1 THEN 1 ELSE 0 END)
FROM dbo._Reference64 AS c
LEFT JOIN #active_segment AS s
    ON c._IDRRef = s.client_ref
LEFT JOIN #chk_kk_segment AS chk
    ON c._IDRRef = chk.client_ref
LEFT JOIN #flags AS f
    ON c._IDRRef = f.client_ref
WHERE s.client_ref IS NOT NULL
   OR chk.client_ref IS NOT NULL
   OR f.client_ref IS NOT NULL
GROUP BY c._IDRRef, s.client_ref, chk.client_ref;

SELECT
    '01_target_segment_missing_corrected_reason' AS probe,
    CASE
        WHEN has_any_doc = 0 THEN 'no_document163_by_known_client_roles'
        WHEN has_posted_doc = 0 THEN 'only_unposted_or_marked_documents'
        WHEN has_membership_product = 0 THEN 'no_membership_like_product'
        WHEN has_active_membership_product = 0 THEN 'membership_product_not_active_by_fld3064'
        WHEN has_active_duration30_membership = 0 THEN 'active_membership_but_duration_under_30'
        WHEN in_current_candidate = 0 THEN 'combination_not_on_same_row'
        ELSE 'in_current_candidate'
    END AS corrected_reason,
    COUNT_BIG(*) AS clients_count
FROM #client_rollup
WHERE in_target_segment = 1
GROUP BY
    CASE
        WHEN has_any_doc = 0 THEN 'no_document163_by_known_client_roles'
        WHEN has_posted_doc = 0 THEN 'only_unposted_or_marked_documents'
        WHEN has_membership_product = 0 THEN 'no_membership_like_product'
        WHEN has_active_membership_product = 0 THEN 'membership_product_not_active_by_fld3064'
        WHEN has_active_duration30_membership = 0 THEN 'active_membership_but_duration_under_30'
        WHEN in_current_candidate = 0 THEN 'combination_not_on_same_row'
        ELSE 'in_current_candidate'
    END
ORDER BY clients_count DESC;

WITH best AS (
    SELECT
        f.*,
        ROW_NUMBER() OVER (
            PARTITION BY f.client_ref
            ORDER BY
                f.is_current_candidate DESC,
                f.is_posted_not_marked DESC,
                f.is_membership_product DESC,
                f.is_active_valid_until DESC,
                f.reg_valid_until DESC,
                f.doc_date DESC
        ) AS rn
    FROM #flags AS f
)
SELECT
    '02_target_segment_only_valid_until_buckets' AS probe,
    CASE
        WHEN b.client_ref IS NULL THEN 'no_document_row'
        WHEN b.reg_valid_until IS NULL OR b.reg_valid_until <= '2001-01-02' THEN 'missing_or_2001'
        WHEN b.reg_valid_until >= @cutoff THEN 'active_after_cutoff'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 7 THEN 'expired_1_7_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 30 THEN 'expired_8_30_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 90 THEN 'expired_31_90_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 180 THEN 'expired_91_180_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 365 THEN 'expired_181_365_days'
        ELSE 'expired_366_plus_days'
    END AS valid_until_bucket,
    COUNT_BIG(*) AS clients_count
FROM #active_segment AS s
LEFT JOIN #client_rollup AS cr
    ON s.client_ref = cr.client_ref
LEFT JOIN best AS b
    ON s.client_ref = b.client_ref
   AND b.rn = 1
WHERE COALESCE(cr.in_current_candidate, 0) = 0
GROUP BY
    CASE
        WHEN b.client_ref IS NULL THEN 'no_document_row'
        WHEN b.reg_valid_until IS NULL OR b.reg_valid_until <= '2001-01-02' THEN 'missing_or_2001'
        WHEN b.reg_valid_until >= @cutoff THEN 'active_after_cutoff'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 7 THEN 'expired_1_7_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 30 THEN 'expired_8_30_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 90 THEN 'expired_31_90_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 180 THEN 'expired_91_180_days'
        WHEN DATEDIFF(day, b.reg_valid_until, @cutoff) <= 365 THEN 'expired_181_365_days'
        ELSE 'expired_366_plus_days'
    END
ORDER BY clients_count DESC;

WITH best AS (
    SELECT
        f.*,
        ROW_NUMBER() OVER (
            PARTITION BY f.client_ref
            ORDER BY
                f.is_current_candidate DESC,
                f.is_posted_not_marked DESC,
                f.is_membership_product DESC,
                f.is_active_valid_until DESC,
                f.reg_valid_until DESC,
                f.doc_date DESC
        ) AS rn
    FROM #flags AS f
)
SELECT TOP 30
    '03_target_segment_only_best_status_product' AS probe,
    b.status_name,
    b.product_code,
    b.product_name,
    COUNT_BIG(*) AS clients_count,
    MIN(b.reg_valid_until) AS min_valid_until,
    MAX(b.reg_valid_until) AS max_valid_until
FROM #active_segment AS s
LEFT JOIN #client_rollup AS cr
    ON s.client_ref = cr.client_ref
LEFT JOIN best AS b
    ON s.client_ref = b.client_ref
   AND b.rn = 1
WHERE COALESCE(cr.in_current_candidate, 0) = 0
GROUP BY b.status_name, b.product_code, b.product_name
ORDER BY clients_count DESC;

WITH best_current AS (
    SELECT
        f.*,
        ROW_NUMBER() OVER (
            PARTITION BY f.client_ref
            ORDER BY
                f.reg_valid_until DESC,
                f.reg_end_date DESC,
                f.doc_date DESC
        ) AS rn
    FROM #flags AS f
    WHERE f.is_current_candidate = 1
)
SELECT
    '04_current_filter_only_doc_timing' AS probe,
    CASE
        WHEN b.doc_date < @target_segment_created_at THEN 'doc_before_target_segment_created'
        WHEN b.doc_date < '4026-01-01' THEN 'doc_after_segment_created_in_2025'
        ELSE 'doc_in_2026'
    END AS doc_timing_bucket,
    COUNT_BIG(*) AS clients_count,
    MIN(b.doc_date) AS min_doc_date,
    MAX(b.doc_date) AS max_doc_date,
    MIN(b.reg_valid_until) AS min_valid_until,
    MAX(b.reg_valid_until) AS max_valid_until
FROM best_current AS b
LEFT JOIN #active_segment AS s
    ON b.client_ref = s.client_ref
WHERE b.rn = 1
  AND s.client_ref IS NULL
GROUP BY
    CASE
        WHEN b.doc_date < @target_segment_created_at THEN 'doc_before_target_segment_created'
        WHEN b.doc_date < '4026-01-01' THEN 'doc_after_segment_created_in_2025'
        ELSE 'doc_in_2026'
    END
ORDER BY clients_count DESC;

SELECT
    '05_segment_overlap_decision_matrix' AS probe,
    COUNT_BIG(*) AS all_relevant_clients,
    SUM(CASE WHEN in_target_segment = 1 THEN 1 ELSE 0 END) AS target_segment_clients,
    SUM(CASE WHEN in_chk_kk_segment = 1 THEN 1 ELSE 0 END) AS chk_kk_segment_clients,
    SUM(CASE WHEN in_current_candidate = 1 THEN 1 ELSE 0 END) AS current_candidate_clients,
    SUM(CASE WHEN in_target_segment = 1 AND in_current_candidate = 1 THEN 1 ELSE 0 END) AS target_and_current,
    SUM(CASE WHEN in_target_segment = 1 AND in_current_candidate = 0 THEN 1 ELSE 0 END) AS target_not_current,
    SUM(CASE WHEN in_target_segment = 0 AND in_current_candidate = 1 THEN 1 ELSE 0 END) AS current_not_target,
    SUM(CASE WHEN in_chk_kk_segment = 1 AND in_current_candidate = 1 THEN 1 ELSE 0 END) AS chk_kk_and_current,
    SUM(CASE WHEN in_chk_kk_segment = 0 AND in_current_candidate = 1 THEN 1 ELSE 0 END) AS current_not_chk_kk
FROM #client_rollup;
GO
