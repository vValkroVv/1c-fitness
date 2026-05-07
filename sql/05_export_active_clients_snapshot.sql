SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @snapshot_date date = '$(snapshot_date)';
DECLARE @snapshot_sql_date date = DATEADD(year, 2000, @snapshot_date);
DECLARE @target_segment_ref binary(16) = 0xB071000C29D830FD11F01B610376A948;
DECLARE @chk_kk_segment_ref binary(16) = 0xB071000C29D830FD11F01B670DA8E617;

WITH target_segment AS (
    SELECT DISTINCT r._Fld2880_RRRef AS client_ref
    FROM dbo._InfoRg2878 AS r
    WHERE r._Fld2879_RTRef = 0x0000005B
      AND r._Fld2879_RRRef = @target_segment_ref
      AND r._Fld2880_RTRef = 0x00000040
),
chk_kk_segment AS (
    SELECT DISTINCT r._Fld2880_RRRef AS client_ref
    FROM dbo._InfoRg2878 AS r
    WHERE r._Fld2879_RTRef = 0x0000005B
      AND r._Fld2879_RRRef = @chk_kk_segment_ref
      AND r._Fld2880_RTRef = 0x00000040
),
role_rows AS (
    SELECT
        v.client_ref,
        d._IDRRef AS doc_ref,
        d._Date_Time AS doc_date,
        CASE
            WHEN r._Fld3063 > '3000-01-01' THEN r._Fld3063
            ELSE d._Date_Time
        END AS start_date,
        r._Fld3064 AS valid_until,
        r._Fld3065 AS duration_days,
        p._Code AS product_code,
        p._Description AS product_name,
        st._Description AS status_name,
        d._Posted AS doc_posted,
        d._Marked AS doc_marked
    FROM dbo._Document163 AS d
    JOIN dbo._InfoRg3060 AS r
        ON r._Fld3061RRef = d._IDRRef
    LEFT JOIN dbo._Reference72 AS p
        ON d._Fld1446RRef = p._IDRRef
    LEFT JOIN dbo._Reference5062 AS st
        ON r._Fld5960RRef = st._IDRRef
    LEFT JOIN dbo._Reference64 AS c9152
        ON d._Fld9152RRef = c9152._IDRRef
    CROSS APPLY (
        SELECT
            CASE
                WHEN c9152._IDRRef IS NOT NULL THEN d._Fld9152RRef
                WHEN d._Fld1447_RTRef = 0x00000040 THEN d._Fld1447_RRRef
            END AS client_ref
    ) AS v
    WHERE v.client_ref IS NOT NULL
),
active_rows AS (
    SELECT
        rr.*,
        DATEDIFF(day, CAST(rr.start_date AS date), CAST(rr.valid_until AS date)) + 1 AS calc_duration_days
    FROM role_rows AS rr
    WHERE rr.doc_posted = 0x01
      AND rr.doc_marked = 0x00
      AND CAST(rr.start_date AS date) <= @snapshot_sql_date
      AND CAST(rr.valid_until AS date) >= @snapshot_sql_date
      AND (
           rr.product_name LIKE N'%Абонемент%'
        OR rr.product_name LIKE N'%абонемент%'
        OR rr.product_name LIKE N'%МУЛЬТИ%'
        OR rr.product_name LIKE N'%УЛЬТРА%'
        OR rr.product_name LIKE N'%членств%'
        OR rr.product_name LIKE N'%Членств%'
      )
),
best_active AS (
    SELECT
        ar.*,
        ROW_NUMBER() OVER (
            PARTITION BY ar.client_ref
            ORDER BY
                ar.valid_until DESC,
                ar.start_date DESC,
                ar.doc_date DESC,
                ar.doc_ref DESC
        ) AS rn,
        MAX(CASE WHEN ar.duration_days >= 30 OR ar.calc_duration_days >= 30 THEN 1 ELSE 0 END)
            OVER (PARTITION BY ar.client_ref) AS has_active_duration_30
    FROM active_rows AS ar
)
SELECT
    'client_ref_hex' AS client_ref_hex,
    'client_code' AS client_code,
    'client_name' AS client_name,
    'client_phone' AS client_phone,
    'in_target_segment' AS in_target_segment,
    'in_chk_kk_segment' AS in_chk_kk_segment,
    'has_active_duration_30' AS has_active_duration_30,
    'doc_date' AS doc_date,
    'start_date' AS start_date,
    'valid_until' AS valid_until,
    'duration_days' AS duration_days,
    'calc_duration_days' AS calc_duration_days,
    'product_code' AS product_code,
    'product_name' AS product_name,
    'status_name' AS status_name
UNION ALL
SELECT
    CONVERT(varchar(32), c._IDRRef, 2),
    COALESCE(c._Code, ''),
    REPLACE(REPLACE(REPLACE(COALESCE(c._Description, N''), CHAR(13), N' '), CHAR(10), N' '), N'|', N'/'),
    REPLACE(REPLACE(REPLACE(COALESCE(c._Fld3832, N''), CHAR(13), N' '), CHAR(10), N' '), N'|', N'/'),
    CASE WHEN ts.client_ref IS NOT NULL THEN '1' ELSE '0' END,
    CASE WHEN chk.client_ref IS NOT NULL THEN '1' ELSE '0' END,
    CASE WHEN ba.has_active_duration_30 = 1 THEN '1' ELSE '0' END,
    CONVERT(varchar(19), DATEADD(year, -2000, ba.doc_date), 120),
    CONVERT(varchar(19), DATEADD(year, -2000, ba.start_date), 120),
    CONVERT(varchar(19), DATEADD(year, -2000, ba.valid_until), 120),
    CONVERT(varchar(30), COALESCE(ba.duration_days, 0)),
    CONVERT(varchar(30), COALESCE(ba.calc_duration_days, 0)),
    COALESCE(ba.product_code, ''),
    REPLACE(REPLACE(REPLACE(COALESCE(ba.product_name, N''), CHAR(13), N' '), CHAR(10), N' '), N'|', N'/'),
    REPLACE(REPLACE(REPLACE(COALESCE(ba.status_name, N''), CHAR(13), N' '), CHAR(10), N' '), N'|', N'/')
FROM best_active AS ba
JOIN dbo._Reference64 AS c
    ON ba.client_ref = c._IDRRef
LEFT JOIN target_segment AS ts
    ON ba.client_ref = ts.client_ref
LEFT JOIN chk_kk_segment AS chk
    ON ba.client_ref = chk.client_ref
WHERE ba.rn = 1
ORDER BY client_ref_hex;
