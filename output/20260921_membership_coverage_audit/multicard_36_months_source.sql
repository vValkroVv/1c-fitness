-- Read-only source evidence for the sole observed 36-month Multicard product.
-- Run against each restored backup; no staging tables are used.
SELECT
    CONVERT(varchar(32), d._IDRRef, 2) AS subscription_ref,
    d._Number AS document_number,
    CASE WHEN d._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END AS sale_datetime,
    CONVERT(varchar(32), d._Fld1446RRef, 2) AS product_ref,
    p._Code AS product_code,
    p._Description AS subscription_name,
    d._Fld1481 AS doc_duration_value,
    CONVERT(varchar(2), d._Posted, 2) AS doc_posted,
    CONVERT(varchar(2), d._Marked, 2) AS doc_marked,
    r._Fld3063 AS raw_start_datetime,
    r._Fld3064 AS raw_end_datetime,
    CASE WHEN r._Fld3063 > '3000-01-01'
         THEN DATEADD(year, -2000, r._Fld3063) ELSE r._Fld3063 END AS start_datetime,
    CASE WHEN r._Fld3064 > '3000-01-01'
         THEN DATEADD(year, -2000, r._Fld3064) ELSE r._Fld3064 END AS end_datetime,
    DATEDIFF(day, r._Fld3063, r._Fld3064) + 1 AS duration_days,
    r._Fld3065 AS rg_duration_days,
    r._Fld3068 AS rg_freeze_days,
    r._Fld3070 AS rg_price
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference72 AS p ON p._IDRRef = d._Fld1446RRef
LEFT JOIN dbo._InfoRg3060 AS r ON r._Fld3061RRef = d._IDRRef
WHERE d._Fld1446RRef = 0xB179000C29D830FD11F0DD95636F8ABB
ORDER BY d._Date_Time, d._Number;
