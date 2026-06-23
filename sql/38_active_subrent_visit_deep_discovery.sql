SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @scan_from_raw datetime2(0) = '4026-04-01 00:00:00';
DECLARE @scan_to_raw datetime2(0) = '4026-06-30 23:59:59';

SELECT
    @@SERVERNAME AS server_name,
    DB_NAME() AS database_name,
    @cutoff_at AS cutoff_at,
    @scan_from_raw AS scan_from_raw_1c,
    @scan_to_raw AS scan_to_raw_1c;

IF OBJECT_ID('tempdb..#active_subrent') IS NOT NULL
    DROP TABLE #active_subrent;

SELECT
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    sale_date,
    start_date,
    end_date,
    subscription_ref,
    client_ref,
    effective_client_ref,
    original_client_ref,
    holder_client_ref,
    payer_client_ref,
    product_ref,
    rg_price,
    matched_payment_amount,
    matched_payment_method
INTO #active_subrent
FROM fitbase_part2.membership_import_facts
WHERE is_limited_subrent = 1
  AND end_date >= CONVERT(date, @cutoff_at);

CREATE INDEX IX_active_subrent_subscription_ref ON #active_subrent(subscription_ref);
CREATE INDEX IX_active_subrent_client_ref ON #active_subrent(client_ref);
CREATE INDEX IX_active_subrent_product_ref ON #active_subrent(product_ref);

SELECT
    'active_limited_subrent_12' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    sale_date,
    start_date,
    end_date,
    subscription_ref,
    client_ref,
    product_ref,
    rg_price,
    matched_payment_amount,
    matched_payment_method
FROM #active_subrent
ORDER BY end_date DESC, document_number;

IF OBJECT_ID('tempdb..#target_refs') IS NOT NULL
    DROP TABLE #target_refs;

CREATE TABLE #target_refs (
    target_document_number nvarchar(20) NOT NULL,
    target_subscription_name nvarchar(200) NOT NULL,
    target_client_id nvarchar(20) NOT NULL,
    ref_kind nvarchar(60) NOT NULL,
    ref binary(16) NOT NULL
);

