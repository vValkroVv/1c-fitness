SET NOCOUNT ON;
GO

WITH row_counts AS (
    SELECT
        t.object_id,
        s.name AS schema_name,
        t.name AS table_name,
        SUM(CASE WHEN p.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS approx_rows
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    LEFT JOIN sys.partitions p ON p.object_id = t.object_id
    WHERE t.is_ms_shipped = 0
    GROUP BY t.object_id, s.name, t.name
),
column_counts AS (
    SELECT
        t.object_id,
        COUNT(*) AS column_count
    FROM sys.tables t
    JOIN sys.columns c ON c.object_id = t.object_id
    WHERE t.is_ms_shipped = 0
    GROUP BY t.object_id
),
table_rows AS (
    SELECT
        rc.schema_name,
        rc.table_name,
        rc.approx_rows,
        cc.column_count
    FROM row_counts rc
    JOIN column_counts cc ON cc.object_id = rc.object_id
)
SELECT csv_line
FROM (
SELECT
    0 AS sort_group,
    CAST(9223372036854775807 AS bigint) AS sort_approx_rows,
    N'' AS sort_table_name,
    N'"schema_name","table_name","approx_rows","column_count"' AS csv_line
UNION ALL
SELECT
    1 AS sort_group,
    approx_rows AS sort_approx_rows,
    table_name AS sort_table_name,
    CONCAT(
        N'"', REPLACE(schema_name, N'"', N'""'), N'",',
        N'"', REPLACE(table_name, N'"', N'""'), N'",',
        approx_rows, N',',
        column_count
    ) AS csv_line
FROM table_rows
) lines
ORDER BY sort_group, sort_approx_rows DESC, sort_table_name;
GO
