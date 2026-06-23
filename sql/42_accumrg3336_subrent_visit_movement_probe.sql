SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_date date = CONVERT(date, @cutoff_at);

SELECT
    'accumrg3336_columns' AS probe,
    c.column_id,
    c.name AS column_name,
    ty.name AS type_name,
    c.max_length,
    c.precision,
    c.scale
FROM sys.columns AS c
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'dbo._AccumRg3336')
ORDER BY c.column_id;

IF OBJECT_ID('tempdb..#final_active_contracts') IS NOT NULL
    DROP TABLE #final_active_contracts;

CREATE TABLE #final_active_contracts (
    document_number nvarchar(20) COLLATE Cyrillic_General_CI_AS NOT NULL PRIMARY KEY
);

INSERT INTO #final_active_contracts(document_number)
VALUES
    (N'00000149952'),
    (N'00000149697'),
    (N'00000150143'),
    (N'00000149696'),
    (N'00000150128'),
    (N'00000150231'),
    (N'00000150029'),
    (N'00000149630'),
    (N'00000149628'),
    (N'00000149980'),
    (N'00000150031'),
    (N'00000149921');

IF OBJECT_ID('tempdb..#active_subrent') IS NOT NULL
    DROP TABLE #active_subrent;

SELECT
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.start_date,
    f.end_date,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    CASE
        WHEN f.subscription_name LIKE N'%20 посещ%' THEN 20
        WHEN f.subscription_name LIKE N'%15 посещ%' THEN 15
        WHEN f.subscription_name LIKE N'%12 посещ%' THEN 12
        WHEN f.subscription_name LIKE N'%10 посещ%' THEN 10
        WHEN f.subscription_name LIKE N'%8 посещ%' THEN 8
        ELSE NULL
    END AS visit_limit
INTO #active_subrent
FROM fitbase_part2.membership_import_facts AS f
JOIN #final_active_contracts AS c
  ON c.document_number = f.document_number;

IF OBJECT_ID('tempdb..#active_doc150') IS NOT NULL
    DROP TABLE #active_doc150;

SELECT
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.start_date,
    s.end_date,
    s.visit_limit,
    d._IDRRef AS doc150_ref_bin,
    CONVERT(varchar(32), d._IDRRef, 2) AS doc150_ref,
    d._Number AS doc150_number,
    DATEADD(year, -2000, d._Date_Time) AS visit_datetime,
    CONVERT(date, DATEADD(year, -2000, d._Date_Time)) AS visit_date,
    d._Fld995 AS duration_seconds
INTO #active_doc150
FROM #active_subrent AS s
JOIN dbo._Document150 AS d
  ON d._Fld991_RRRef = s.subscription_ref_bin
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
  AND DATEADD(year, -2000, d._Date_Time) <= @cutoff_at
  AND CONVERT(date, DATEADD(year, -2000, d._Date_Time)) BETWEEN s.start_date AND
      CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END;

CREATE INDEX IX_active_doc150_ref_bin ON #active_doc150(doc150_ref_bin);

SELECT TOP (120)
    'accumrg3336_active_samples' AS probe,
    d.document_number,
    d.client_id,
    d.effective_client_fio,
    d.subscription_name,
    d.visit_limit,
    d.doc150_number,
    d.visit_datetime,
    d.duration_seconds,
    DATEADD(year, -2000, r._Period) AS rg_period,
    CONVERT(varchar(8), r._RecorderTRef, 2) AS recorder_tref,
    CONVERT(varchar(32), r._RecorderRRef, 2) AS recorder_rref,
    CAST(r._RecordKind AS int) AS record_kind,
    CONVERT(varchar(2), r._Active, 2) AS active_hex,
    r._LineNo AS line_no,
    CONVERT(varchar(2), r._Fld3337_TYPE, 2) AS fld3337_type,
    CONVERT(varchar(8), r._Fld3337_RTRef, 2) AS fld3337_tref,
    CONVERT(varchar(32), r._Fld3337_RRRef, 2) AS fld3337_ref,
    CONVERT(varchar(2), r._Fld3338_TYPE, 2) AS fld3338_type,
    CONVERT(varchar(8), r._Fld3338_RTRef, 2) AS fld3338_tref,
    CONVERT(varchar(32), r._Fld3338_RRRef, 2) AS fld3338_ref,
    r._Fld3339 AS fld3339,
    r._Fld3340 AS fld3340,
    r._Fld3341 AS fld3341,
    r._Fld3342 AS fld3342,
    r._Fld3343 AS fld3343,
    r._Fld3344 AS fld3344,
    r._Fld3345 AS fld3345,
    r._Fld3346 AS fld3346,
    r._Fld3347 AS fld3347,
    CONVERT(varchar(32), r._Fld3348RRef, 2) AS fld3348_ref,
    CONVERT(varchar(32), r._Fld3349RRef, 2) AS fld3349_ref,
    r._Fld346 AS fld346
