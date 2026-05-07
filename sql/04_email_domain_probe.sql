USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

WITH src AS (
    SELECT N'_InfoRg5867._Fld5869' AS source, LOWER(LTRIM(RTRIM(_Fld5869))) AS v
    FROM dbo._InfoRg5867
    WHERE _Fld5869 LIKE N'%@%'

    UNION ALL
    SELECT N'_InfoRg5255._Fld5257', LOWER(LTRIM(RTRIM(_Fld5257)))
    FROM dbo._InfoRg5255
    WHERE _Fld5257 LIKE N'%@%'

    UNION ALL
    SELECT N'_InfoRg5255._Fld5265', LOWER(LTRIM(RTRIM(_Fld5265)))
    FROM dbo._InfoRg5255
    WHERE _Fld5265 LIKE N'%@%'

    UNION ALL
    SELECT N'_InfoRg5226._Fld5231', LOWER(LTRIM(RTRIM(_Fld5231)))
    FROM dbo._InfoRg5226
    WHERE _Fld5231 LIKE N'%@%'

    UNION ALL
    SELECT N'_InfoRg5211._Fld5222', LOWER(LTRIM(RTRIM(_Fld5222)))
    FROM dbo._InfoRg5211
    WHERE _Fld5222 LIKE N'%@%'
),
after_at AS (
    SELECT
        source,
        v,
        SUBSTRING(v, CHARINDEX(N'@', v) + 1, 4000) AS tail
    FROM src
    WHERE CHARINDEX(N'@', v) > 0
),
domains AS (
    SELECT
        source,
        CASE
            WHEN PATINDEX(N'%[^a-z0-9.-]%', tail + N' ') > 1
                THEN LEFT(tail, PATINDEX(N'%[^a-z0-9.-]%', tail + N' ') - 1)
            ELSE tail
        END AS domain
    FROM after_at
)
SELECT TOP 200
    source,
    domain,
    COUNT_BIG(*) AS rows
FROM domains
GROUP BY source, domain
ORDER BY source, rows DESC, domain;
GO
