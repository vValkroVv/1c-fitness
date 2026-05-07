USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';
DECLARE @active_segment_ref binary(16) = 0xB071000C29D830FD11F01B610376A948;

WITH active_segment AS (
    SELECT DISTINCT r._Fld2880_RRRef AS client_ref
    FROM dbo._InfoRg2878 AS r
    WHERE r._Fld2879_RTRef = 0x0000005B
      AND r._Fld2879_RRRef = @active_segment_ref
      AND r._Fld2880_RTRef = 0x00000040
),
membership_candidates AS (
    SELECT
        d._Fld1447_RRRef AS client_ref,
        r._Fld3061RRef AS doc_ref,
        d._Date_Time AS sale_date,
        r._Fld3063 AS end_date_candidate,
        r._Fld3064 AS valid_until_candidate,
        r._Fld3065 AS duration_days_candidate,
        p._Description AS product_name,
        st._Description AS booking_status_name
    FROM dbo._InfoRg3060 AS r
    JOIN dbo._Document163 AS d
        ON r._Fld3061RRef = d._IDRRef
    LEFT JOIN dbo._Reference72 AS p
        ON d._Fld1446RRef = p._IDRRef
    LEFT JOIN dbo._Reference5062 AS st
        ON r._Fld5960RRef = st._IDRRef
    WHERE d._Fld1447_RTRef = 0x00000040
      AND d._Posted = 0x01
      AND d._Marked = 0x00
      AND r._Fld3064 >= @cutoff
      AND r._Fld3065 >= 30
      AND (
            p._Description LIKE N'%Абонемент%'
         OR p._Description LIKE N'%абонемент%'
         OR p._Description LIKE N'%МУЛЬТИ%'
         OR p._Description LIKE N'%УЛЬТРА%'
         OR p._Description LIKE N'%членств%'
         OR p._Description LIKE N'%Членств%'
      )
),
membership_clients AS (
    SELECT DISTINCT client_ref
    FROM membership_candidates
)
SELECT
    'segment_vs_membership_counts' AS probe,
    (SELECT COUNT_BIG(*) FROM active_segment) AS active_segment_clients,
    (SELECT COUNT_BIG(*) FROM membership_clients) AS membership_active_clients,
    (SELECT COUNT_BIG(*) FROM active_segment s JOIN membership_clients m ON s.client_ref = m.client_ref) AS intersection_clients,
    (SELECT COUNT_BIG(*) FROM active_segment s LEFT JOIN membership_clients m ON s.client_ref = m.client_ref WHERE m.client_ref IS NULL) AS segment_without_membership_clients,
    (SELECT COUNT_BIG(*) FROM membership_clients m LEFT JOIN active_segment s ON s.client_ref = m.client_ref WHERE s.client_ref IS NULL) AS membership_without_segment_clients;

WITH active_segment AS (
    SELECT DISTINCT r._Fld2880_RRRef AS client_ref
    FROM dbo._InfoRg2878 AS r
    WHERE r._Fld2879_RTRef = 0x0000005B
      AND r._Fld2879_RRRef = @active_segment_ref
      AND r._Fld2880_RTRef = 0x00000040
),
membership_candidates AS (
    SELECT
        d._Fld1447_RRRef AS client_ref,
        r._Fld3061RRef AS doc_ref,
        d._Date_Time AS sale_date,
        r._Fld3063 AS end_date_candidate,
        r._Fld3064 AS valid_until_candidate,
        r._Fld3065 AS duration_days_candidate,
        p._Description AS product_name,
        st._Description AS booking_status_name,
        ROW_NUMBER() OVER (
            PARTITION BY d._Fld1447_RRRef
            ORDER BY r._Fld3064 DESC, r._Fld3063 DESC, d._Date_Time DESC
        ) AS rn
    FROM dbo._InfoRg3060 AS r
    JOIN dbo._Document163 AS d
        ON r._Fld3061RRef = d._IDRRef
    LEFT JOIN dbo._Reference72 AS p
        ON d._Fld1446RRef = p._IDRRef
    LEFT JOIN dbo._Reference5062 AS st
        ON r._Fld5960RRef = st._IDRRef
    WHERE d._Fld1447_RTRef = 0x00000040
      AND d._Posted = 0x01
      AND d._Marked = 0x00
      AND r._Fld3064 >= @cutoff
      AND r._Fld3065 >= 30
      AND (
            p._Description LIKE N'%Абонемент%'
         OR p._Description LIKE N'%абонемент%'
         OR p._Description LIKE N'%МУЛЬТИ%'
         OR p._Description LIKE N'%УЛЬТРА%'
         OR p._Description LIKE N'%членств%'
         OR p._Description LIKE N'%Членств%'
      )
),
best_membership AS (
    SELECT *
    FROM membership_candidates
    WHERE rn = 1
)
SELECT
    'active_segment_stage_preview' AS probe,
    CASE
        WHEN bm.booking_status_name LIKE N'%Брон%' OR bm.booking_status_name LIKE N'%брон%' THEN N'Бронь'
        WHEN DATEDIFF(day, @cutoff, bm.valid_until_candidate) BETWEEN 31 AND 60 THEN N'60-31 день до окончания'
        WHEN DATEDIFF(day, @cutoff, bm.valid_until_candidate) BETWEEN 8 AND 30 THEN N'30-8 дней до окончания'
        WHEN DATEDIFF(day, @cutoff, bm.valid_until_candidate) BETWEEN 0 AND 7 THEN N'7-0 день до окончания'
        WHEN bm.valid_until_candidate >= @cutoff THEN N'Действующие клиенты'
        ELSE N'no_active_membership'
    END AS funnel_step_candidate,
    COUNT_BIG(*) AS clients_count
