SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

SELECT
    'AccumRg3305 rt3308' AS probe,
    CONVERT(varchar(8), _Fld3308_RTRef, 2) AS rt,
    COUNT_BIG(*) AS rows_count
FROM dbo._AccumRg3305
GROUP BY CONVERT(varchar(8), _Fld3308_RTRef, 2)
ORDER BY rows_count DESC;
GO

SELECT TOP 80
    'AccumRg3305 sample' AS probe,
    r._Period,
    CONVERT(varchar(8), r._RecorderTRef, 2) AS recorder_tref,
    CONVERT(varchar(32), r._RecorderRRef, 2) AS recorder_ref,
    r._RecordKind,
    CONVERT(varchar(2), r._Active, 2) AS active,
    p._Code AS client_code,
    p._Description AS client_fio,
    CONVERT(varchar(8), r._Fld3308_RTRef, 2) AS rt3308,
    CONVERT(varchar(32), r._Fld3308_RRRef, 2) AS rr3308,
    r._Fld3311 AS num_a,
    r._Fld3312 AS num_b,
    r._Fld9180 AS num_c
FROM dbo._AccumRg3305 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld3307_RTRef = 0x00000040
   AND r._Fld3307_RRRef = p._IDRRef
ORDER BY r._Period DESC;
GO

SELECT TOP 80
    'AccumRgT3318 balance sample' AS probe,
    r._Period,
    p._Code AS client_code,
    p._Description AS client_fio,
    CONVERT(varchar(8), r._Fld3308_RTRef, 2) AS rt3308,
    CONVERT(varchar(32), r._Fld3308_RRRef, 2) AS rr3308,
    r._Fld3311 AS num_a,
    r._Fld3312 AS num_b,
    r._Fld9180 AS num_c
FROM dbo._AccumRgT3318 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld3307_RTRef = 0x00000040
   AND r._Fld3307_RRRef = p._IDRRef
ORDER BY r._Period DESC;
GO

SELECT TOP 80
    'AccumRgT3318 positive balance groups' AS probe,
    CONVERT(varchar(8), r._Fld3308_RTRef, 2) AS rt3308,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), r._Fld3307_RRRef, 2)) AS distinct_clients,
    SUM(CASE WHEN r._Fld3311 > 0 OR r._Fld3312 > 0 OR r._Fld9180 > 0 THEN 1 ELSE 0 END) AS positive_rows,
    MIN(r._Period) AS min_period,
    MAX(r._Period) AS max_period
FROM dbo._AccumRgT3318 AS r
WHERE r._Fld3307_RTRef = 0x00000040
GROUP BY CONVERT(varchar(8), r._Fld3308_RTRef, 2)
ORDER BY rows_count DESC;
GO