FROM #active_doc150 AS d
JOIN dbo._AccumRg3336 AS r
  ON r._RecorderRRef = d.doc150_ref_bin
ORDER BY d.document_number, d.visit_datetime, d.doc150_number;

SELECT
    'accumrg3336_active_summary_by_contract' AS probe,
    d.document_number,
    d.client_id,
    d.effective_client_fio,
    d.subscription_name,
    d.visit_limit,
    COUNT(*) AS rg3336_rows,
    COUNT(DISTINCT d.doc150_ref) AS distinct_doc150,
    SUM(CASE WHEN r._RecordKind = 0 THEN 1 ELSE 0 END) AS record_kind_0_rows,
    SUM(CASE WHEN r._RecordKind = 1 THEN 1 ELSE 0 END) AS record_kind_1_rows,
    SUM(CAST(r._Fld3339 AS decimal(18, 2))) AS sum_fld3339,
    SUM(CAST(r._Fld3340 AS decimal(18, 2))) AS sum_fld3340,
    SUM(CAST(r._Fld3341 AS decimal(18, 2))) AS sum_fld3341,
    SUM(CAST(r._Fld3342 AS decimal(18, 2))) AS sum_fld3342,
    SUM(CAST(r._Fld3343 AS decimal(18, 2))) AS sum_fld3343,
    SUM(CAST(r._Fld3344 AS decimal(18, 2))) AS sum_fld3344,
    SUM(CAST(r._Fld3345 AS decimal(18, 2))) AS sum_fld3345,
    SUM(CAST(r._Fld3346 AS decimal(18, 2))) AS sum_fld3346,
    SUM(CAST(r._Fld3347 AS decimal(18, 2))) AS sum_fld3347,
    MIN(d.visit_datetime) AS first_visit,
    MAX(d.visit_datetime) AS last_visit
FROM #active_doc150 AS d
JOIN dbo._AccumRg3336 AS r
  ON r._RecorderRRef = d.doc150_ref_bin
GROUP BY
    d.document_number,
    d.client_id,
    d.effective_client_fio,
    d.subscription_name,
    d.visit_limit
ORDER BY d.document_number;

SELECT
    'accumrg3336_active_summary_by_values' AS probe,
    CAST(r._RecordKind AS int) AS record_kind,
    CAST(r._Fld3339 AS decimal(18, 2)) AS fld3339,
    CAST(r._Fld3340 AS decimal(18, 2)) AS fld3340,
    CAST(r._Fld3341 AS decimal(18, 2)) AS fld3341,
    CAST(r._Fld3342 AS decimal(18, 2)) AS fld3342,
    CAST(r._Fld3343 AS decimal(18, 2)) AS fld3343,
    CAST(r._Fld3344 AS decimal(18, 2)) AS fld3344,
    CAST(r._Fld3345 AS decimal(18, 2)) AS fld3345,
    CAST(r._Fld3346 AS decimal(18, 2)) AS fld3346,
    CAST(r._Fld3347 AS decimal(18, 2)) AS fld3347,
    COUNT(*) AS rows_count
FROM #active_doc150 AS d
JOIN dbo._AccumRg3336 AS r
  ON r._RecorderRRef = d.doc150_ref_bin
GROUP BY
    CAST(r._RecordKind AS int),
    CAST(r._Fld3339 AS decimal(18, 2)),
    CAST(r._Fld3340 AS decimal(18, 2)),
    CAST(r._Fld3341 AS decimal(18, 2)),
    CAST(r._Fld3342 AS decimal(18, 2)),
    CAST(r._Fld3343 AS decimal(18, 2)),
    CAST(r._Fld3344 AS decimal(18, 2)),
    CAST(r._Fld3345 AS decimal(18, 2)),
    CAST(r._Fld3346 AS decimal(18, 2)),
    CAST(r._Fld3347 AS decimal(18, 2))
ORDER BY rows_count DESC, record_kind, fld3339, fld3344;
