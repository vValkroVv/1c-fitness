SET NOCOUNT ON;
GO

WITH table_rows AS (
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
inventory AS (
    SELECT
        tr.schema_name,
        tr.table_name,
        tr.approx_rows,
        c.column_id,
        c.name AS column_name,
        ty.name AS sql_type,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable
    FROM table_rows tr
    JOIN sys.columns c ON c.object_id = tr.object_id
    JOIN sys.types ty ON ty.user_type_id = c.user_type_id
)
SELECT csv_line
FROM (
SELECT
    0 AS sort_group,
    N'' AS sort_schema_name,
    N'' AS sort_table_name,
    0 AS sort_column_id,
    N'"schema_name","table_name","approx_rows","column_id","column_name","sql_type","max_length","precision","scale","is_nullable"' AS csv_line
UNION ALL
SELECT
    1 AS sort_group,
    schema_name AS sort_schema_name,
    table_name AS sort_table_name,
    column_id AS sort_column_id,
    CONCAT(
        N'"', REPLACE(schema_name, N'"', N'""'), N'",',
        N'"', REPLACE(table_name, N'"', N'""'), N'",',
        approx_rows, N',',
        column_id, N',',
        N'"', REPLACE(column_name, N'"', N'""'), N'",',
        N'"', REPLACE(sql_type, N'"', N'""'), N'",',
        max_length, N',',
        precision, N',',
        scale, N',',
        is_nullable
    ) AS csv_line
FROM inventory
) lines
ORDER BY sort_group, sort_schema_name, sort_table_name, sort_column_id;
GO