FROM active_segment AS s
LEFT JOIN best_membership AS bm
    ON s.client_ref = bm.client_ref
GROUP BY
    CASE
        WHEN bm.booking_status_name LIKE N'%Брон%' OR bm.booking_status_name LIKE N'%брон%' THEN N'Бронь'
        WHEN DATEDIFF(day, @cutoff, bm.valid_until_candidate) BETWEEN 31 AND 60 THEN N'60-31 день до окончания'
        WHEN DATEDIFF(day, @cutoff, bm.valid_until_candidate) BETWEEN 8 AND 30 THEN N'30-8 дней до окончания'
        WHEN DATEDIFF(day, @cutoff, bm.valid_until_candidate) BETWEEN 0 AND 7 THEN N'7-0 день до окончания'
        WHEN bm.valid_until_candidate >= @cutoff THEN N'Действующие клиенты'
        ELSE N'no_active_membership'
    END
ORDER BY clients_count DESC;

WITH active_segment AS (
    SELECT DISTINCT r._Fld2880_RRRef AS client_ref
    FROM dbo._InfoRg2878 AS r
    WHERE r._Fld2879_RTRef = 0x0000005B
      AND r._Fld2879_RRRef = @active_segment_ref
      AND r._Fld2880_RTRef = 0x00000040
),
membership_candidates AS (
    SELECT
        d._Fld1447_RRRef AS client_ref,
        r._Fld3061RRef AS doc_ref,
        d._Date_Time AS sale_date,
        r._Fld3063 AS end_date_candidate,
        r._Fld3064 AS valid_until_candidate,
        r._Fld3065 AS duration_days_candidate,
        p._Description AS product_name,
        st._Description AS booking_status_name
    FROM dbo._InfoRg3060 AS r
    JOIN dbo._Document163 AS d
        ON r._Fld3061RRef = d._IDRRef
    LEFT JOIN dbo._Reference72 AS p
        ON d._Fld1446RRef = p._IDRRef
    LEFT JOIN dbo._Reference5062 AS st
        ON r._Fld5960RRef = st._IDRRef
    WHERE d._Fld1447_RTRef = 0x00000040
      AND d._Posted = 0x01
      AND d._Marked = 0x00
      AND r._Fld3064 >= @cutoff
      AND r._Fld3065 >= 30
      AND (
            p._Description LIKE N'%Абонемент%'
         OR p._Description LIKE N'%абонемент%'
         OR p._Description LIKE N'%МУЛЬТИ%'
         OR p._Description LIKE N'%УЛЬТРА%'
         OR p._Description LIKE N'%членств%'
         OR p._Description LIKE N'%Членств%'
      )
),
membership_clients AS (
    SELECT DISTINCT client_ref
    FROM membership_candidates
)
SELECT TOP 80
    'active_segment_without_membership_sample' AS probe,
    c._Code AS client_code,
    c._Description AS client_fio,
    c._Fld3832 AS client_phone
FROM active_segment AS s
JOIN dbo._Reference64 AS c
    ON s.client_ref = c._IDRRef
LEFT JOIN membership_clients AS m
    ON s.client_ref = m.client_ref
WHERE m.client_ref IS NULL
ORDER BY c._Code;
GO
