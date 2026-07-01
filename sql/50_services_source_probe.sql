SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

PRINT '01 sample Document154_VT1137 service lines';
SELECT TOP (80)
    p._Description AS product_name,
    CONVERT(varchar(32), l._Document154_IDRRef, 2) AS sale_doc_ref,
    d._Number AS sale_number,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS sale_datetime,
    d._Posted,
    d._Marked,
    CONVERT(varchar(8), d._Fld1131_RTRef, 2) AS header_client_rt,
    CONVERT(varchar(32), d._Fld1131_RRRef, 2) AS header_client_ref,
    c._Code AS header_client_id,
    c._Description AS header_client_fio,
    l._LineNo1138,
    l._Fld10484,
    l._Fld10224,
    l._Fld10225,
    l._Fld10485,
    l._Fld1140,
    l._Fld1141,
    CONVERT(varchar(32), l._Fld1142, 2) AS fld1142,
    CONVERT(varchar(32), l._Fld1143, 2) AS fld1143,
    l._Fld1144,
    l._Fld1145,
    l._Fld9149,
    CONVERT(varchar(32), l._Fld1148_RRRef, 2) AS fld1148_rr,
    CONVERT(varchar(8), l._Fld1148_RTRef, 2) AS fld1148_rt,
    CONVERT(varchar(32), l._Fld1149_RRRef, 2) AS fld1149_rr,
    CONVERT(varchar(8), l._Fld1149_RTRef, 2) AS fld1149_rt,
    l._Fld1154,
    l._Fld1155,
    l._Fld1156,
    l._Fld1157,
    l._Fld1158,
    l._Fld1160
FROM dbo._Document154_VT1137 AS l
JOIN dbo._Reference72 AS p
  ON p._IDRRef = l._Fld1146RRef
JOIN dbo._Document154 AS d
  ON d._IDRRef = l._Document154_IDRRef
LEFT JOIN dbo._Reference64 AS c
  ON c._IDRRef = d._Fld1131_RRRef
 AND d._Fld1131_RTRef = 0x00000040
WHERE p._Description IN (
    N'Пакет 12 (персональные тренировки)',
    N'Пакет 8',
    N'Доплата',
    N'Солярий 1 минута',
    N'Восстановление пластиковой карты',
    N'Подарочный сертификат на сумму 1000',
    N'Разовая',
    N'Разовое посещение'
)
  AND d._Posted = 0x01
  AND d._Marked = 0x00
  AND CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
      END <= @cutoff_at
ORDER BY sale_datetime DESC, l._LineNo1138;

PRINT '02 service line coverage in Document154_VT1137 by 51 names';
WITH service_list AS (
    SELECT *
    FROM (VALUES
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
        (51, N'Аренда рекламного места А2')
    ) AS v(service_order, service_name)
),
matched_products AS (
    SELECT
        sl.service_order,
        sl.service_name,
        p._IDRRef AS product_ref
    FROM service_list AS sl
    JOIN dbo._Reference72 AS p
      ON LOWER(LTRIM(RTRIM(p._Description))) = LOWER(LTRIM(RTRIM(sl.service_name))) COLLATE Cyrillic_General_CI_AS
),
sales AS (
    SELECT
        mp.service_order,
        mp.service_name,
        l._Document154_IDRRef,
        d._Fld1131_RRRef AS client_ref_bin,
        c._Code AS client_id,
        CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END AS sale_datetime
    FROM matched_products AS mp
    JOIN dbo._Document154_VT1137 AS l
      ON l._Fld1146RRef = mp.product_ref
    JOIN dbo._Document154 AS d
      ON d._IDRRef = l._Document154_IDRRef
    LEFT JOIN dbo._Reference64 AS c
      ON c._IDRRef = d._Fld1131_RRRef
     AND d._Fld1131_RTRef = 0x00000040
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
          END <= @cutoff_at
)
SELECT
    sl.service_order,
    sl.service_name,
    COUNT(s._Document154_IDRRef) AS line_rows_before_cutoff,
    COUNT(DISTINCT s.client_id) AS distinct_clients_before_cutoff,
    MIN(s.sale_datetime) AS first_sale_datetime,
    MAX(s.sale_datetime) AS last_sale_datetime
FROM service_list AS sl
LEFT JOIN sales AS s
  ON s.service_order = sl.service_order
GROUP BY sl.service_order, sl.service_name
ORDER BY sl.service_order;

