USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

SELECT TOP 80
    'Reference64_email_like' AS probe,
    _Code AS client_code,
    _Description AS client_fio,
    _Fld3832 AS phone,
    _Fld3818 AS note
FROM dbo._Reference64
WHERE _Fld3818 LIKE N'%@%'
   OR _Fld3812 LIKE N'%@%'
   OR _Fld3819 LIKE N'%@%'
   OR _Fld3825 LIKE N'%@%'
   OR _Fld3829 LIKE N'%@%'
   OR _Fld3835 LIKE N'%@%';
GO

SELECT TOP 80
    'InfoRg5255_email_like' AS probe,
    _Fld5257,
    _Fld5258,
    _Fld5260,
    _Fld5261,
    _Fld5265,
    _Fld5267,
    _Fld7963,
    _Fld10093
FROM dbo._InfoRg5255
WHERE _Fld5257 LIKE N'%@%'
   OR _Fld5258 LIKE N'%@%'
   OR _Fld5260 LIKE N'%@%'
   OR _Fld5261 LIKE N'%@%'
   OR _Fld5265 LIKE N'%@%'
   OR _Fld5267 LIKE N'%@%'
   OR _Fld7963 LIKE N'%@%'
   OR _Fld10093 LIKE N'%@%';
GO

SELECT TOP 80
    'InfoRg5843_email_like' AS probe,
    _Period,
    _Fld5845,
    _Fld5846,
    _Fld8795,
    _Fld5849,
    _Fld5852,
    LEFT(_Fld5848, 500) AS fld5848,
    LEFT(_Fld9414, 500) AS fld9414,
    LEFT(_Fld5855, 500) AS fld5855,
    LEFT(_Fld5856, 500) AS fld5856,
    LEFT(_Fld5857, 500) AS fld5857,
    _Fld7926,
    _Fld10273
FROM dbo._InfoRg5843
WHERE _Fld5845 LIKE N'%@%'
   OR _Fld5846 LIKE N'%@%'
   OR _Fld8795 LIKE N'%@%'
   OR _Fld5849 LIKE N'%@%'
   OR _Fld5852 LIKE N'%@%'
   OR _Fld5848 LIKE N'%@%'
   OR _Fld9414 LIKE N'%@%'
   OR _Fld5855 LIKE N'%@%'
   OR _Fld5856 LIKE N'%@%'
   OR _Fld5857 LIKE N'%@%'
   OR _Fld7926 LIKE N'%@%'
   OR _Fld10273 LIKE N'%@%';
GO

SELECT
    'email_like_counts' AS probe,
    (SELECT COUNT_BIG(*) FROM dbo._Reference64 WHERE _Fld3818 LIKE N'%@%' OR _Fld3812 LIKE N'%@%' OR _Fld3819 LIKE N'%@%' OR _Fld3825 LIKE N'%@%' OR _Fld3829 LIKE N'%@%' OR _Fld3835 LIKE N'%@%') AS reference64_rows,
    (SELECT COUNT_BIG(*) FROM dbo._InfoRg5255 WHERE _Fld5257 LIKE N'%@%' OR _Fld5258 LIKE N'%@%' OR _Fld5260 LIKE N'%@%' OR _Fld5261 LIKE N'%@%' OR _Fld5265 LIKE N'%@%' OR _Fld5267 LIKE N'%@%' OR _Fld7963 LIKE N'%@%' OR _Fld10093 LIKE N'%@%') AS inforg5255_rows,
    (SELECT COUNT_BIG(*) FROM dbo._InfoRg5843 WHERE _Fld5845 LIKE N'%@%' OR _Fld5846 LIKE N'%@%' OR _Fld8795 LIKE N'%@%' OR _Fld5849 LIKE N'%@%' OR _Fld5852 LIKE N'%@%' OR _Fld5848 LIKE N'%@%' OR _Fld9414 LIKE N'%@%' OR _Fld5855 LIKE N'%@%' OR _Fld5856 LIKE N'%@%' OR _Fld5857 LIKE N'%@%' OR _Fld7926 LIKE N'%@%' OR _Fld10273 LIKE N'%@%') AS inforg5843_rows;
GO
