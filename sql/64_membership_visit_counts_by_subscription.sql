SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    CONVERT(varchar(32), m._IDRRef, 2) AS subscription_ref,
    m._Number AS contract_id,
    COUNT_BIG(*) AS visit_docs,
    MIN(CASE
            WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time)
            ELSE v._Date_Time
        END) AS first_visit,
    MAX(CASE
            WHEN v._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, v._Date_Time)
            ELSE v._Date_Time
        END) AS last_visit
FROM dbo._Document150 AS v
JOIN dbo._Document163 AS m
  ON v._Fld991_RTRef = 0x000000A3
 AND m._IDRRef = v._Fld991_RRRef
WHERE v._Posted = 0x01
  AND v._Marked = 0x00
GROUP BY
    CONVERT(varchar(32), m._IDRRef, 2),
    m._Number
ORDER BY
    m._Number;
