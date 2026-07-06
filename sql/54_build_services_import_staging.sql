SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_date date = CONVERT(date, @cutoff_at);

IF OBJECT_ID(N'fitbase_part2.services_import_facts', N'U') IS NOT NULL
    DROP TABLE fitbase_part2.services_import_facts;

DROP TABLE IF EXISTS #service_list;
DROP TABLE IF EXISTS #service_products;
DROP TABLE IF EXISTS #service_sales;
DROP TABLE IF EXISTS #linked_service_docs;
DROP TABLE IF EXISTS #balance_by_doc;
DROP TABLE IF EXISTS #sale_docs;
DROP TABLE IF EXISTS #payments_by_sale_doc;

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

SELECT
    sl.service_order,
    sl.service_name,
    p._IDRRef AS product_ref_bin,
    CONVERT(varchar(32), p._IDRRef, 2) AS product_ref,
    p._Code AS product_code,
    p._Description AS product_name
INTO #service_products
FROM #service_list AS sl
JOIN dbo._Reference72 AS p
  ON LOWER(LTRIM(RTRIM(p._Description))) = sl.service_name_norm;

CREATE INDEX IX_tmp_service_products_product_ref
    ON #service_products(product_ref_bin);

SELECT
    sp.service_order,
    sp.service_name,
    sp.product_ref,
    sp.product_code,
    sp.product_name,
    d._IDRRef AS sale_doc_ref_bin,
    CONVERT(varchar(32), d._IDRRef, 2) AS sale_doc_ref,
    d._Number AS sale_number,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS sale_datetime,
    CONVERT(date, CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END) AS sale_date,
    d._Fld1119RRef AS sale_client_ref_bin,
    CONVERT(varchar(32), d._Fld1119RRef, 2) AS sale_client_ref,
    sale_client._Code AS sale_client_id,
    sale_client._Description AS sale_client_fio,
    sale_client._Fld3832 AS sale_client_phone,
    org._Description AS sale_branch_raw,
    CASE
        WHEN org._Description LIKE N'%Гоголев%' THEN N'Фитнес Империя (Гоголевский)'
        WHEN org._Description LIKE N'%Столиц%' THEN N'Фитнес Империя (Столица)'
        WHEN org._Description LIKE N'%Карель%' THEN N'Фитнес Империя (Ровио)'
        WHEN org._Description LIKE N'%Ровио%' THEN N'Фитнес Империя (Ровио)'
        WHEN org._Description LIKE N'%Промышлен%' THEN N'Фитнес Империя (Промышленная)'
        ELSE NULL
    END AS sale_branch,
    CASE
        WHEN org._Description IS NOT NULL THEN N'dbo._Document154._Fld1116RRef -> dbo._Reference105'
        ELSE NULL
    END AS sale_branch_source,
    l._LineNo1138 AS sale_line_no,
    CASE
        WHEN l._Fld1148_RTRef = 0x000000A3 THEN l._Fld1148_RRRef
        ELSE NULL
    END AS linked_service_doc_ref_bin,
    CASE
        WHEN l._Fld1148_RTRef = 0x000000A3 THEN CONVERT(varchar(32), l._Fld1148_RRRef, 2)
        ELSE NULL
    END AS linked_service_doc_ref,
    CONVERT(varchar(8), l._Fld1148_RTRef, 2) AS linked_object_rtref,
    CAST(CASE
        WHEN COALESCE(l._Fld1144, 0) > 0 THEN l._Fld1144
        WHEN COALESCE(l._Fld1145, 0) > 0 THEN l._Fld1145
        ELSE 1
    END AS decimal(15, 3)) AS line_quantity,
    CAST(CASE
        WHEN COALESCE(l._Fld1154, 0) > 0 THEN l._Fld1154
        WHEN COALESCE(l._Fld1140, 0) > 0 THEN l._Fld1140
        WHEN COALESCE(l._Fld1160, 0) > 0
            THEN l._Fld1160 * CASE
                WHEN COALESCE(l._Fld1144, 0) > 0 THEN l._Fld1144
                WHEN COALESCE(l._Fld1145, 0) > 0 THEN l._Fld1145
                ELSE 1
            END
        ELSE 0
    END AS decimal(15, 2)) AS line_total_amount,
    CAST(CASE
        WHEN COALESCE(l._Fld1160, 0) > 0 THEN l._Fld1160
        WHEN COALESCE(l._Fld1144, 0) > 0 AND COALESCE(l._Fld1154, l._Fld1140, 0) > 0 THEN COALESCE(l._Fld1154, l._Fld1140) / l._Fld1144
        WHEN COALESCE(l._Fld1145, 0) > 0 AND COALESCE(l._Fld1154, l._Fld1140, 0) > 0 THEN COALESCE(l._Fld1154, l._Fld1140) / l._Fld1145
        WHEN COALESCE(l._Fld1154, 0) > 0 THEN l._Fld1154
        WHEN COALESCE(l._Fld1140, 0) > 0 THEN l._Fld1140
        ELSE 0
    END AS decimal(15, 2)) AS unit_price,
    CAST(COALESCE(l._Fld1156, 0) AS decimal(15, 2)) AS vat_amount,
    l._Fld9149 AS line_comment,
    sd._Number AS service_doc_number,
    CASE
        WHEN sd._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, sd._Date_Time)
        ELSE sd._Date_Time
    END AS service_doc_datetime,
    CONVERT(varchar(32), sd._Fld9152RRef, 2) AS service_doc_holder_ref,
    holder._Code AS service_doc_holder_id,
    holder._Description AS service_doc_holder_fio,
    CASE
        WHEN sd._Fld1450 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, sd._Fld1450))
        WHEN sd._Fld1450 > '1900-01-01' THEN CONVERT(date, sd._Fld1450)
        ELSE NULL
    END AS service_start_date_raw,
    CASE
        WHEN sd._Fld1482 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, sd._Fld1482))
        WHEN sd._Fld1482 > '1900-01-01' THEN CONVERT(date, sd._Fld1482)
        ELSE NULL
    END AS service_end_date_raw,
    CAST(COALESCE(sd._Fld1481, 0) AS decimal(15, 2)) AS service_doc_duration_value,
    sd._Posted AS service_doc_posted,
    sd._Marked AS service_doc_marked,
    CAST(COALESCE(rg._Fld3065, 0) AS decimal(15, 2)) AS rg_duration_days,
    CAST(COALESCE(rg._Fld3070, 0) AS decimal(15, 2)) AS rg_price,
    CAST(COALESCE(rg._Fld3072, 0) AS decimal(15, 2)) AS rg_paid_candidate,
    CAST(COALESCE(rg._Fld5963, 0) AS decimal(15, 2)) AS rg_payment_count_candidate,
    CAST(COALESCE(rg._Fld8007, 0) AS decimal(15, 2)) AS rg_visits_candidate_8007,
    CAST(COALESCE(rg._Fld8008, 0) AS decimal(15, 2)) AS rg_visits_candidate_8008,
    CAST(COALESCE(rg._Fld8009, 0) AS decimal(15, 2)) AS rg_visits_candidate_8009
