SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

IF OBJECT_ID('tempdb..#all_references') IS NOT NULL
    DROP TABLE #all_references;

CREATE TABLE #all_references (
    source_table nvarchar(128) NOT NULL,
    ref binary(16) NOT NULL,
    code nvarchar(200) NULL,
    description nvarchar(600) NULL
);

DECLARE
    @schema_name nvarchar(128),
    @reference_table nvarchar(128),
    @has_code bit,
    @sql nvarchar(max);

DECLARE reference_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name,
       CASE WHEN EXISTS (
            SELECT 1 FROM sys.columns c
            WHERE c.object_id = t.object_id AND c.name = N'_Code'
       ) THEN 1 ELSE 0 END AS has_code
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
  AND t.name LIKE N'_Reference%'
  AND t.name NOT LIKE N'%[_]VT%'
  AND EXISTS (
      SELECT 1 FROM sys.columns c
      WHERE c.object_id = t.object_id AND c.name = N'_IDRRef'
  )
  AND EXISTS (
      SELECT 1 FROM sys.columns c
      WHERE c.object_id = t.object_id AND c.name = N'_Description'
  );

OPEN reference_cursor;
FETCH NEXT FROM reference_cursor INTO @schema_name, @reference_table, @has_code;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
INSERT INTO #all_references (source_table, ref, code, description)
SELECT
    @reference_table,
    _IDRRef,
    ' + CASE WHEN @has_code = 1 THEN N'CONVERT(nvarchar(200), _Code)' ELSE N'NULL' END + N',
    CONVERT(nvarchar(600), _Description)
FROM ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@reference_table) + N'
WHERE _IDRRef <> 0x00000000000000000000000000000000;';

    EXEC sp_executesql
        @sql,
        N'@reference_table nvarchar(128)',
        @reference_table = @reference_table;

    FETCH NEXT FROM reference_cursor INTO @schema_name, @reference_table, @has_code;
END

CLOSE reference_cursor;
DEALLOCATE reference_cursor;

CREATE INDEX IX_all_references_ref ON #all_references(ref);

IF OBJECT_ID('tempdb..#reference_column_matches') IS NOT NULL
    DROP TABLE #reference_column_matches;

CREATE TABLE #reference_column_matches (
    source_table nvarchar(128) NOT NULL,
    source_column nvarchar(128) NOT NULL,
    matched_reference_table nvarchar(128) NOT NULL,
    distinct_matched_values bigint NOT NULL,
    sample_code nvarchar(200) NULL,
    sample_description nvarchar(600) NULL
);

DECLARE
    @source_table nvarchar(128),
    @source_column nvarchar(128);

DECLARE source_column_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT t.name AS source_table, c.name AS source_column
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN (
        N'_Document150',
        N'_Document152',
        N'_Document163',
        N'_Document137',
        N'_Document137_VT724',
        N'_InfoRg5233',
        N'_InfoRg7156',
        N'_AccumRg3305'
    )
  AND ty.name = N'binary'
  AND c.max_length = 16
  AND c.name NOT LIKE N'%[_]RRRef'
  AND c.name NOT LIKE N'%[_]RRef'
  AND c.name NOT IN (N'_IDRRef', N'_Version', N'_Marked', N'_Posted', N'_Active')
ORDER BY t.name, c.column_id;

OPEN source_column_cursor;
FETCH NEXT FROM source_column_cursor INTO @source_table, @source_column;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
WITH distinct_values AS (
    SELECT DISTINCT ' + QUOTENAME(@source_column) + N' AS ref
    FROM dbo.' + QUOTENAME(@source_table) + N'
    WHERE ' + QUOTENAME(@source_column) + N' <> 0x00000000000000000000000000000000
)
INSERT INTO #reference_column_matches (
    source_table, source_column, matched_reference_table,
    distinct_matched_values, sample_code, sample_description
)
SELECT
    @source_table,
    @source_column,
    ar.source_table,
    COUNT_BIG(*) AS distinct_matched_values,
    MIN(ar.code) AS sample_code,
    MIN(ar.description) AS sample_description
FROM distinct_values dv
JOIN #all_references ar ON ar.ref = dv.ref
GROUP BY ar.source_table
OPTION (MAXDOP 2);';

    EXEC sp_executesql
        @sql,
        N'@source_table nvarchar(128), @source_column nvarchar(128)',
        @source_table = @source_table,
        @source_column = @source_column;

    FETCH NEXT FROM source_column_cursor INTO @source_table, @source_column;
END

CLOSE source_column_cursor;
DEALLOCATE source_column_cursor;

SELECT
    source_table,
    source_column,
    matched_reference_table,
    distinct_matched_values,
    sample_code,
    sample_description
FROM #reference_column_matches
WHERE distinct_matched_values > 0
ORDER BY source_table, source_column, distinct_matched_values DESC;
GO
