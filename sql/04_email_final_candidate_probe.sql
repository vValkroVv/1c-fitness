USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';

IF OBJECT_ID('tempdb..#active_clients') IS NOT NULL DROP TABLE #active_clients;
IF OBJECT_ID('tempdb..#client_emails') IS NOT NULL DROP TABLE #client_emails;

WITH email_source_summary AS (
    SELECT
        N'_InfoRg5255' AS table_name,
        N'_Fld5256RRef -> _Reference64._IDRRef' AS client_join,
        N'_Fld5257' AS email_column,
        COUNT_BIG(*) AS source_rows,
        SUM(CASE WHEN _Fld5257 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%' THEN CONVERT(bigint, 1) ELSE 0 END) AS email_like_rows,
        COUNT(DISTINCT CASE WHEN _Fld5257 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%' THEN CONVERT(varchar(32), _Fld5256RRef, 2) END) AS distinct_clients_with_email,
        N'structured client-linked candidate' AS interpretation
    FROM dbo._InfoRg5255

    UNION ALL

    SELECT
        N'_InfoRg5867',
        N'_Fld5870_RTRef/_Fld5870_RRRef -> _Reference64',
        N'_Fld5869',
        COUNT_BIG(*),
        SUM(CASE WHEN _Fld5869 LIKE N'%@%' AND LOWER(_Fld5869) NOT LIKE N'%@c.us%' THEN CONVERT(bigint, 1) ELSE 0 END),
        COUNT(DISTINCT CASE WHEN _Fld5869 LIKE N'%@%' AND LOWER(_Fld5869) NOT LIKE N'%@c.us%' AND _Fld5870_RTRef = 0x00000040 THEN CONVERT(varchar(32), _Fld5870_RRRef, 2) END),
        N'not email: @ values are WhatsApp/JID @c.us'
    FROM dbo._InfoRg5867

    UNION ALL

    SELECT
        N'_InfoRg5226',
        N'_Fld5227_RTRef/_Fld5227_RRRef -> _Reference64',
        N'_Fld5231',
        COUNT_BIG(*),
        SUM(CASE WHEN _Fld5231 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%' THEN CONVERT(bigint, 1) ELSE 0 END),
        COUNT(DISTINCT CASE WHEN _Fld5231 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%' AND _Fld5227_RTRef = 0x00000040 THEN CONVERT(varchar(32), _Fld5227_RRRef, 2) END),
        N'notes/messages, not canonical email field'
    FROM dbo._InfoRg5226

    UNION ALL

    SELECT
        N'_InfoRg5211',
        N'_Fld5213_RTRef/_Fld5213_RRRef -> _Reference64',
        N'_Fld5222',
        COUNT_BIG(*),
        SUM(CASE WHEN _Fld5222 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%' THEN CONVERT(bigint, 1) ELSE 0 END),
        COUNT(DISTINCT CASE WHEN _Fld5222 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%' AND _Fld5213_RTRef = 0x00000040 THEN CONVERT(varchar(32), _Fld5213_RRRef, 2) END),
        N'notes/tasks, not canonical email field'
    FROM dbo._InfoRg5211
)
SELECT
    'email_source_summary' AS result_set,
    table_name,
    client_join,
    email_column,
    source_rows,
    email_like_rows,
    distinct_clients_with_email,
    interpretation
FROM email_source_summary
ORDER BY
    CASE WHEN table_name = N'_InfoRg5255' THEN 0 ELSE 1 END,
    email_like_rows DESC;

WITH active_raw AS (
    SELECT
        CASE
            WHEN d._Fld9152RRef <> 0x00000000000000000000000000000000
                 AND holder._IDRRef IS NOT NULL
                THEN d._Fld9152RRef
            WHEN d._Fld1447_RTRef = 0x00000040
                THEN d._Fld1447_RRRef
            ELSE NULL
        END AS client_ref
    FROM dbo._InfoRg3060 AS r
    JOIN dbo._Document163 AS d
      ON d._IDRRef = r._Fld3061RRef
    LEFT JOIN dbo._Reference64 AS holder
      ON holder._IDRRef = d._Fld9152RRef
    LEFT JOIN dbo._Reference72 AS product
      ON product._IDRRef = d._Fld1446RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND product._Description IS NOT NULL
      AND (
          LOWER(product._Description) LIKE N'%абонемент%'
          OR LOWER(product._Description) LIKE N'%мульти%'
          OR LOWER(product._Description) LIKE N'%ультра%'
          OR LOWER(product._Description) LIKE N'%членств%'
      )
      AND CAST(CASE WHEN r._Fld3063 > '3000-01-01' THEN r._Fld3063 ELSE d._Date_Time END AS date) <= @cutoff
      AND CAST(r._Fld3064 AS date) >= @cutoff
)
SELECT DISTINCT client_ref
INTO #active_clients
FROM active_raw
WHERE client_ref IS NOT NULL;

SELECT DISTINCT
    _Fld5256RRef AS client_ref,
    LOWER(LTRIM(RTRIM(_Fld5257))) AS email_value
INTO #client_emails
FROM dbo._InfoRg5255
WHERE _Fld5257 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%';

SELECT
    'email_active_coverage' AS result_set,
    COUNT(DISTINCT ac.client_ref) AS active_clients_2026_04_29,
    COUNT(DISTINCT ce.client_ref) AS active_clients_with_inforg5255_email,
    (SELECT COUNT(DISTINCT client_ref) FROM #client_emails) AS all_clients_with_inforg5255_email,
    (SELECT COUNT(*) FROM #client_emails) AS distinct_client_email_pairs
FROM #active_clients AS ac
LEFT JOIN #client_emails AS ce
  ON ce.client_ref = ac.client_ref;
GO