INTO #service_sales
FROM #service_products AS sp
JOIN dbo._Document154_VT1137 AS l
  ON l._Fld1146RRef = sp.product_ref_bin
JOIN dbo._Document154 AS d
  ON d._IDRRef = l._Document154_IDRRef
LEFT JOIN dbo._Reference64 AS sale_client
  ON sale_client._IDRRef = d._Fld1119RRef
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = d._Fld1116RRef
LEFT JOIN dbo._Document163 AS sd
  ON sd._IDRRef = CASE WHEN l._Fld1148_RTRef = 0x000000A3 THEN l._Fld1148_RRRef ELSE NULL END
LEFT JOIN dbo._Reference64 AS holder
  ON holder._IDRRef = sd._Fld9152RRef
LEFT JOIN dbo._InfoRg3060 AS rg
  ON rg._Fld3061RRef = sd._IDRRef
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
  AND CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
      END <= @cutoff_at;

CREATE INDEX IX_tmp_service_sales_sale_doc
    ON #service_sales(sale_doc_ref_bin);
CREATE INDEX IX_tmp_service_sales_linked_doc
    ON #service_sales(linked_service_doc_ref_bin);
CREATE INDEX IX_tmp_service_sales_name
    ON #service_sales(service_order, service_name);

SELECT DISTINCT linked_service_doc_ref_bin
INTO #linked_service_docs
FROM #service_sales
WHERE linked_service_doc_ref_bin IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_linked_service_docs
    ON #linked_service_docs(linked_service_doc_ref_bin);

