USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

WITH snapshots AS (
    SELECT '2025-08-31' AS snapshot_date, CAST('4025-08-31' AS date) AS snapshot_sql_date
    UNION ALL
    SELECT '2026-04-29' AS snapshot_date, CAST('4026-04-29' AS date) AS snapshot_sql_date
),
base_docs AS (
    SELECT
        s.snapshot_date,
        d._IDRRef AS doc_ref,
        d._Date_Time AS doc_date,
        CASE WHEN r._Fld3063 > '3000-01-01' THEN r._Fld3063 ELSE d._Date_Time END AS start_date,
        r._Fld3064 AS valid_until,
        p._Description AS product_name,
        d._Fld1447_RTRef,
        d._Fld1447_RRRef,
        d._Fld9152RRef,
        c9152._IDRRef AS valid_9152_client_ref,
        d._Posted,
        d._Marked
    FROM snapshots AS s
    CROSS JOIN dbo._Document163 AS d
    JOIN dbo._InfoRg3060 AS r
        ON r._Fld3061RRef = d._IDRRef
    LEFT JOIN dbo._Reference72 AS p
        ON d._Fld1446RRef = p._IDRRef
    LEFT JOIN dbo._Reference64 AS c9152
        ON d._Fld9152RRef = c9152._IDRRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND CAST(CASE WHEN r._Fld3063 > '3000-01-01' THEN r._Fld3063 ELSE d._Date_Time END AS date) <= s.snapshot_sql_date
      AND CAST(r._Fld3064 AS date) >= s.snapshot_sql_date
      AND (
           p._Description LIKE N'%Абонемент%'
        OR p._Description LIKE N'%абонемент%'
        OR p._Description LIKE N'%МУЛЬТИ%'
        OR p._Description LIKE N'%УЛЬТРА%'
        OR p._Description LIKE N'%членств%'
        OR p._Description LIKE N'%Членств%'
      )
),
role_rows AS (
    SELECT snapshot_date, 'payer_1447_only' AS role_mode, _Fld1447_RRRef AS client_ref
    FROM base_docs
    WHERE _Fld1447_RTRef = 0x00000040
    UNION ALL
    SELECT snapshot_date, 'member_9152_only' AS role_mode, _Fld9152RRef AS client_ref
    FROM base_docs
    WHERE valid_9152_client_ref IS NOT NULL
    UNION ALL
    SELECT
        snapshot_date,
        'preferred_9152_else_1447' AS role_mode,
        CASE
            WHEN valid_9152_client_ref IS NOT NULL THEN _Fld9152RRef
            WHEN _Fld1447_RTRef = 0x00000040 THEN _Fld1447_RRRef
        END AS client_ref
    FROM base_docs
    WHERE valid_9152_client_ref IS NOT NULL
       OR _Fld1447_RTRef = 0x00000040
    UNION ALL
    SELECT snapshot_date, 'either_union' AS role_mode, _Fld1447_RRRef AS client_ref
    FROM base_docs
    WHERE _Fld1447_RTRef = 0x00000040
    UNION ALL
    SELECT snapshot_date, 'either_union' AS role_mode, _Fld9152RRef AS client_ref
    FROM base_docs
    WHERE valid_9152_client_ref IS NOT NULL
)
SELECT
    snapshot_date,
    role_mode,
    COUNT(DISTINCT CONVERT(varchar(32), client_ref, 2)) AS active_clients
FROM role_rows
WHERE client_ref IS NOT NULL
GROUP BY snapshot_date, role_mode
ORDER BY snapshot_date, role_mode;
GO
