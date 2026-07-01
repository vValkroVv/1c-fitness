SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @service_doc_ref binary(16) = 0x8937F1EEDA60712241A7DB57CD3FACE9;

PRINT '01 package Document163 details';
SELECT
    CONVERT(varchar(32), d._IDRRef, 2) AS service_doc_ref,
    d._Number,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS doc_datetime,
    p._Description AS product_name,
    c._Code AS holder_id,
    c._Description AS holder_fio,
    CASE
        WHEN d._Fld1450 > '3000-01-01' THEN DATEADD(year, -2000, d._Fld1450)
        ELSE d._Fld1450
    END AS start_datetime,
    CASE
        WHEN d._Fld1482 > '3000-01-01' THEN DATEADD(year, -2000, d._Fld1482)
        ELSE d._Fld1482
    END AS end_datetime,
    d._Fld1481 AS duration_value
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference72 AS p
  ON p._IDRRef = d._Fld1446RRef
LEFT JOIN dbo._Reference64 AS c
  ON c._IDRRef = d._Fld9152RRef
WHERE d._IDRRef = @service_doc_ref;

PRINT '02 AccumRg3336 movements for package';
SELECT TOP (50)
    CONVERT(varchar(8), r._RecorderTRef, 2) AS recorder_tref,
    CONVERT(varchar(32), r._RecorderRRef, 2) AS recorder_ref,
    r._RecordKind,
    CASE
        WHEN r._Period > '3000-01-01' THEN DATEADD(year, -2000, r._Period)
        ELSE r._Period
    END AS period_datetime,
    CONVERT(varchar(8), r._Fld3338_TYPE, 2) AS dim_type,
    CONVERT(varchar(8), r._Fld3338_RTRef, 2) AS dim_rt,
    CONVERT(varchar(32), r._Fld3338_RRRef, 2) AS dim_rr,
    r._Fld3339
FROM dbo._AccumRg3336 AS r
WHERE r._Fld3337_RRRef = @service_doc_ref
ORDER BY r._Period, r._RecordKind;

PRINT '03 AccumRg3336 balance for package';
SELECT
    SUM(CASE
        WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3))
        WHEN r._RecordKind = 1 THEN -CAST(r._Fld3339 AS decimal(15, 3))
        ELSE 0
    END) AS signed_balance,
    SUM(CASE WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS receipt,
    SUM(CASE WHEN r._RecordKind = 1 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS expense,
    COUNT(*) AS movement_rows
FROM dbo._AccumRg3336 AS r
WHERE r._Active = 0x01
  AND r._Fld3337_RRRef = @service_doc_ref
  AND DATEADD(year, -2000, r._Period) <= @cutoff_at;

PRINT '04 InfoRg3060 for package';
SELECT TOP (20)
    CONVERT(varchar(32), _Fld3061RRef, 2) AS service_doc_ref,
    _Fld3065,
    _Fld3068,
    _Fld3069,
    _Fld3070,
    _Fld3072,
    _Fld5963,
    _Fld8007,
    _Fld8008,
    _Fld8009
FROM dbo._InfoRg3060
WHERE _Fld3061RRef = @service_doc_ref;