INSERT INTO #target_refs(target_document_number, target_subscription_name, target_client_id, ref_kind, ref)
SELECT document_number, subscription_name, client_id, N'subscription_ref', CONVERT(binary(16), subscription_ref, 2)
FROM #active_subrent
WHERE NULLIF(subscription_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, subscription_name, client_id, N'client_ref', CONVERT(binary(16), client_ref, 2)
FROM #active_subrent
WHERE NULLIF(client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, subscription_name, client_id, N'effective_client_ref', CONVERT(binary(16), effective_client_ref, 2)
FROM #active_subrent
WHERE NULLIF(effective_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, subscription_name, client_id, N'original_client_ref', CONVERT(binary(16), original_client_ref, 2)
FROM #active_subrent
WHERE NULLIF(original_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, subscription_name, client_id, N'holder_client_ref', CONVERT(binary(16), holder_client_ref, 2)
FROM #active_subrent
WHERE NULLIF(holder_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, subscription_name, client_id, N'payer_client_ref', CONVERT(binary(16), payer_client_ref, 2)
FROM #active_subrent
WHERE NULLIF(payer_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, subscription_name, client_id, N'product_ref', CONVERT(binary(16), product_ref, 2)
FROM #active_subrent
WHERE NULLIF(product_ref, N'') IS NOT NULL;

CREATE INDEX IX_target_refs_ref ON #target_refs(ref);

IF OBJECT_ID('tempdb..#doc_column_matches') IS NOT NULL
    DROP TABLE #doc_column_matches;

CREATE TABLE #doc_column_matches (
    source_area nvarchar(30) NOT NULL,
    table_name sysname NOT NULL,
    column_name sysname NOT NULL,
    ref_kind nvarchar(60) NOT NULL,
    rows_count bigint NOT NULL,
    distinct_target_docs bigint NOT NULL,
    min_normalized_datetime datetime2(0) NULL,
    max_normalized_datetime datetime2(0) NULL
);

IF OBJECT_ID('tempdb..#doc_samples') IS NOT NULL
    DROP TABLE #doc_samples;

CREATE TABLE #doc_samples (
    source_area nvarchar(30) NOT NULL,
    table_name sysname NOT NULL,
    column_name sysname NOT NULL,
    ref_kind nvarchar(60) NOT NULL,
    target_document_number nvarchar(20) NOT NULL,
    target_subscription_name nvarchar(200) NOT NULL,
    target_client_id nvarchar(20) NOT NULL,
    source_number nvarchar(40) NULL,
    normalized_datetime datetime2(0) NULL,
    source_ref_hex varchar(32) NULL
);

DECLARE
    @schema_name sysname,
    @table_name sysname,
    @column_name sysname,
    @parent_table_name sysname,
    @parent_column_name sysname,
    @sql nvarchar(max);

DECLARE header_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name, c.name
FROM sys.tables AS t
JOIN sys.schemas AS s
  ON s.schema_id = t.schema_id
JOIN sys.columns AS date_col
  ON date_col.object_id = t.object_id
 AND date_col.name = N'_Date_Time'
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
JOIN sys.partitions AS p
  ON p.object_id = t.object_id
 AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
  AND t.name LIKE N'_Document%'
  AND t.name NOT LIKE N'%[_]VT%'
  AND p.rows > 0
  AND ty.name = N'binary'
  AND c.max_length = 16
  AND c.name <> N'_IDRRef'
ORDER BY p.rows DESC, t.name, c.column_id;

OPEN header_cursor;
FETCH NEXT FROM header_cursor INTO @schema_name, @table_name, @column_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #doc_column_matches (
    source_area, table_name, column_name, ref_kind, rows_count,
    distinct_target_docs, min_normalized_datetime, max_normalized_datetime
)
SELECT
    N''document_header'',
    @table_name,
    @column_name,
    tr.ref_kind,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT tr.target_document_number) AS distinct_target_docs,
    MIN(DATEADD(year, -2000, source_table._Date_Time)) AS min_normalized_datetime,
    MAX(DATEADD(year, -2000, source_table._Date_Time)) AS max_normalized_datetime
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N' AS source_table WITH (NOLOCK)
JOIN #target_refs AS tr
  ON source_table.' + QUOTENAME(@column_name) + N' = tr.ref
WHERE source_table._Date_Time >= @scan_from_raw
  AND source_table._Date_Time <= @scan_to_raw
GROUP BY tr.ref_kind
OPTION (MAXDOP 2);

INSERT INTO #doc_samples (
    source_area, table_name, column_name, ref_kind,
    target_document_number, target_subscription_name, target_client_id,
    source_number, normalized_datetime, source_ref_hex
)
SELECT TOP (40)
    N''document_header'',
    @table_name,
    @column_name,
    tr.ref_kind,
    tr.target_document_number,
    tr.target_subscription_name,
    tr.target_client_id,
    CONVERT(nvarchar(40), source_table._Number),
    DATEADD(year, -2000, source_table._Date_Time),
    CONVERT(varchar(32), source_table._IDRRef, 2)
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N' AS source_table WITH (NOLOCK)
JOIN #target_refs AS tr
  ON source_table.' + QUOTENAME(@column_name) + N' = tr.ref
WHERE source_table._Date_Time >= @scan_from_raw
  AND source_table._Date_Time <= @scan_to_raw
ORDER BY source_table._Date_Time DESC, source_table._Number DESC
OPTION (MAXDOP 2);';

    BEGIN TRY
        EXEC sp_executesql
            @sql,
            N'@table_name sysname, @column_name sysname, @scan_from_raw datetime2(0), @scan_to_raw datetime2(0)',
            @table_name = @table_name,
            @column_name = @column_name,
            @scan_from_raw = @scan_from_raw,
            @scan_to_raw = @scan_to_raw;
    END TRY
    BEGIN CATCH
    END CATCH;

    FETCH NEXT FROM header_cursor INTO @schema_name, @table_name, @column_name;
END

CLOSE header_cursor;
DEALLOCATE header_cursor;

DECLARE vt_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    s.name AS schema_name,
    vt.name AS vt_table_name,
    c.name AS binary_column_name,
    parent.name AS parent_table_name,
    parent_col.name AS parent_column_name
FROM sys.tables AS vt
JOIN sys.schemas AS s
  ON s.schema_id = vt.schema_id
JOIN sys.partitions AS p
  ON p.object_id = vt.object_id
 AND p.index_id IN (0, 1)
JOIN sys.columns AS parent_col
  ON parent_col.object_id = vt.object_id
 AND parent_col.name = LEFT(vt.name, CHARINDEX(N'_VT', vt.name) - 1) + N'_IDRRef'
JOIN sys.tables AS parent
  ON parent.name = LEFT(vt.name, CHARINDEX(N'_VT', vt.name) - 1)
JOIN sys.columns AS parent_date_col
  ON parent_date_col.object_id = parent.object_id
 AND parent_date_col.name = N'_Date_Time'
JOIN sys.columns AS c
  ON c.object_id = vt.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
WHERE vt.is_ms_shipped = 0
  AND vt.name LIKE N'_Document%[_]VT%'
  AND p.rows > 0
  AND ty.name = N'binary'
  AND c.max_length = 16
  AND c.name <> parent_col.name
ORDER BY p.rows DESC, vt.name, c.column_id;

OPEN vt_cursor;
FETCH NEXT FROM vt_cursor INTO @schema_name, @table_name, @column_name, @parent_table_name, @parent_column_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #doc_column_matches (
    source_area, table_name, column_name, ref_kind, rows_count,
    distinct_target_docs, min_normalized_datetime, max_normalized_datetime
)
SELECT
    N''document_vt'',
    @table_name,
    @column_name,
    tr.ref_kind,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT tr.target_document_number) AS distinct_target_docs,
    MIN(DATEADD(year, -2000, parent_doc._Date_Time)) AS min_normalized_datetime,
    MAX(DATEADD(year, -2000, parent_doc._Date_Time)) AS max_normalized_datetime
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N' AS source_table WITH (NOLOCK)
JOIN ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@parent_table_name) + N' AS parent_doc WITH (NOLOCK)
  ON parent_doc._IDRRef = source_table.' + QUOTENAME(@parent_column_name) + N'
