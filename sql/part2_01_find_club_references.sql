USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'fitbase_part2')
    EXEC(N'CREATE SCHEMA fitbase_part2');

DROP TABLE IF EXISTS fitbase_part2.club_reference_candidates;

CREATE TABLE fitbase_part2.club_reference_candidates (
    table_name sysname NOT NULL,
    ref_hex varchar(32) NOT NULL,
    code nvarchar(100) NULL,
    description nvarchar(400) NULL,
    normalized_club nvarchar(100) NULL
);

DECLARE @sql nvarchar(max) = N'';

WITH reference_tables AS (
    SELECT
        t.object_id,
        t.schema_id,
        t.name,
        MAX(CASE WHEN c.name = N'_Code' THEN 1 ELSE 0 END) AS has_code
    FROM sys.tables AS t
    JOIN sys.columns AS d
      ON d.object_id = t.object_id
     AND d.name = N'_Description'
    LEFT JOIN sys.columns AS c
      ON c.object_id = t.object_id
     AND c.name = N'_Code'
    WHERE t.name LIKE N'_Reference%'
    GROUP BY t.object_id, t.schema_id, t.name
)
SELECT @sql = STRING_AGG(CAST(N'
INSERT INTO fitbase_part2.club_reference_candidates (table_name, ref_hex, code, description, normalized_club)
SELECT
    N''' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N''' AS table_name,
    CONVERT(varchar(32), _IDRRef, 2) AS ref_hex,
    ' + CASE
            WHEN t.has_code = 1
            THEN N'CAST(_Code AS nvarchar(100))'
            ELSE N'CAST(NULL AS nvarchar(100))'
        END + N' AS code,
    CAST(_Description AS nvarchar(400)) AS description,
    CASE
        WHEN _Description LIKE N''%Коммуналь%'' THEN N''Коммунальная, 20''
        WHEN _Description LIKE N''%Лососин%'' THEN N''Лососинское шоссе, 26''
        WHEN _Description LIKE N''%Промышлен%'' THEN N''Промышленная, 10''
        WHEN _Description LIKE N''%Ровио%'' THEN N''Ровио, 3''
        ELSE NULL
    END AS normalized_club
FROM ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N'
WHERE _Description LIKE N''%Коммуналь%''
   OR _Description LIKE N''%Лососин%''
   OR _Description LIKE N''%Промышлен%''
   OR _Description LIKE N''%Ровио%''
' AS nvarchar(max)), NCHAR(10))
FROM reference_tables AS t;

EXEC sp_executesql @sql;

SELECT
    table_name,
    ref_hex,
    code,
    description,
    normalized_club
FROM fitbase_part2.club_reference_candidates
ORDER BY table_name, normalized_club, description, ref_hex;

SELECT
    table_name,
    normalized_club,
    COUNT_BIG(*) AS candidate_rows
FROM fitbase_part2.club_reference_candidates
GROUP BY table_name, normalized_club
ORDER BY candidate_rows DESC, table_name, normalized_club;
GO
