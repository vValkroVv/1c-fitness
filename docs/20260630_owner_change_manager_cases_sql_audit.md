# SQL-audit смены владельца по кейсам менеджера

Дата проверки: `2026-07-20`.

Источник: восстановленная из `data/Fitnes-30-06-26.bak` база
`FitnessRestored_20260630_macos`.

Единый срез: `2026-06-30 23:27:03`.

Проверка выполнена только `SELECT`-запросами. После аудита SQL-контейнер
остановлен.

## Как повторить

```bash
SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260630_macos \
  -W -s '|' -Q "<SQL из раздела ниже>"
```

## 1. Фактическое поле «Вид операции»

На обоих скриншотах 1С видом операции является `Смена владельца`. В SQL это
`dbo._Document138._Fld761RRef`. Ссылка принадлежит перечислению
`dbo._Enum186`, а не справочнику `_Reference72`.

```sql
SET NOCOUNT ON;

SELECT
    _EnumOrder,
    CONVERT(varchar(32), _IDRRef, 2) AS enum_ref
FROM dbo._Enum186
ORDER BY _EnumOrder;
```

Значение для `Смена владельца`:

```text
_EnumOrder|enum_ref
5|9C10896C259288044EBD0A4A7A054001
```

## 2. Два кейса из DOCX

```sql
SET NOCOUNT ON;

SELECT
    d._Number AS doc_number,
    CASE
        WHEN d._Date_Time > '3000-01-01'
            THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS doc_at,
    CONVERT(int, d._Posted) AS posted,
    CONVERT(int, d._Marked) AS marked,
    CONVERT(varchar(32), d._Fld761RRef, 2) AS operation_ref,
    e._EnumOrder AS operation_enum_order,
    CONVERT(varchar(32), d._Fld764RRef, 2) AS modifier_ref,
    modifier._Description AS modifier_name,
    sale._Number AS membership_number,
    old_client._Code AS old_client_id,
    old_client._Description AS old_client_fio,
    new_client._Code AS new_client_id,
    new_client._Description AS new_client_fio
FROM dbo._Document138 AS d
LEFT JOIN dbo._Enum186 AS e
  ON e._IDRRef = d._Fld761RRef
LEFT JOIN dbo._Reference72 AS modifier
  ON modifier._IDRRef = d._Fld764RRef
LEFT JOIN dbo._Document163 AS sale
  ON sale._IDRRef = d._Fld763RRef
LEFT JOIN dbo._Reference64 AS old_client
  ON old_client._IDRRef = d._Fld762RRef
LEFT JOIN dbo._Reference64 AS new_client
  ON new_client._IDRRef = d._Fld767RRef
WHERE d._Number IN (N'00000052842', N'00000055310', N'00000056656')
ORDER BY d._Date_Time, d._IDRRef;
```

Контрольный вывод:

```text
doc_number|doc_at|posted|marked|operation_ref|operation_enum_order|modifier_name|membership_number|old_client_id|old_client_fio|new_client_id|new_client_fio
00000052842|2025-04-11 17:28:26|1|0|9C10896C259288044EBD0A4A7A054001|5|Переоформление бесплатное|00000133547|000034737|Дворжицкий Владислав Станиславович|000004598|Дворжицкая Анна Александровна
00000055310|2026-01-13 19:34:05|1|0|9C10896C259288044EBD0A4A7A054001|5|Переоформление бесплатное|00000144947|000059399|Позолотин Никита Олегович|000064195|Гончарова Екатерина Игоревна
00000056656|2026-06-08 17:18:59|1|0|9C10896C259288044EBD0A4A7A054001|5|Переоформление платное абонемента на фитнес|00000144947|000064195|Гончарова Екатерина Игоревна|000074154|Галаничева Карина Павловна
```

## 3. Масштаб пропуска текущим SQL

Условия ниже точно повторяют eligibility-условия текущего staging:

- документ проведён;
- не помечен на удаление;
- дата не позже `cutoff_at`;
- членство, старый и новый клиенты заполнены;
- связанный `_Document163` существует.

```sql
SET NOCOUNT ON;

DECLARE @cutoff_at datetime2 = '2026-06-30T23:27:03';
DECLARE @cutoff_sql_at datetime2 = DATEADD(year, 2000, @cutoff_at);
DECLARE @owner_operation_ref binary(16) =
    CONVERT(binary(16), '9C10896C259288044EBD0A4A7A054001', 2);

WITH eligible AS (
    SELECT
        d.*,
        modifier._Description AS modifier_name
    FROM dbo._Document138 AS d
    LEFT JOIN dbo._Reference72 AS modifier
      ON modifier._IDRRef = d._Fld764RRef
    JOIN dbo._Document163 AS sale
      ON sale._IDRRef = d._Fld763RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND d._Date_Time <= @cutoff_sql_at
      AND d._Fld762RRef <> 0x00000000000000000000000000000000
      AND d._Fld767RRef <> 0x00000000000000000000000000000000
      AND d._Fld763RRef <> 0x00000000000000000000000000000000
)
SELECT
    SUM(CASE
        WHEN _Fld761RRef = @owner_operation_ref THEN 1 ELSE 0
    END) AS operation_owner_rows,
    SUM(CASE
        WHEN LTRIM(RTRIM(modifier_name)) IN (
            N'Смена владельца',
            N'Смена владельца подарочной карты'
        ) THEN 1 ELSE 0
    END) AS current_modifier_filter_rows,
    SUM(CASE
        WHEN _Fld761RRef = @owner_operation_ref
         AND LTRIM(RTRIM(modifier_name)) IN (
            N'Смена владельца',
            N'Смена владельца подарочной карты'
         ) THEN 1 ELSE 0
    END) AS overlap_rows,
    SUM(CASE
        WHEN _Fld761RRef = @owner_operation_ref
         AND LTRIM(RTRIM(COALESCE(modifier_name, N''))) NOT IN (
            N'Смена владельца',
            N'Смена владельца подарочной карты'
         ) THEN 1 ELSE 0
    END) AS operation_owner_missed_by_current_filter
FROM eligible;
```

