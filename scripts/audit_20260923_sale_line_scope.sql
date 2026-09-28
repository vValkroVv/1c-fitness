SET NOCOUNT ON;
WITH recent_lines AS (
    SELECT
        l._Fld1146RRef AS product_ref,
        l._Fld1148_RTRef AS linked_type,
        p._Description AS product_name,
        p._Code AS product_code,
        l._Fld1154 AS line_amount
    FROM dbo._Document154 AS d
    JOIN dbo._Document154_VT1137 AS l
      ON l._Document154_IDRRef = d._IDRRef
    LEFT JOIN dbo._Reference72 AS p
      ON p._IDRRef = l._Fld1146RRef
    WHERE d._Posted = 0x01 AND d._Marked = 0x00
      AND (CASE WHEN d._Date_Time > '3000-01-01'
                THEN DATEADD(year, -2000, d._Date_Time)
                ELSE d._Date_Time END) > '2026-09-20 20:12:12'
      AND (CASE WHEN d._Date_Time > '3000-01-01'
                THEN DATEADD(year, -2000, d._Date_Time)
                ELSE d._Date_Time END) <= '2026-09-23 23:36:39'
)
SELECT CONVERT(varchar(32), product_ref, 2),
       CONVERT(varchar(8), linked_type, 2),
       COALESCE(product_code, N''),
       COALESCE(REPLACE(REPLACE(product_name, CHAR(9), N' '), CHAR(10), N' '), N''),
       COUNT_BIG(*),
       SUM(CAST(COALESCE(line_amount, 0) AS decimal(15, 2)))
FROM recent_lines
GROUP BY product_ref, linked_type, product_code, product_name
ORDER BY COUNT_BIG(*) DESC, product_name;
