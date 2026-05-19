USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'fitbase_part2')
    EXEC(N'CREATE SCHEMA fitbase_part2');

DROP TABLE IF EXISTS #club_refs;
DROP TABLE IF EXISTS fitbase_part2.club_link_candidates;

CREATE TABLE #club_refs (
    ref_bin binary(16) NOT NULL,
    ref_hex varchar(32) NOT NULL,
    ref_table sysname NOT NULL,
    description nvarchar(400) NULL,
    normalized_club nvarchar(100) NULL
);

DECLARE @ref_sql nvarchar(max) = N'';

SELECT @ref_sql = STRING_AGG(CAST(N'
INSERT INTO #club_refs (ref_bin, ref_hex, ref_table, description, normalized_club)
SELECT
    _IDRRef,
    CONVERT(varchar(32), _IDRRef, 2),
    N''' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N''',
    CAST(_Description AS nvarchar(400)),
    CASE
        WHEN _Description LIKE N''%Коммуналь%'' THEN N''Коммунальная, 20''
        WHEN _Description LIKE N''%Лососин%'' THEN N''Лососинское шоссе, 26''
        WHEN _Description LIKE N''%Промышлен%'' THEN N''Промышленная, 10''
        WHEN _Description LIKE N''%Ровио%'' THEN N''Ровио, 3''
        ELSE NULL
    END
FROM ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N'
WHERE _Description LIKE N''%Коммуналь%''
   OR _Description LIKE N''%Лососин%''
   OR _Description LIKE N''%Промышлен%''
   OR _Description LIKE N''%Ровио%''
' AS nvarchar(max)), NCHAR(10))
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
 AND c.name = N'_Description'
WHERE t.name LIKE N'_Reference%';

EXEC sp_executesql @ref_sql;

CREATE TABLE fitbase_part2.club_link_candidates (
    target_table sysname NOT NULL,
    target_column sysname NOT NULL,
    matched_rows bigint NOT NULL,
    distinct_refs bigint NOT NULL,
    distinct_clubs bigint NOT NULL,
    sample_ref_table sysname NULL,
    sample_description nvarchar(400) NULL,
    sample_normalized_club nvarchar(100) NULL
);

DECLARE @link_sql nvarchar(max) = N'';

SELECT @link_sql = STRING_AGG(CAST(N'
INSERT INTO fitbase_part2.club_link_candidates (
    target_table,
    target_column,
    matched_rows,
    distinct_refs,
    distinct_clubs,
    sample_ref_table,
    sample_description,
    sample_normalized_club
)
SELECT
    N''' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N''',
    N''' + c.name + N''',
    COUNT_BIG(*),
    COUNT_BIG(DISTINCT cr.ref_hex),
    COUNT_BIG(DISTINCT cr.normalized_club),
    MIN(cr.ref_table),
    MIN(cr.description),
    MIN(cr.normalized_club)
FROM ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N' AS src
JOIN #club_refs AS cr
  ON src.' + QUOTENAME(c.name) + N' = cr.ref_bin
HAVING COUNT_BIG(*) > 0
' AS nvarchar(max)), NCHAR(10))
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
WHERE t.name IN (N'_Document163', N'_InfoRg3060', N'_Document152', N'_Reference72', N'_Reference64')
  AND ty.name = N'binary'
  AND c.max_length = 16;

EXEC sp_executesql @link_sql;

SELECT
    target_table,
    target_column,
    matched_rows,
    distinct_refs,
    distinct_clubs,
    sample_ref_table,
    sample_description,
    sample_normalized_club
FROM fitbase_part2.club_link_candidates
ORDER BY matched_rows DESC, target_table, target_column;
GO