SELECT
    r._Fld3337_RRRef AS linked_service_doc_ref_bin,
    SUM(CASE WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS receipt_qty,
    SUM(CASE WHEN r._RecordKind = 1 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS expense_qty,
    SUM(CASE
        WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3))
        WHEN r._RecordKind = 1 THEN -CAST(r._Fld3339 AS decimal(15, 3))
        ELSE 0
    END) AS signed_balance,
    COUNT(*) AS movement_rows,
    SUM(CASE WHEN r._RecordKind = 0 THEN 1 ELSE 0 END) AS receipt_rows,
    SUM(CASE WHEN r._RecordKind = 1 THEN 1 ELSE 0 END) AS expense_rows
INTO #balance_by_doc
FROM dbo._AccumRg3336 AS r
JOIN #linked_service_docs AS lsd
  ON lsd.linked_service_doc_ref_bin = r._Fld3337_RRRef
WHERE r._Active = 0x01
  AND r._Fld3339 <> 0
  AND DATEADD(year, -2000, r._Period) <= @cutoff_at
GROUP BY r._Fld3337_RRRef;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_balance_by_doc
    ON #balance_by_doc(linked_service_doc_ref_bin);

SELECT DISTINCT sale_doc_ref_bin
INTO #sale_docs
FROM #service_sales;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_sale_docs
    ON #sale_docs(sale_doc_ref_bin);

WITH payment_candidates AS (
    SELECT
        pl._Fld1087_RRRef AS sale_doc_ref_bin,
        CONVERT(varchar(32), p._IDRRef, 2) AS payment_ref,
        CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
        END AS payment_datetime,
        CAST(p._Fld1080 AS decimal(15, 2)) AS payment_amount,
        pm._Description AS payment_method,
        op._Description AS payment_operation,
        N'direct_doc152_vt1083_doc154' AS payment_match_source,
        ROW_NUMBER() OVER (
            PARTITION BY pl._Fld1087_RRRef
            ORDER BY
                CASE
                    WHEN pm._Description IS NULL OR LTRIM(RTRIM(pm._Description)) = N'' THEN 3
                    WHEN LOWER(pm._Description) LIKE N'%сбп%'
                      OR LOWER(pm._Description) LIKE N'%сбпр%'
                      OR LOWER(pm._Description) LIKE N'%налич%'
                      OR LOWER(pm._Description) LIKE N'%эквайр%'
                      OR LOWER(pm._Description) LIKE N'%банк%'
                      OR LOWER(pm._Description) LIKE N'%безнал%'
                      OR LOWER(pm._Description) LIKE N'%терминал%'
                      OR LOWER(pm._Description) LIKE N'%карта%'
                      OR LOWER(pm._Description) LIKE N'%р/с%' THEN 0
                    ELSE 1
                END,
                CASE
                    WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
                    ELSE p._Date_Time
                END DESC,
                p._IDRRef DESC
        ) AS rn
    FROM #sale_docs AS sd
    JOIN dbo._Document152_VT1083 AS pl
      ON pl._Fld1087_RTRef = 0x0000009A
     AND pl._Fld1087_RRRef = sd.sale_doc_ref_bin
    JOIN dbo._Document152 AS p
      ON p._IDRRef = pl._Document152_IDRRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = p._Fld1072RRef
    WHERE p._Posted = 0x01
      AND p._Marked = 0x00
      AND CASE
            WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
            ELSE p._Date_Time
          END <= @cutoff_at
)
SELECT
    sale_doc_ref_bin,
    payment_ref,
    payment_datetime,
    payment_amount,
    payment_method,
    payment_operation,
    payment_match_source
INTO #payments_by_sale_doc
FROM payment_candidates
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_payments_by_sale_doc
    ON #payments_by_sale_doc(sale_doc_ref_bin);

