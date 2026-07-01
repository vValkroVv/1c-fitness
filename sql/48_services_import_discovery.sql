SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

IF OBJECT_ID('tempdb..#service_list') IS NOT NULL
    DROP TABLE #service_list;

CREATE TABLE #service_list (
    service_order int NOT NULL PRIMARY KEY,
    service_name nvarchar(300) COLLATE Cyrillic_General_CI_AS NOT NULL,
    service_name_norm AS LOWER(LTRIM(RTRIM(service_name)))
);

INSERT INTO #service_list (service_order, service_name)
VALUES
(1, N'Step-1 разовое посещение без клубной карты'),
(2, N'Йога (персональная тренировка) 12 пос. (группа до 4 человек)'),
(3, N'Йога (персональная тренировка) 12 пос. VIP (1 человек)'),
(4, N'Йога (персональная тренировка) 8 пос. (группа до 4 человек)'),
(5, N'Йога (персональная тренировка) 8 пос. VIP (1 человек)'),
(6, N'Йога в гамаках(при наличии клубной карты)'),
(7, N'Сайкл для начинающих без клубной карты'),
(8, N'Сайкл для начинающих при наличии клубной карты'),
(9, N'Сайкл разовое без клубной карты'),
(10, N'Сайкл разовое при наличии клубной карты'),
(11, N'Стрип-пластика'),
(12, N'Восстановление пластиковой карты'),
(13, N'Доплата'),
(14, N'Доплата до года'),
(15, N'Заморозка абонемента 1 месяц'),
(16, N'Заморозка абонемента 14 дней'),
(17, N'Заморозка абонемента 90 дней'),
(18, N'Перевод из клуба в клуб'),
(19, N'Переоформление платное абонемента на фитнес'),
(20, N'Пакет 10 (персональные тренировки)'),
(21, N'Пакет 10 ВИП (персональные тренировки)'),
(22, N'Пакет 12 (персональные тренировки)'),
(23, N'Пакет 12 ВИП (персональные тренировки)'),
(24, N'Пакет 4 (персональные тренировки)'),
(25, N'Пакет 8'),
(26, N'Пакет 8 ВИП'),
(27, N'Пробная П/Т'),
(28, N'Разовая'),
(29, N'Разовая ВИП'),
(30, N'Субаренда 1 посещение'),
(31, N'Подарочный сертификат на сумму 1000'),
(32, N'Подарочный сертификат на сумму 1500'),
(33, N'Подарочный сертификат на сумму 2000'),
(34, N'Подарочный сертификат на сумму 3000'),
(35, N'Подарочный сертификат на сумму 5000'),
(36, N'Разовое посещение'),
(37, N'Медленный класс (10 посещений) двойное предложение'),
(38, N'Пакет 6'),
(39, N'Солярий 1 минута'),
(40, N'Утеря номерка от гардероба'),
(41, N'Аренда рекламного места'),
(42, N'Солярий 5 минут'),
(43, N'Утеря магнитного ключа-метки'),
(44, N'Медленный класс (персональные тренировки)'),
(45, N'Утеря ключа от шкафчика'),
(46, N'Step-1 разовое посещение при наличии клубной карты'),
(47, N'Йога (персональная тренировка) VIP'),
(48, N'Утеря манжеты'),
(49, N'Утеря валика'),
(50, N'Персональная тренировка VIP'),
(51, N'Аренда рекламного места А2');

PRINT '01 service list size';
SELECT COUNT(*) AS service_names FROM #service_list;

PRINT '02 exact product matches in _Reference72';
SELECT
    sl.service_order,
    sl.service_name,
    COUNT(p._IDRRef) AS exact_product_refs,
    STRING_AGG(CONVERT(varchar(32), p._IDRRef, 2), ';') AS product_refs,
    STRING_AGG(p._Code, ';') AS product_codes
FROM #service_list AS sl
LEFT JOIN dbo._Reference72 AS p
  ON LOWER(LTRIM(RTRIM(p._Description))) = sl.service_name_norm
GROUP BY sl.service_order, sl.service_name
ORDER BY sl.service_order;

PRINT '03 current stg_products coverage';
SELECT
    sl.service_order,
    sl.service_name,
    sp.product_ref,
    sp.product_code,
    sp.product_class,
    sp.observed_sale_rows,
    sp.observed_subscription_rows,
    sp.observed_clients,
    sp.min_duration_days,
    sp.max_duration_days,
    sp.avg_duration_days
