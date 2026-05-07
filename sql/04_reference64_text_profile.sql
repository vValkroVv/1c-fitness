SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

SELECT
    column_name,
    non_empty_rows,
    email_like_rows,
    plus7_like_rows,
    min_sample,
    max_sample
FROM (
    SELECT '_Code' AS column_name, COUNT(NULLIF(LTRIM(RTRIM(_Code)), '')) AS non_empty_rows,
           SUM(CASE WHEN _Code LIKE N'%@%' THEN 1 ELSE 0 END) AS email_like_rows,
           SUM(CASE WHEN _Code LIKE N'%+7%' THEN 1 ELSE 0 END) AS plus7_like_rows,
           MIN(NULLIF(LTRIM(RTRIM(_Code)), '')) AS min_sample,
           MAX(NULLIF(LTRIM(RTRIM(_Code)), '')) AS max_sample
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Description', COUNT(NULLIF(LTRIM(RTRIM(_Description)), '')),
           SUM(CASE WHEN _Description LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Description LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Description)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Description)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3811', COUNT(NULLIF(LTRIM(RTRIM(_Fld3811)), '')),
           SUM(CASE WHEN _Fld3811 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3811 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3811)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3811)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3812', COUNT(NULLIF(LTRIM(RTRIM(_Fld3812)), '')),
           SUM(CASE WHEN _Fld3812 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3812 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3812)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3812)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3814_S', COUNT(NULLIF(LTRIM(RTRIM(_Fld3814_S)), '')),
           SUM(CASE WHEN _Fld3814_S LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3814_S LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3814_S)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3814_S)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld8954_S', COUNT(NULLIF(LTRIM(RTRIM(_Fld8954_S)), '')),
           SUM(CASE WHEN _Fld8954_S LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld8954_S LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld8954_S)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld8954_S)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3815', COUNT(NULLIF(LTRIM(RTRIM(_Fld3815)), '')),
           SUM(CASE WHEN _Fld3815 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3815 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(LEFT(NULLIF(LTRIM(RTRIM(_Fld3815)), ''), 180)),
           MAX(LEFT(NULLIF(LTRIM(RTRIM(_Fld3815)), ''), 180))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3816', COUNT(NULLIF(LTRIM(RTRIM(_Fld3816)), '')),
           SUM(CASE WHEN _Fld3816 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3816 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3816)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3816)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3818', COUNT(NULLIF(LTRIM(RTRIM(_Fld3818)), '')),
           SUM(CASE WHEN _Fld3818 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3818 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(LEFT(NULLIF(LTRIM(RTRIM(_Fld3818)), ''), 180)),
           MAX(LEFT(NULLIF(LTRIM(RTRIM(_Fld3818)), ''), 180))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3819', COUNT(NULLIF(LTRIM(RTRIM(_Fld3819)), '')),
           SUM(CASE WHEN _Fld3819 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3819 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3819)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3819)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3825', COUNT(NULLIF(LTRIM(RTRIM(_Fld3825)), '')),
           SUM(CASE WHEN _Fld3825 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3825 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(LEFT(NULLIF(LTRIM(RTRIM(_Fld3825)), ''), 180)),
           MAX(LEFT(NULLIF(LTRIM(RTRIM(_Fld3825)), ''), 180))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld5995', COUNT(NULLIF(LTRIM(RTRIM(_Fld5995)), '')),
           SUM(CASE WHEN _Fld5995 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld5995 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld5995)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld5995)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3828', COUNT(NULLIF(LTRIM(RTRIM(_Fld3828)), '')),
           SUM(CASE WHEN _Fld3828 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3828 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3828)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3828)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld8858', COUNT(NULLIF(LTRIM(RTRIM(_Fld8858)), '')),
           SUM(CASE WHEN _Fld8858 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld8858 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld8858)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld8858)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3829', COUNT(NULLIF(LTRIM(RTRIM(_Fld3829)), '')),
           SUM(CASE WHEN _Fld3829 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3829 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3829)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3829)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld8119', COUNT(NULLIF(LTRIM(RTRIM(_Fld8119)), '')),
           SUM(CASE WHEN _Fld8119 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld8119 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld8119)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld8119)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3843', COUNT(NULLIF(LTRIM(RTRIM(_Fld3843)), '')),
           SUM(CASE WHEN _Fld3843 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3843 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3843)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3843)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3832', COUNT(NULLIF(LTRIM(RTRIM(_Fld3832)), '')),
           SUM(CASE WHEN _Fld3832 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3832 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3832)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3832)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld8120', COUNT(NULLIF(LTRIM(RTRIM(_Fld8120)), '')),
           SUM(CASE WHEN _Fld8120 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld8120 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld8120)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld8120)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3835', COUNT(NULLIF(LTRIM(RTRIM(_Fld3835)), '')),
           SUM(CASE WHEN _Fld3835 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3835 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3835)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3835)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld8860', COUNT(NULLIF(LTRIM(RTRIM(_Fld8860)), '')),
           SUM(CASE WHEN _Fld8860 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld8860 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld8860)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld8860)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld8859', COUNT(NULLIF(LTRIM(RTRIM(_Fld8859)), '')),
           SUM(CASE WHEN _Fld8859 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld8859 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld8859)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld8859)), ''))
    FROM dbo._Reference64
    UNION ALL
    SELECT '_Fld3836', COUNT(NULLIF(LTRIM(RTRIM(_Fld3836)), '')),
           SUM(CASE WHEN _Fld3836 LIKE N'%@%' THEN 1 ELSE 0 END),
           SUM(CASE WHEN _Fld3836 LIKE N'%+7%' THEN 1 ELSE 0 END),
           MIN(NULLIF(LTRIM(RTRIM(_Fld3836)), '')),
           MAX(NULLIF(LTRIM(RTRIM(_Fld3836)), ''))
    FROM dbo._Reference64
) AS profile
ORDER BY non_empty_rows DESC, column_name;
GO

SELECT TOP 50
    _Code AS client_code,
    _Description AS client_fio,
    _Fld3812,
    _Fld3815,
    _Fld3816,
    _Fld3818,
    _Fld3825,
    _Fld3843,
    _Fld3832,
    _Fld8120,
    _Fld8860,
    _Fld8859
FROM dbo._Reference64
WHERE _Fld3812 LIKE N'%@%'
   OR _Fld3815 LIKE N'%@%'
   OR _Fld3816 LIKE N'%@%'
   OR _Fld3818 LIKE N'%@%'
   OR _Fld3825 LIKE N'%@%'
   OR _Fld3843 LIKE N'%@%'
   OR _Fld3832 LIKE N'%@%'
   OR _Fld8120 LIKE N'%@%'
   OR _Fld8860 LIKE N'%@%'
   OR _Fld8859 LIKE N'%@%';
GO
