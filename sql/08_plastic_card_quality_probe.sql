USE [FitnessRestored];
GO

SET NOCOUNT ON;

SELECT
    c.column_id,
    c.name AS column_name,
    t.name AS type_name,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable
FROM sys.columns AS c
JOIN sys.types AS t
  ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'dbo._Reference59')
ORDER BY c.column_id;

SELECT
    COUNT_BIG(*) AS rows,
    COUNT(DISTINCT _Fld3750_RRRef) AS clients,
    SUM(CASE WHEN _Marked = 0x00 THEN 1 ELSE 0 END) AS unmarked,
    SUM(CASE WHEN _Marked <> 0x00 THEN 1 ELSE 0 END) AS marked,
    SUM(CASE WHEN _Fld3752 = 0x01 THEN 1 ELSE 0 END) AS fld3752_01,
    SUM(CASE WHEN _Fld3757 = 0x01 THEN 1 ELSE 0 END) AS fld3757_01,
    SUM(CASE WHEN _Fld8852 = 0x01 THEN 1 ELSE 0 END) AS fld8852_01,
    SUM(CASE WHEN _Fld9523 = 0x01 THEN 1 ELSE 0 END) AS fld9523_01,
    SUM(CASE WHEN _Fld9524 = 0x01 THEN 1 ELSE 0 END) AS fld9524_01,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(_Fld8108)), N'') IS NOT NULL THEN 1 ELSE 0 END) AS nonempty_fld8108,
    SUM(CASE WHEN _Fld3755 <> 0 THEN 1 ELSE 0 END) AS nonzero_fld3755,
    SUM(CASE WHEN _Fld8109 <> 0 THEN 1 ELSE 0 END) AS nonzero_fld8109,
    SUM(CASE WHEN _Fld346 <> 0 THEN 1 ELSE 0 END) AS nonzero_fld346,
    MIN(_Fld3751) AS min_fld3751_raw,
    MAX(_Fld3751) AS max_fld3751_raw
FROM dbo._Reference59
WHERE _Fld3750_RTRef = 0x00000040;

SELECT
    CONVERT(varchar(32), _Fld3749RRef, 2) AS fld3749_ref,
    COUNT_BIG(*) AS rows
FROM dbo._Reference59
WHERE _Fld3750_RTRef = 0x00000040
GROUP BY CONVERT(varchar(32), _Fld3749RRef, 2)
ORDER BY rows DESC;

SELECT
    CONVERT(varchar(32), _Fld3754RRef, 2) AS fld3754_ref,
    COUNT_BIG(*) AS rows
FROM dbo._Reference59
WHERE _Fld3750_RTRef = 0x00000040
GROUP BY CONVERT(varchar(32), _Fld3754RRef, 2)
ORDER BY rows DESC;

SELECT
    _Fld3752 AS fld3752_raw,
    CONVERT(varchar(2), _Fld3752, 2) AS fld3752,
    COUNT_BIG(*) AS rows
FROM dbo._Reference59
WHERE _Fld3750_RTRef = 0x00000040
GROUP BY _Fld3752
ORDER BY rows DESC;

SELECT TOP (20)
    CONVERT(varchar(32), _Fld3750_RRRef, 2) AS client_ref,
    CONVERT(varchar(32), _IDRRef, 2) AS card_ref,
    _Code,
    _Description,
    _Fld3751,
    _Fld3753,
    _Fld3756,
    CONVERT(varchar(2), _Marked, 2) AS marked
FROM dbo._Reference59
WHERE _Fld3750_RTRef = 0x00000040
  AND _Fld3751 > '2026-04-29'
  AND _Fld3751 < '3000-01-01'
ORDER BY _Fld3751 DESC;
