SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DROP TABLE IF EXISTS #target_services;
DROP TABLE IF EXISTS #target_refs;

CREATE TABLE #target_services (
    service_order int NOT NULL PRIMARY KEY,
    service_name nvarchar(300) COLLATE Cyrillic_General_CI_AS NOT NULL
);

INSERT INTO #target_services (service_order, service_name)
VALUES
(2, N'Йога (персональная тренировка) 12 пос. (группа до 4 человек)'),
(3, N'Йога (персональная тренировка) 12 пос. VIP (1 человек)'),
(4, N'Йога (персональная тренировка) 8 пос. (группа до 4 человек)'),
(5, N'Йога (персональная тренировка) 8 пос. VIP (1 человек)'),
(7, N'Сайкл для начинающих без клубной карты'),
(21, N'Пакет 10 ВИП (персональные тренировки)'),
(24, N'Пакет 4 (персональные тренировки)'),
(49, N'Утеря валика');

SELECT
    ts.service_order,
    ts.service_name,
    p._IDRRef AS product_ref_bin,
    CONVERT(varchar(32), p._IDRRef, 2) AS product_ref,
    p._Code AS product_code
INTO #target_refs
FROM #target_services AS ts
JOIN dbo._Reference72 AS p
  ON LOWER(LTRIM(RTRIM(p._Description))) = LOWER(LTRIM(RTRIM(ts.service_name))) COLLATE Cyrillic_General_CI_AS;

CREATE UNIQUE CLUSTERED INDEX IX_target_refs_product_ref_bin
    ON #target_refs(product_ref_bin);

PRINT '01 exact target products';
SELECT service_order, service_name, product_ref, product_code
FROM #target_refs
ORDER BY service_order;

PRINT '02 target hits in known sale/service sources';
SELECT
    tr.service_order,
    tr.service_name,
    COUNT(DISTINCT d163._IDRRef) AS document163_rows,
    COUNT(DISTINCT vt1137._Document154_IDRRef) AS document154_vt1137_docs,
    COUNT(vt1137._Document154_IDRRef) AS document154_vt1137_lines,
    COUNT(DISTINCT vt1181._Document154_IDRRef) AS document154_vt1181_docs,
    COUNT(vt1181._Document154_IDRRef) AS document154_vt1181_lines,
    COUNT(DISTINCT vt1162._Document154_IDRRef) AS document154_vt1162_docs,
    COUNT(vt1162._Document154_IDRRef) AS document154_vt1162_lines
FROM #target_refs AS tr
LEFT JOIN dbo._Document163 AS d163
  ON d163._Fld1446RRef = tr.product_ref_bin
 AND d163._Posted = 0x01
 AND d163._Marked = 0x00
LEFT JOIN dbo._Document154_VT1137 AS vt1137
  ON vt1137._Fld1146RRef = tr.product_ref_bin
LEFT JOIN dbo._Document154_VT1181 AS vt1181
  ON vt1181._Fld1185RRef = tr.product_ref_bin
LEFT JOIN dbo._Document154_VT1162 AS vt1162
  ON vt1162._Fld1168RRef = tr.product_ref_bin
  OR vt1162._Fld1167RRef = tr.product_ref_bin
  OR vt1162._Fld1166RRef = tr.product_ref_bin
GROUP BY tr.service_order, tr.service_name
ORDER BY tr.service_order;

PRINT '03 other direct target hits in Document154 header fields';
SELECT
    tr.service_order,
    tr.service_name,
    SUM(CASE WHEN d._Fld1136RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1136,
    SUM(CASE WHEN d._Fld1124RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1124,
    SUM(CASE WHEN d._Fld1117RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1117,
    SUM(CASE WHEN d._Fld1118RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1118,
    SUM(CASE WHEN d._Fld1120RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1120,
    SUM(CASE WHEN d._Fld1119RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1119,
    SUM(CASE WHEN d._Fld1115RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1115,
    SUM(CASE WHEN d._Fld1123RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1123,
    SUM(CASE WHEN d._Fld1116RRef = tr.product_ref_bin THEN 1 ELSE 0 END) AS fld1116
FROM #target_refs AS tr
CROSS JOIN dbo._Document154 AS d
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
GROUP BY tr.service_order, tr.service_name
ORDER BY tr.service_order;

