SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @sale_doc_ref binary(16) = 0xB071F1F9946499CC42B27BB50D36693B;

PRINT '01 Document154 header fields that match Reference64 for one service sale';
SELECT
    d._Number AS sale_number,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS sale_datetime,
    f.field_name,
    f.ref_hex,
    c._Code AS client_id,
    c._Description AS client_fio
FROM dbo._Document154 AS d
CROSS APPLY (VALUES
    (N'_Fld1136RRef', CONVERT(varchar(32), d._Fld1136RRef, 2), d._Fld1136RRef),
    (N'_Fld1131_RRRef', CONVERT(varchar(32), d._Fld1131_RRRef, 2), d._Fld1131_RRRef),
    (N'_Fld1124RRef', CONVERT(varchar(32), d._Fld1124RRef, 2), d._Fld1124RRef),
    (N'_Fld7829RRef', CONVERT(varchar(32), d._Fld7829RRef, 2), d._Fld7829RRef),
    (N'_Fld1117RRef', CONVERT(varchar(32), d._Fld1117RRef, 2), d._Fld1117RRef),
    (N'_Fld1118RRef', CONVERT(varchar(32), d._Fld1118RRef, 2), d._Fld1118RRef),
    (N'_Fld1120RRef', CONVERT(varchar(32), d._Fld1120RRef, 2), d._Fld1120RRef),
    (N'_Fld1133RRef', CONVERT(varchar(32), d._Fld1133RRef, 2), d._Fld1133RRef),
    (N'_Fld1119RRef', CONVERT(varchar(32), d._Fld1119RRef, 2), d._Fld1119RRef),
    (N'_Fld1134RRef', CONVERT(varchar(32), d._Fld1134RRef, 2), d._Fld1134RRef),
    (N'_Fld1115RRef', CONVERT(varchar(32), d._Fld1115RRef, 2), d._Fld1115RRef),
    (N'_Fld9146RRef', CONVERT(varchar(32), d._Fld9146RRef, 2), d._Fld9146RRef),
    (N'_Fld5399RRef', CONVERT(varchar(32), d._Fld5399RRef, 2), d._Fld5399RRef),
    (N'_Fld1123RRef', CONVERT(varchar(32), d._Fld1123RRef, 2), d._Fld1123RRef),
    (N'_Fld6066RRef', CONVERT(varchar(32), d._Fld6066RRef, 2), d._Fld6066RRef),
    (N'_Fld1116RRef', CONVERT(varchar(32), d._Fld1116RRef, 2), d._Fld1116RRef),
    (N'_Fld1121RRef', CONVERT(varchar(32), d._Fld1121RRef, 2), d._Fld1121RRef)
) AS f(field_name, ref_hex, ref_bin)
LEFT JOIN dbo._Reference64 AS c
  ON c._IDRRef = f.ref_bin
WHERE d._IDRRef = @sale_doc_ref
ORDER BY CASE WHEN c._IDRRef IS NULL THEN 1 ELSE 0 END, f.field_name;

PRINT '02 Document154 header field match counts against Reference64';
SELECT field_name, COUNT_BIG(*) AS matching_doc_rows
FROM (
    SELECT N'_Fld1136RRef' AS field_name FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1136RRef
    UNION ALL SELECT N'_Fld1124RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1124RRef
    UNION ALL SELECT N'_Fld7829RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld7829RRef
    UNION ALL SELECT N'_Fld1117RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1117RRef
    UNION ALL SELECT N'_Fld1118RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1118RRef
    UNION ALL SELECT N'_Fld1120RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1120RRef
    UNION ALL SELECT N'_Fld1133RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1133RRef
    UNION ALL SELECT N'_Fld1119RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1119RRef
    UNION ALL SELECT N'_Fld1134RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1134RRef
    UNION ALL SELECT N'_Fld1115RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1115RRef
    UNION ALL SELECT N'_Fld9146RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld9146RRef
    UNION ALL SELECT N'_Fld5399RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld5399RRef
    UNION ALL SELECT N'_Fld1123RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1123RRef
    UNION ALL SELECT N'_Fld6066RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld6066RRef
    UNION ALL SELECT N'_Fld1116RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1116RRef
    UNION ALL SELECT N'_Fld1121RRef' FROM dbo._Document154 AS d JOIN dbo._Reference64 AS c ON c._IDRRef = d._Fld1121RRef
) AS x
GROUP BY field_name
ORDER BY matching_doc_rows DESC, field_name;

