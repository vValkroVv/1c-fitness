SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

SELECT TOP 100
    seg._Description AS segment_name,
    CONVERT(varchar(32), seg._IDRRef, 2) AS segment_ref,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), r._Fld2880_RRRef, 2)) AS distinct_clients
FROM dbo._InfoRg2878 AS r
JOIN dbo._Reference91 AS seg
    ON r._Fld2879_RTRef = 0x0000005B
   AND r._Fld2879_RRRef = seg._IDRRef
WHERE r._Fld2880_RTRef = 0x00000040
GROUP BY seg._Description, CONVERT(varchar(32), seg._IDRRef, 2)
ORDER BY rows_count DESC;
GO

SELECT TOP 100
    seg._Description AS segment_name,
    CONVERT(varchar(32), seg._IDRRef, 2) AS segment_ref,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), r._Fld2880_RRRef, 2)) AS distinct_clients
FROM dbo._InfoRg2878 AS r
JOIN dbo._Reference91 AS seg
    ON r._Fld2879_RTRef = 0x0000005B
   AND r._Fld2879_RRRef = seg._IDRRef
WHERE r._Fld2880_RTRef = 0x00000040
  AND (
        seg._Description LIKE N'%Актив%'
        OR seg._Description LIKE N'%актив%'
        OR seg._Description LIKE N'%Оконч%'
        OR seg._Description LIKE N'%оконч%'
        OR seg._Description LIKE N'%Брон%'
        OR seg._Description LIKE N'%брон%'
        OR seg._Description LIKE N'%членств%'
        OR seg._Description LIKE N'%Членств%'
      )
GROUP BY seg._Description, CONVERT(varchar(32), seg._IDRRef, 2)
ORDER BY rows_count DESC;
GO
