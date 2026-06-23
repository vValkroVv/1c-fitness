SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @scan_from_raw datetime2(0) = '4026-04-01 00:00:00';
DECLARE @scan_to_raw datetime2(0) = '4026-06-30 23:59:59';

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
    holder_client_ref,
    payer_client_ref,
    product_ref
INTO #active_subrent
FROM fitbase_part2.membership_import_facts
WHERE is_limited_subrent = 1
  AND end_date >= CONVERT(date, @cutoff_at);

IF OBJECT_ID('tempdb..#target_refs') IS NOT NULL
    DROP TABLE #target_refs;

CREATE TABLE #target_refs (
    target_document_number nvarchar(20) NOT NULL,
    target_subscription_name nvarchar(200) NOT NULL,
    target_client_id nvarchar(20) NOT NULL,
    target_client_fio nvarchar(300) NOT NULL,
    target_start_date date NOT NULL,
    target_end_date date NOT NULL,
    ref_kind nvarchar(60) NOT NULL,
    ref binary(16) NOT NULL
);

INSERT INTO #target_refs(
    target_document_number,
    target_subscription_name,
    target_client_id,
    target_client_fio,
    target_start_date,
    target_end_date,
    ref_kind,
    ref
)
SELECT document_number, subscription_name, client_id, effective_client_fio, start_date, end_date,
       N'subscription_ref', CONVERT(binary(16), subscription_ref, 2)
FROM #active_subrent
UNION ALL
SELECT document_number, subscription_name, client_id, effective_client_fio, start_date, end_date,
       N'client_ref', CONVERT(binary(16), client_ref, 2)
FROM #active_subrent
UNION ALL
SELECT document_number, subscription_name, client_id, effective_client_fio, start_date, end_date,
       N'effective_client_ref', CONVERT(binary(16), effective_client_ref, 2)
FROM #active_subrent
UNION ALL
SELECT document_number, subscription_name, client_id, effective_client_fio, start_date, end_date,
       N'holder_client_ref', CONVERT(binary(16), holder_client_ref, 2)
FROM #active_subrent
UNION ALL
SELECT document_number, subscription_name, client_id, effective_client_fio, start_date, end_date,
       N'payer_client_ref', CONVERT(binary(16), payer_client_ref, 2)
FROM #active_subrent
UNION ALL
SELECT document_number, subscription_name, client_id, effective_client_fio, start_date, end_date,
       N'product_ref', CONVERT(binary(16), product_ref, 2)
FROM #active_subrent;

CREATE INDEX IX_target_refs_ref ON #target_refs(ref);

WITH document150_unpivot AS (
    SELECT
        d._IDRRef,
        d._Number,
        DATEADD(year, -2000, d._Date_Time) AS normalized_datetime,
        CONVERT(varchar(2), d._Posted, 2) AS posted_hex,
        CONVERT(varchar(2), d._Marked, 2) AS marked_hex,
        d._Fld5396,
        d._Fld7813,
        d._Fld993,
        d._Fld994,
        d._Fld995,
        d._Fld999,
        d._Fld1000,
        d._Fld1004,
        d._Fld7816,
        d._Fld8767,
        d._Fld8768,
        d._Fld9144,
        ref_column,
        ref_value
    FROM dbo._Document150 AS d
    CROSS APPLY (VALUES
        (N'_Fld988RRef', d._Fld988RRef),
        (N'_Fld989_RRRef', d._Fld989_RRRef),
        (N'_Fld990RRef', d._Fld990RRef),
        (N'_Fld991_RRRef', d._Fld991_RRRef),
        (N'_Fld992_RRRef', d._Fld992_RRRef),
        (N'_Fld7814RRef', d._Fld7814RRef),
        (N'_Fld998RRef', d._Fld998RRef),
        (N'_Fld1001RRef', d._Fld1001RRef),
        (N'_Fld1003RRef', d._Fld1003RRef),
        (N'_Fld1005RRef', d._Fld1005RRef),
        (N'_Fld8769RRef', d._Fld8769RRef),
        (N'_Fld8770RRef', d._Fld8770RRef)
    ) AS refs(ref_column, ref_value)
    WHERE d._Date_Time >= @scan_from_raw
      AND d._Date_Time <= @scan_to_raw
      AND d._Posted = 0x01
      AND d._Marked = 0x00
)
SELECT
    'document150_ref_match_summary' AS probe,
    ref_column,
    tr.ref_kind,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT tr.target_document_number) AS distinct_target_docs,
    COUNT(DISTINCT document150_unpivot._Number) AS distinct_doc150_rows,
    MIN(document150_unpivot.normalized_datetime) AS min_datetime,
    MAX(document150_unpivot.normalized_datetime) AS max_datetime
FROM document150_unpivot
JOIN #target_refs AS tr
  ON tr.ref = document150_unpivot.ref_value