Фактический вывод:

```text
operation_owner_rows|current_modifier_filter_rows|overlap_rows|operation_owner_missed_by_current_filter
5528|4595|4595|933
```

Разбивка 5 528 фактических owner-change по модификатору:

```text
Смена владельца подарочной карты|3771
Смена владельца|824
Переоформление платное абонемента на фитнес|587
Переоформление бесплатное|346
```

## 4. Влияние на effective owner

```sql
SET NOCOUNT ON;

DECLARE @cutoff_at datetime2 = '2026-06-30T23:27:03';
DECLARE @cutoff_sql_at datetime2 = DATEADD(year, 2000, @cutoff_at);
DECLARE @owner_operation_ref binary(16) =
    CONVERT(binary(16), '9C10896C259288044EBD0A4A7A054001', 2);

WITH eligible AS (
    SELECT
        d.*,
        modifier._Description AS modifier_name
    FROM dbo._Document138 AS d
    LEFT JOIN dbo._Reference72 AS modifier
      ON modifier._IDRRef = d._Fld764RRef
    JOIN dbo._Document163 AS sale
      ON sale._IDRRef = d._Fld763RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND d._Date_Time <= @cutoff_sql_at
      AND d._Fld762RRef <> 0x00000000000000000000000000000000
      AND d._Fld767RRef <> 0x00000000000000000000000000000000
      AND d._Fld763RRef <> 0x00000000000000000000000000000000
),
correct_rank AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY _Fld763RRef
            ORDER BY _Date_Time DESC, _IDRRef DESC
        ) AS owner_change_rank
    FROM eligible
    WHERE _Fld761RRef = @owner_operation_ref
),
current_rank AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY _Fld763RRef
            ORDER BY _Date_Time DESC, _IDRRef DESC
        ) AS owner_change_rank
    FROM eligible
    WHERE LTRIM(RTRIM(modifier_name)) IN (
        N'Смена владельца',
        N'Смена владельца подарочной карты'
    )
)
SELECT
    COUNT_BIG(*) AS correct_latest_memberships,
    SUM(CASE
        WHEN current_row._IDRRef IS NULL THEN 1 ELSE 0
    END) AS missing_entirely_current,
    SUM(CASE
        WHEN current_row._IDRRef IS NOT NULL
         AND current_row._IDRRef <> correct_row._IDRRef
            THEN 1 ELSE 0
    END) AS wrong_older_current,
    SUM(CASE
        WHEN current_row._Fld767RRef IS NULL
          OR current_row._Fld767RRef <> correct_row._Fld767RRef
            THEN 1 ELSE 0
    END) AS different_effective_owner
FROM correct_rank AS correct_row
LEFT JOIN current_rank AS current_row
  ON current_row._Fld763RRef = correct_row._Fld763RRef
 AND current_row.owner_change_rank = 1
WHERE correct_row.owner_change_rank = 1;
```

Фактический вывод:

```text
correct_latest_memberships|missing_entirely_current|wrong_older_current|different_effective_owner
5277|819|42|861
```

`861` — оценка влияния на effective owner в SQL-слое. Она не означает, что все
861 членство обязательно доживает до каждого финального XLSX после остальных
бизнес-фильтров.

## Вывод

Кейсы `52842` и `56656` не потеряны в backup и не отсечены датой. Они
пропущены из-за ошибочного фильтра по `_Fld764RRef` — модификатору. Признак
вида операции «Смена владельца» находится в `_Fld761RRef`.

## Проверка production-исправления

После замены owner-change фильтра в
`end-to-end-xlsx/sql/part2_03_build_three_funnel_staging.sql` SQL-слой
пересобран на той же восстановленной базе. Затем выполнен
`end-to-end-xlsx/sql/audit_owner_change_20260630.sql`.

Результат:

```text
owner_change_20260630_audit: PASS
stage_owner_change_rows: 5528
stage_effective_owner_change_rows: 5277

00000133547 -> 00000052842 -> 000004598, Дворжицкая Анна Александровна
00000144947 -> 00000056656 -> 000074154, Галаничева Карина Павловна
```

`fitbase_part2.stg_subscriptions_all` получил этих же effective owners. После
пересчёта воронок:

```text
000004598  Дворжицкая Анна       -> Действующие клиенты, contract 00000133547
000074154  Галаничева Карина      -> Действующие клиенты, contract 00000144947
```

Финальные XLSX в ходе этой проверки не пересобирались.