FROM #service_list AS sl
LEFT JOIN fitbase_part2.stg_products AS sp
  ON LOWER(LTRIM(RTRIM(sp.product_name))) = sl.service_name_norm
ORDER BY sl.service_order, sp.product_ref;

PRINT '04 current stg_sales_all rows before cutoff by service';
SELECT
    sl.service_order,
    sl.service_name,
    COUNT(s.sale_ref) AS sale_rows_before_cutoff,
    COUNT(DISTINCT s.client_ref) AS distinct_clients_before_cutoff,
    SUM(CASE WHEN s.sale_datetime <= @cutoff_at THEN 1 ELSE 0 END) AS rows_on_cutoff,
    MIN(s.sale_datetime) AS first_sale_datetime,
    MAX(s.sale_datetime) AS last_sale_datetime
FROM #service_list AS sl
LEFT JOIN fitbase_part2.stg_sales_all AS s
  ON LOWER(LTRIM(RTRIM(s.product_name))) = sl.service_name_norm
 AND s.sale_datetime <= @cutoff_at
GROUP BY sl.service_order, sl.service_name
ORDER BY sl.service_order;

PRINT '05 top exact product refs in Document163';
SELECT
    sl.service_order,
    sl.service_name,
    COUNT(d._IDRRef) AS document163_rows,
    COUNT(DISTINCT COALESCE(holder._IDRRef, payer._IDRRef)) AS distinct_clients,
    MIN(CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END) AS first_doc_datetime,
    MAX(CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END) AS last_doc_datetime
FROM #service_list AS sl
JOIN dbo._Reference72 AS p
  ON LOWER(LTRIM(RTRIM(p._Description))) = sl.service_name_norm
LEFT JOIN dbo._Document163 AS d
  ON d._Fld1446RRef = p._IDRRef
 AND d._Posted = 0x01
 AND d._Marked = 0x00
 AND CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END <= @cutoff_at
LEFT JOIN dbo._Reference64 AS holder
  ON holder._IDRRef = d._Fld9152RRef
LEFT JOIN dbo._Reference64 AS payer
  ON payer._IDRRef = d._Fld1447_RRRef
 AND d._Fld1447_RTRef = 0x00000040
GROUP BY sl.service_order, sl.service_name
ORDER BY sl.service_order;

PRINT '06 Document154_VT1137 columns containing 51 service product refs';
WITH service_refs AS (
    SELECT p._IDRRef AS product_ref
    FROM #service_list AS sl
    JOIN dbo._Reference72 AS p
      ON LOWER(LTRIM(RTRIM(p._Description))) = sl.service_name_norm
)
SELECT '_Fld1139RRef' AS column_name, COUNT_BIG(*) AS matching_rows
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1139RRef
UNION ALL
SELECT '_Fld1146RRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1146RRef
UNION ALL
SELECT '_Fld1147RRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1147RRef
UNION ALL
SELECT '_Fld1148_RRRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1148_RRRef
UNION ALL
SELECT '_Fld1149_RRRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1149_RRRef
UNION ALL
SELECT '_Fld1152RRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1152RRef
UNION ALL
SELECT '_Fld1151RRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1151RRef
UNION ALL
SELECT '_Fld1153RRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1153RRef
UNION ALL
SELECT '_Fld1159RRef', COUNT_BIG(*)
FROM dbo._Document154_VT1137 AS l
JOIN service_refs AS r ON r.product_ref = l._Fld1159RRef
ORDER BY matching_rows DESC, column_name;

PRINT '07 product-like columns in user tables';
SELECT
    SCHEMA_NAME(t.schema_id) AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    ty.name AS type_name,
    c.max_length
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
WHERE t.is_ms_shipped = 0
  AND ty.name IN (N'binary', N'varbinary', N'uniqueidentifier')
  AND (
      c.name LIKE N'%RRef'
      OR c.name LIKE N'%RRRef'
      OR c.name LIKE N'%Fld%'
  )
  AND (
      t.name LIKE N'_Document%'
      OR t.name LIKE N'_InfoRg%'
      OR t.name LIKE N'_AccumRg%'
  )
ORDER BY t.name, c.column_id;