GROUP BY ref_column, tr.ref_kind
ORDER BY rows_count DESC, ref_column, tr.ref_kind;

WITH document150_unpivot AS (
    SELECT
        d._IDRRef,
        d._Number,
        DATEADD(year, -2000, d._Date_Time) AS normalized_datetime,
        CONVERT(varchar(2), d._Posted, 2) AS posted_hex,
        CONVERT(varchar(2), d._Marked, 2) AS marked_hex,
        d._Fld5396,
        d._Fld7813,
        d._Fld993,
        d._Fld994,
        d._Fld995,
        d._Fld999,
        d._Fld1000,
        d._Fld1004,
        d._Fld7816,
        d._Fld8767,
        d._Fld8768,
        d._Fld9144,
        ref_column,
        ref_value
    FROM dbo._Document150 AS d
    CROSS APPLY (VALUES
        (N'_Fld988RRef', d._Fld988RRef),
        (N'_Fld989_RRRef', d._Fld989_RRRef),
        (N'_Fld990RRef', d._Fld990RRef),
        (N'_Fld991_RRRef', d._Fld991_RRRef),
        (N'_Fld992_RRRef', d._Fld992_RRRef),
        (N'_Fld7814RRef', d._Fld7814RRef),
        (N'_Fld998RRef', d._Fld998RRef),
        (N'_Fld1001RRef', d._Fld1001RRef),
        (N'_Fld1003RRef', d._Fld1003RRef),
        (N'_Fld1005RRef', d._Fld1005RRef),
        (N'_Fld8769RRef', d._Fld8769RRef),
        (N'_Fld8770RRef', d._Fld8770RRef)
    ) AS refs(ref_column, ref_value)
    WHERE d._Date_Time >= @scan_from_raw
      AND d._Date_Time <= @scan_to_raw
      AND d._Posted = 0x01
      AND d._Marked = 0x00
)
SELECT TOP (300)
    'document150_ref_match_samples' AS probe,
    tr.target_document_number,
    tr.target_client_id,
    tr.target_client_fio,
    tr.target_subscription_name,
    tr.target_start_date,
    tr.target_end_date,
    tr.ref_kind,
    d.ref_column,
    d._Number AS doc150_number,
    d.normalized_datetime,
    d._Fld5396,
    d._Fld7813,
    d._Fld993,
    d._Fld994,
    d._Fld995,
    d._Fld999,
    d._Fld1000,
    d._Fld1004,
    d._Fld7816,
    d._Fld8767,
    d._Fld8768,
    d._Fld9144,
    CONVERT(varchar(32), d._IDRRef, 2) AS doc150_ref
FROM document150_unpivot AS d
JOIN #target_refs AS tr
  ON tr.ref = d.ref_value
ORDER BY tr.target_client_id, d.normalized_datetime, d._Number, d.ref_column;

WITH target_client_docs AS (
    SELECT DISTINCT
        tr.target_document_number,
        tr.target_client_id,
        tr.target_client_fio,
        tr.target_subscription_name,
        tr.target_start_date,
        tr.target_end_date,
        d._IDRRef,
        d._Number,
        DATEADD(year, -2000, d._Date_Time) AS normalized_datetime,
        d._Fld995,
        d._Fld999,
        d._Fld1000,
        d._Fld1004,
        d._Fld7816,
        d._Fld9144
    FROM dbo._Document150 AS d
    JOIN #target_refs AS tr
      ON tr.ref_kind IN (N'client_ref', N'effective_client_ref', N'holder_client_ref', N'payer_client_ref')
     AND tr.ref IN (
         d._Fld988RRef,
         d._Fld989_RRRef,
         d._Fld990RRef,
         d._Fld991_RRRef,
         d._Fld992_RRRef,
         d._Fld7814RRef,
         d._Fld998RRef,
         d._Fld1001RRef,
         d._Fld1003RRef,
         d._Fld1005RRef,
         d._Fld8769RRef,
         d._Fld8770RRef
     )
    WHERE d._Date_Time >= @scan_from_raw
      AND d._Date_Time <= @scan_to_raw
      AND d._Posted = 0x01
      AND d._Marked = 0x00
)
SELECT
    'document150_counts_by_active_subrent_client' AS probe,
    target_document_number,
    target_client_id,
    target_client_fio,
    target_subscription_name,
    target_start_date,
    target_end_date,
    COUNT_BIG(*) AS doc150_rows_in_scan_window,
    SUM(CASE WHEN CONVERT(date, normalized_datetime) BETWEEN target_start_date AND target_end_date THEN 1 ELSE 0 END) AS doc150_rows_inside_subrent_period,
    MIN(normalized_datetime) AS min_datetime,
    MAX(normalized_datetime) AS max_datetime
FROM target_client_docs
GROUP BY
    target_document_number,
    target_client_id,
    target_client_fio,
    target_subscription_name,
    target_start_date,
    target_end_date
ORDER BY target_client_id, target_document_number;

