USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';

IF OBJECT_ID('tempdb..#active_filter') IS NOT NULL DROP TABLE #active_filter;
IF OBJECT_ID('tempdb..#segments') IS NOT NULL DROP TABLE #segments;

CREATE TABLE #active_filter (
    client_ref binary(16) NOT NULL PRIMARY KEY
);

INSERT INTO #active_filter (client_ref)
SELECT DISTINCT v.client_ref
FROM dbo._Document163 AS d
JOIN dbo._InfoRg3060 AS r
    ON r._Fld3061RRef = d._IDRRef
LEFT JOIN dbo._Reference72 AS p
    ON d._Fld1446RRef = p._IDRRef
CROSS APPLY (
    SELECT d._Fld1447_RRRef AS client_ref
    WHERE d._Fld1447_RTRef = 0x00000040
    UNION
    SELECT d._Fld9152RRef AS client_ref
    WHERE d._Fld9152RRef <> 0x00000000000000000000000000000000
      AND EXISTS (
          SELECT 1
          FROM dbo._Reference64 AS c
          WHERE c._IDRRef = d._Fld9152RRef
      )
) AS v
WHERE d._Posted = 0x01
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
  );

CREATE TABLE #segments (
    segment_ref binary(16) NOT NULL,
    client_ref binary(16) NOT NULL
);

INSERT INTO #segments (segment_ref, client_ref)
SELECT DISTINCT r._Fld2879_RRRef, r._Fld2880_RRRef
FROM dbo._InfoRg2878 AS r
WHERE r._Fld2879_RTRef = 0x0000005B
  AND r._Fld2880_RTRef = 0x00000040;

CREATE INDEX IX_segments_ref_client ON #segments(segment_ref, client_ref);
CREATE INDEX IX_segments_client ON #segments(client_ref);

SELECT
    '01_reference91_active_like_metadata' AS probe,
    CONVERT(varchar(32), s._IDRRef, 2) AS segment_ref,
    s._Description AS segment_name,
    s._Marked AS marked,
    s._Folder AS folder_flag,
    s._Fld4329 AS segment_datetime_candidate,
    DATALENGTH(s._Fld4328) AS fld4328_bytes,
    LEN(COALESCE(s._Fld4330, N'')) AS fld4330_len,
    CONVERT(varchar(32), s._Fld4326RRef, 2) AS fld4326_ref,
    CONVERT(varchar(32), s._Fld4327RRef, 2) AS fld4327_ref,
    CONVERT(varchar(32), s._Fld4331RRef, 2) AS fld4331_ref,
    COUNT(DISTINCT CONVERT(varchar(32), seg.client_ref, 2)) AS segment_clients,
    COUNT(DISTINCT CASE WHEN af.client_ref IS NOT NULL THEN CONVERT(varchar(32), seg.client_ref, 2) END) AS intersects_active_filter
FROM dbo._Reference91 AS s
LEFT JOIN #segments AS seg
    ON s._IDRRef = seg.segment_ref
LEFT JOIN #active_filter AS af
    ON seg.client_ref = af.client_ref
WHERE s._Description LIKE N'%Актив%'
   OR s._Description LIKE N'%актив%'
   OR s._Description LIKE N'%членств%'
   OR s._Description LIKE N'%Членств%'
   OR s._IDRRef IN (
      0xB071000C29D830FD11F01B610376A948,
      0xB071000C29D830FD11F01B578762F7DA,
      0xB070000C29D830FD11F01ABFEF98B876,
      0xAF05000C29D830FD11EF086800375F01
   )
GROUP BY
    s._IDRRef,
    s._Description,
    s._Marked,
    s._Folder,
    s._Fld4329,
    DATALENGTH(s._Fld4328),
    LEN(COALESCE(s._Fld4330, N'')),
    s._Fld4326RRef,
    s._Fld4327RRef,
    s._Fld4331RRef
ORDER BY segment_clients DESC, segment_name;

SELECT TOP 30
    '02_segments_by_overlap_with_active_filter' AS probe,
    CONVERT(varchar(32), s._IDRRef, 2) AS segment_ref,
    s._Description AS segment_name,
    s._Fld4329 AS segment_datetime_candidate,
    COUNT(DISTINCT CONVERT(varchar(32), seg.client_ref, 2)) AS segment_clients,
    COUNT(DISTINCT CASE WHEN af.client_ref IS NOT NULL THEN CONVERT(varchar(32), seg.client_ref, 2) END) AS intersection_clients,
    COUNT(DISTINCT CASE WHEN af.client_ref IS NULL THEN CONVERT(varchar(32), seg.client_ref, 2) END) AS segment_without_active_filter,
    (SELECT COUNT_BIG(*) FROM #active_filter) -
        COUNT(DISTINCT CASE WHEN af.client_ref IS NOT NULL THEN CONVERT(varchar(32), seg.client_ref, 2) END) AS active_filter_without_segment
FROM dbo._Reference91 AS s
JOIN #segments AS seg
    ON s._IDRRef = seg.segment_ref
LEFT JOIN #active_filter AS af
    ON seg.client_ref = af.client_ref
GROUP BY s._IDRRef, s._Description, s._Fld4329
ORDER BY intersection_clients DESC, segment_clients DESC;

SELECT
    '03_target_segment_vs_same_size_segments' AS probe,
    CONVERT(varchar(32), s._IDRRef, 2) AS segment_ref,
    s._Description AS segment_name,
    s._Fld4329 AS segment_datetime_candidate,
    COUNT(DISTINCT CONVERT(varchar(32), seg.client_ref, 2)) AS segment_clients,
    COUNT(DISTINCT CASE WHEN target.client_ref IS NOT NULL THEN CONVERT(varchar(32), seg.client_ref, 2) END) AS intersection_with_target_active_segment,
    COUNT(DISTINCT CASE WHEN af.client_ref IS NOT NULL THEN CONVERT(varchar(32), seg.client_ref, 2) END) AS intersection_with_active_filter
FROM dbo._Reference91 AS s
JOIN #segments AS seg
    ON s._IDRRef = seg.segment_ref
LEFT JOIN #segments AS target
    ON target.segment_ref = 0xB071000C29D830FD11F01B610376A948
   AND seg.client_ref = target.client_ref
LEFT JOIN #active_filter AS af
    ON seg.client_ref = af.client_ref
WHERE s._IDRRef IN (
      0xB071000C29D830FD11F01B610376A948,
      0xB071000C29D830FD11F01B578762F7DA,
      0xB070000C29D830FD11F01ABFEF98B876,
      0xAF05000C29D830FD11EF086800375F01,
      0xB06F000C29D830FD11F019CB7103393E
   )
GROUP BY s._IDRRef, s._Description, s._Fld4329
ORDER BY segment_clients DESC;
GO
