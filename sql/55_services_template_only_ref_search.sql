SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DROP TABLE IF EXISTS #target_services;
DROP TABLE IF EXISTS #target_refs;
DROP TABLE IF EXISTS #matches;

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

CREATE TABLE #matches (
    schema_name sysname NOT NULL,
    table_name sysname NOT NULL,
    column_name sysname NOT NULL,
    matching_rows bigint NOT NULL
);

DECLARE @schema sysname;
DECLARE @table sysname;
DECLARE @column sysname;
DECLARE @sql nvarchar(max);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
WITH table_rows AS (
    SELECT object_id, SUM(rows) AS rows_count
    FROM sys.partitions
    WHERE index_id IN (0, 1)
    GROUP BY object_id
)
SELECT
    SCHEMA_NAME(t.schema_id) AS schema_name,
    t.name AS table_name,
    c.name AS column_name
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
JOIN table_rows AS trc
  ON trc.object_id = t.object_id
WHERE t.is_ms_shipped = 0
  AND ty.name IN (N'binary', N'varbinary')
  AND c.max_length = 16
  AND trc.rows_count > 0
  AND t.name LIKE N'_Document%'
  AND c.name <> N'_Version'
ORDER BY t.name, c.column_id;

OPEN cur;
FETCH NEXT FROM cur INTO @schema, @table, @column;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        INSERT INTO #matches (schema_name, table_name, column_name, matching_rows)
        SELECT @schema_name, @table_name, @column_name, COUNT_BIG(*)
        FROM ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N' AS src
        JOIN #target_refs AS tr
          ON tr.product_ref_bin = src.' + QUOTENAME(@column) + N'
        HAVING COUNT_BIG(*) > 0;';

    EXEC sp_executesql
        @sql,
        N'@schema_name sysname, @table_name sysname, @column_name sysname',
        @schema_name = @schema,
        @table_name = @table,
        @column_name = @column;

    FETCH NEXT FROM cur INTO @schema, @table, @column;
END

CLOSE cur;
DEALLOCATE cur;

PRINT '01 target refs';
SELECT * FROM #target_refs ORDER BY service_order, product_ref;

PRINT '02 tables/columns containing target product refs';
SELECT *
FROM #matches
ORDER BY matching_rows DESC, table_name, column_name;

PRINT '03 service-level hits by source';
DECLARE @hit_sql nvarchar(max) = N'';

-- Concrete high-value tables for service import investigation.
SELECT
    tr.service_order,
    tr.service_name,
    COUNT(d163._IDRRef) AS document163_rows,
    COUNT(vt1137._Document154_IDRRef) AS document154_vt1137_rows
FROM #target_refs AS tr
LEFT JOIN dbo._Document163 AS d163
  ON d163._Fld1446RRef = tr.product_ref_bin
 AND d163._Posted = 0x01
 AND d163._Marked = 0x00
LEFT JOIN dbo._Document154_VT1137 AS vt1137
  ON vt1137._Fld1146RRef = tr.product_ref_bin
GROUP BY tr.service_order, tr.service_name
ORDER BY tr.service_order;
