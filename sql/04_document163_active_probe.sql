SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff datetime2 = '4026-04-29';

SELECT
    'Document163 active-ish summary' AS probe,
    COUNT_BIG(*) AS total_rows,
    SUM(CASE WHEN _Posted = 0x01 THEN 1 ELSE 0 END) AS posted_rows,
    SUM(CASE WHEN _Posted = 0x01 AND _Date_Time <= @cutoff AND _Fld1450 >= @cutoff THEN 1 ELSE 0 END) AS active_by_docdate_enddate,
    MIN(_Date_Time) AS min_doc_date,
    MAX(_Date_Time) AS max_doc_date,
    MIN(_Fld1450) AS min_end_candidate,
    MAX(_Fld1450) AS max_end_candidate
FROM dbo._Document163;
GO

DECLARE @cutoff datetime2 = '4026-04-29';

SELECT TOP 80
    'Document163 status groups' AS probe,
    CONVERT(varchar(2), _Posted, 2) AS posted,
    CONVERT(varchar(2), _Marked, 2) AS marked,
    _Fld1452 AS num_status_a,
    _Fld1454 AS num_status_b,
    _Fld1465 AS num_status_c,
    _Fld1481 AS num_status_d,
    COUNT_BIG(*) AS rows_count
FROM dbo._Document163
GROUP BY
    CONVERT(varchar(2), _Posted, 2),
    CONVERT(varchar(2), _Marked, 2),
    _Fld1452,
    _Fld1454,
    _Fld1465,
    _Fld1481
ORDER BY rows_count DESC;
GO

DECLARE @cutoff datetime2 = '4026-04-29';

SELECT TOP 80
    'Document163 active sample with product' AS probe,
    d._Number AS doc_number,
    d._Date_Time AS doc_date,
    p._Code AS client_code,
    p._Description AS client_fio,
    d._Fld1450 AS end_date_candidate,
    DATEDIFF(day, CAST(d._Date_Time AS date), CAST(d._Fld1450 AS date)) AS days_doc_to_end,
    d._Fld1452 AS num_status_a,
    d._Fld1454 AS num_status_b,
    d._Fld1465 AS num_status_c,
    d._Fld1481 AS num_status_d,
    n._Code AS product_code,
    n._Description AS product_name
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference64 AS p
    ON d._Fld1447_RTRef = 0x00000040
   AND d._Fld1447_RRRef = p._IDRRef
LEFT JOIN dbo._Reference72 AS n
    ON d._Fld1446RRef = n._IDRRef
WHERE d._Posted = 0x01
  AND d._Date_Time <= @cutoff
  AND d._Fld1450 >= @cutoff
ORDER BY d._Date_Time DESC;
GO

DECLARE @cutoff datetime2 = '4026-04-29';

SELECT TOP 80
    'Document163 active product distribution' AS probe,
    n._Code AS product_code,
    n._Description AS product_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), d._Fld1447_RRRef, 2)) AS distinct_clients,
    MIN(d._Date_Time) AS min_doc_date,
    MAX(d._Date_Time) AS max_doc_date,
    MIN(d._Fld1450) AS min_end_date,
    MAX(d._Fld1450) AS max_end_date
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference72 AS n
    ON d._Fld1446RRef = n._IDRRef
WHERE d._Posted = 0x01
  AND d._Date_Time <= @cutoff
  AND d._Fld1450 >= @cutoff
GROUP BY n._Code, n._Description
ORDER BY rows_count DESC;
GO