JOIN #target_refs AS tr
  ON source_table.' + QUOTENAME(@column_name) + N' = tr.ref
WHERE parent_doc._Date_Time >= @scan_from_raw
  AND parent_doc._Date_Time <= @scan_to_raw
GROUP BY tr.ref_kind
OPTION (MAXDOP 2);

INSERT INTO #doc_samples (
    source_area, table_name, column_name, ref_kind,
    target_document_number, target_subscription_name, target_client_id,
    source_number, normalized_datetime, source_ref_hex
)
SELECT TOP (40)
    N''document_vt'',
    @table_name,
    @column_name,
    tr.ref_kind,
    tr.target_document_number,
    tr.target_subscription_name,
    tr.target_client_id,
    CONVERT(nvarchar(40), parent_doc._Number),
    DATEADD(year, -2000, parent_doc._Date_Time),
    CONVERT(varchar(32), parent_doc._IDRRef, 2)
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N' AS source_table WITH (NOLOCK)
JOIN ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@parent_table_name) + N' AS parent_doc WITH (NOLOCK)
  ON parent_doc._IDRRef = source_table.' + QUOTENAME(@parent_column_name) + N'
JOIN #target_refs AS tr
  ON source_table.' + QUOTENAME(@column_name) + N' = tr.ref
WHERE parent_doc._Date_Time >= @scan_from_raw
  AND parent_doc._Date_Time <= @scan_to_raw
ORDER BY parent_doc._Date_Time DESC, parent_doc._Number DESC
OPTION (MAXDOP 2);';

    BEGIN TRY
        EXEC sp_executesql
            @sql,
            N'@table_name sysname, @column_name sysname, @scan_from_raw datetime2(0), @scan_to_raw datetime2(0)',
            @table_name = @table_name,
            @column_name = @column_name,
            @scan_from_raw = @scan_from_raw,
            @scan_to_raw = @scan_to_raw;
    END TRY
    BEGIN CATCH
    END CATCH;

    FETCH NEXT FROM vt_cursor INTO @schema_name, @table_name, @column_name, @parent_table_name, @parent_column_name;
END

CLOSE vt_cursor;
DEALLOCATE vt_cursor;

SELECT
    'document_ref_matches_summary' AS probe,
    source_area,
    table_name,
    column_name,
    ref_kind,
    rows_count,
    distinct_target_docs,
    min_normalized_datetime,
    max_normalized_datetime
FROM #doc_column_matches
WHERE rows_count > 0
ORDER BY
    CASE ref_kind
        WHEN N'subscription_ref' THEN 0
        WHEN N'product_ref' THEN 1
        ELSE 2
    END,
    rows_count DESC,
    table_name,
    column_name;

SELECT TOP (400)
    'document_ref_matches_samples' AS probe,
    source_area,
    table_name,
    column_name,
    ref_kind,
    target_document_number,
    target_subscription_name,
    target_client_id,
    source_number,
    normalized_datetime,
    source_ref_hex
FROM #doc_samples
ORDER BY
    CASE ref_kind
        WHEN N'subscription_ref' THEN 0
        WHEN N'product_ref' THEN 1
        ELSE 2
    END,
    normalized_datetime DESC,
    table_name,
    column_name;