SELECT
    ss.service_order,
    ss.service_name,
    ss.product_ref,
    ss.product_code,
    ss.product_name,
    ss.sale_doc_ref,
    ss.sale_number,
    ss.sale_line_no,
    CONCAT(ss.sale_number, N'-', ss.sale_line_no) AS sale_line_id,
    ss.sale_datetime,
    ss.sale_date,
    ss.sale_client_ref,
    ss.sale_client_id,
    ss.sale_client_fio,
    ss.sale_client_phone,
    ss.sale_branch_raw,
    ss.sale_branch,
    ss.sale_branch_source,
    ss.linked_service_doc_ref,
    ss.linked_object_rtref,
    ss.service_doc_number,
    ss.service_doc_datetime,
    ss.service_doc_holder_ref,
    ss.service_doc_holder_id,
    ss.service_doc_holder_fio,
    CASE WHEN ss.service_start_date_raw <= '2001-01-02' THEN NULL ELSE ss.service_start_date_raw END AS service_start_date,
    CASE WHEN ss.service_end_date_raw <= '2001-01-02' THEN NULL ELSE ss.service_end_date_raw END AS service_end_date,
    ss.service_doc_duration_value,
    ss.service_doc_posted,
    ss.service_doc_marked,
    ss.line_quantity,
    ss.line_total_amount,
    ss.unit_price,
    ss.vat_amount,
    ss.line_comment,
    ss.rg_duration_days,
    ss.rg_price,
    ss.rg_paid_candidate,
    ss.rg_payment_count_candidate,
    ss.rg_visits_candidate_8007,
    ss.rg_visits_candidate_8008,
    ss.rg_visits_candidate_8009,
    CAST(COALESCE(b.receipt_qty, 0) AS decimal(15, 3)) AS rg3336_receipt_qty,
    CAST(COALESCE(b.expense_qty, 0) AS decimal(15, 3)) AS rg3336_expense_qty,
    CAST(COALESCE(b.signed_balance, 0) AS decimal(15, 3)) AS rg3336_signed_balance,
    COALESCE(b.movement_rows, 0) AS rg3336_movement_rows,
    COALESCE(b.receipt_rows, 0) AS rg3336_receipt_rows,
    COALESCE(b.expense_rows, 0) AS rg3336_expense_rows,
    CASE WHEN ss.linked_service_doc_ref IS NOT NULL THEN 1 ELSE 0 END AS has_linked_service_doc,
    CASE WHEN COALESCE(b.signed_balance, 0) > 0 THEN 1 ELSE 0 END AS is_active_by_balance,
    CASE
        WHEN ss.service_end_date_raw > '2001-01-02'
         AND ss.service_end_date_raw >= @cutoff_date
         AND ss.sale_datetime <= @cutoff_at THEN 1
        ELSE 0
    END AS is_active_by_date,
    CASE
        WHEN ss.linked_service_doc_ref IS NOT NULL
         AND (
             COALESCE(b.signed_balance, 0) > 0
             OR (
                 ss.service_end_date_raw > '2001-01-02'
                 AND ss.service_end_date_raw >= @cutoff_date
             )
         ) THEN 1
        ELSE 0
    END AS is_active_on_cutoff,
    pay.payment_ref,
    pay.payment_datetime,
    CAST(COALESCE(pay.payment_amount, 0) AS decimal(15, 2)) AS payment_amount,
    pay.payment_method,
    pay.payment_operation,
    pay.payment_match_source,
    @cutoff_at AS cutoff_at,
    N'dbo._Document154_VT1137 + dbo._Document154' AS raw_source
INTO fitbase_part2.services_import_facts
FROM #service_sales AS ss
LEFT JOIN #balance_by_doc AS b
  ON b.linked_service_doc_ref_bin = ss.linked_service_doc_ref_bin
LEFT JOIN #payments_by_sale_doc AS pay
  ON pay.sale_doc_ref_bin = ss.sale_doc_ref_bin;

CREATE INDEX IX_services_import_facts_client_id
    ON fitbase_part2.services_import_facts(sale_client_id);
CREATE INDEX IX_services_import_facts_service_name
    ON fitbase_part2.services_import_facts(service_name);
CREATE INDEX IX_services_import_facts_active
    ON fitbase_part2.services_import_facts(is_active_on_cutoff, service_name);

SELECT
    'services_import_facts' AS table_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT service_name) AS service_names_with_rows,
    COUNT(DISTINCT sale_client_id) AS distinct_sale_clients,
    SUM(CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_rows,
    COUNT(DISTINCT CASE WHEN is_active_on_cutoff = 1 THEN service_name END) AS active_service_names
FROM fitbase_part2.services_import_facts;

SELECT
    service_order,
    service_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT sale_client_id) AS distinct_clients,
    SUM(CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END) AS active_rows,
    MAX(sale_datetime) AS last_sale_datetime
FROM fitbase_part2.services_import_facts
GROUP BY service_order, service_name
ORDER BY service_order;
