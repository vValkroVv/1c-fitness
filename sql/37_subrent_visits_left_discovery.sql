SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

SELECT
    @@SERVERNAME AS server_name,
    DB_NAME() AS database_name,
    @cutoff_at AS cutoff_at;

SELECT
    'membership_import_facts_subrent_counts' AS probe,
    is_subrent,
    is_limited_subrent,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS distinct_clients,
    MIN(sale_date) AS min_sale_date,
    MAX(sale_date) AS max_sale_date
FROM fitbase_part2.membership_import_facts
WHERE is_subrent = 1
GROUP BY is_subrent, is_limited_subrent
ORDER BY is_limited_subrent DESC;

SELECT
    'limited_subrent_by_name_in_facts' AS probe,
    subscription_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS distinct_clients,
    SUM(CASE WHEN end_date >= CONVERT(date, @cutoff_at) THEN 1 ELSE 0 END) AS active_on_cutoff_rows,
    SUM(CASE WHEN end_date < CONVERT(date, @cutoff_at) THEN 1 ELSE 0 END) AS ended_before_cutoff_rows,
    MIN(sale_date) AS min_sale_date,
    MAX(sale_date) AS max_sale_date,
    SUM(CASE WHEN rg_visits_candidate_8007 <> 0 THEN 1 ELSE 0 END) AS fld8007_nonzero,
    SUM(CASE WHEN rg_visits_candidate_8008 <> 0 THEN 1 ELSE 0 END) AS fld8008_nonzero,
    SUM(CASE WHEN rg_visits_candidate_8009 <> 0 THEN 1 ELSE 0 END) AS fld8009_nonzero,
    MIN(rg_visits_candidate_8008) AS min_fld8008,
    MAX(rg_visits_candidate_8008) AS max_fld8008
FROM fitbase_part2.membership_import_facts
WHERE is_limited_subrent = 1
GROUP BY subscription_name
ORDER BY rows_count DESC;

SELECT TOP (80)
    'limited_subrent_candidate_values_sample' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    sale_date,
    start_date,
    end_date,
    rg_price,
    rg_paid_candidate,
    rg_payment_count_candidate,
    rg_visits_candidate_8007,
    rg_visits_candidate_8008,
    rg_visits_candidate_8009,
    matched_payment_amount,
    matched_payment_method,
    matched_payment_match_source
FROM fitbase_part2.membership_import_facts
WHERE is_limited_subrent = 1
ORDER BY end_date DESC, sale_date DESC, document_number DESC;

IF OBJECT_ID('tempdb..#target_docs') IS NOT NULL
    DROP TABLE #target_docs;

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
    product_ref
INTO #target_docs
FROM fitbase_part2.membership_import_facts
WHERE document_number IN (
    N'00000150231', -- active 8 visits
    N'00000150143', -- active 15 visits
    N'00000150128', -- active 12 visits
    N'00000112123', -- old 20 visits
    N'00000116732'  -- old 10 visits
);

SELECT 'target_limited_subrent_docs' AS probe, * FROM #target_docs ORDER BY document_number;

IF OBJECT_ID('tempdb..#target_refs') IS NOT NULL
    DROP TABLE #target_refs;

CREATE TABLE #target_refs (
    document_number nvarchar(20) NOT NULL,
    ref_kind nvarchar(60) NOT NULL,
    ref binary(16) NOT NULL
);

INSERT INTO #target_refs(document_number, ref_kind, ref)
SELECT document_number, N'subscription_ref', CONVERT(binary(16), subscription_ref, 2)
FROM #target_docs
WHERE NULLIF(subscription_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, N'client_ref', CONVERT(binary(16), client_ref, 2)
FROM #target_docs
WHERE NULLIF(client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, N'effective_client_ref', CONVERT(binary(16), effective_client_ref, 2)
FROM #target_docs
WHERE NULLIF(effective_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, N'original_client_ref', CONVERT(binary(16), original_client_ref, 2)
FROM #target_docs
WHERE NULLIF(original_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, N'holder_client_ref', CONVERT(binary(16), holder_client_ref, 2)
FROM #target_docs
WHERE NULLIF(holder_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, N'payer_client_ref', CONVERT(binary(16), payer_client_ref, 2)
FROM #target_docs
WHERE NULLIF(payer_client_ref, N'') IS NOT NULL
UNION ALL
SELECT document_number, N'product_ref', CONVERT(binary(16), product_ref, 2)
FROM #target_docs
WHERE NULLIF(product_ref, N'') IS NOT NULL;

CREATE INDEX IX_target_refs_ref ON #target_refs(ref);

SELECT
    'inforg3060_candidate_fields_for_target_docs' AS probe,
    td.document_number,
    td.subscription_name,
    td.sale_date,
    td.end_date,
    r._Fld8007,
    r._Fld8008,
    r._Fld8009
FROM #target_docs AS td
JOIN dbo._InfoRg3060 AS r
  ON r._Fld3061RRef = CONVERT(binary(16), td.subscription_ref, 2)
ORDER BY td.document_number;

WITH candidate_column_matches AS (
    SELECT N'_InfoRg3060' AS table_name, N'_Fld3061RRef' AS column_name, tr.ref_kind, COUNT_BIG(*) AS rows_count
    FROM dbo._InfoRg3060 AS x
    JOIN #target_refs AS tr ON x._Fld3061RRef = tr.ref
    GROUP BY tr.ref_kind

    UNION ALL SELECT N'_AccumRg3206', N'_RecorderRRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._RecorderRRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld3207RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld3207RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld3208RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld3208RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld3209RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld3209RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld3210RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld3210RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld3211_RRRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld3211_RRRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld3212RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld3212RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld3215RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld3215RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld8017_RRRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld8017_RRRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3206', N'_Fld8018RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3206 AS x JOIN #target_refs AS tr ON x._Fld8018RRef = tr.ref GROUP BY tr.ref_kind

    UNION ALL SELECT N'_AccumRg3233', N'_RecorderRRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._RecorderRRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3234RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3234RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3236RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3236RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3239RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3239RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3235_RRRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3235_RRRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3243RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3243RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3244RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3244RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3237RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3237RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3240_RRRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3240_RRRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3241RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3241RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3238RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3238RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld8024RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld8024RRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld3242_RRRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld3242_RRRef = tr.ref GROUP BY tr.ref_kind
    UNION ALL SELECT N'_AccumRg3233', N'_Fld8025RRef', tr.ref_kind, COUNT_BIG(*)
    FROM dbo._AccumRg3233 AS x JOIN #target_refs AS tr ON x._Fld8025RRef = tr.ref GROUP BY tr.ref_kind
)
SELECT
    'candidate_register_reference_matches' AS probe,
    table_name,
    column_name,
    ref_kind,
    rows_count
FROM candidate_column_matches
WHERE rows_count > 0
ORDER BY table_name, column_name, ref_kind;

SELECT TOP (80)
    'accumrg3206_rows_matching_targets' AS probe,
    tr.document_number,
    tr.ref_kind,
    x._Period,
    CONVERT(varchar(8), x._RecorderTRef, 2) AS recorder_tref,
    CONVERT(varchar(32), x._RecorderRRef, 2) AS recorder_ref,
    x._LineNo,
    CONVERT(varchar(2), x._Active, 2) AS active_hex,
    CONVERT(varchar(32), x._Fld3207RRef, 2) AS fld3207_ref,
    CONVERT(varchar(32), x._Fld3208RRef, 2) AS fld3208_ref,
    CONVERT(varchar(32), x._Fld3209RRef, 2) AS fld3209_ref,
    CONVERT(varchar(32), x._Fld3210RRef, 2) AS fld3210_ref,
    CONVERT(varchar(8), x._Fld3211_RTRef, 2) AS fld3211_tref,
    CONVERT(varchar(32), x._Fld3211_RRRef, 2) AS fld3211_ref,
    CONVERT(varchar(32), x._Fld3212RRef, 2) AS fld3212_ref,
    x._Fld3214,
    CONVERT(varchar(32), x._Fld3215RRef, 2) AS fld3215_ref,
    CONVERT(varchar(8), x._Fld8017_RTRef, 2) AS fld8017_tref,
    CONVERT(varchar(32), x._Fld8017_RRRef, 2) AS fld8017_ref,
    CONVERT(varchar(32), x._Fld8018RRef, 2) AS fld8018_ref,
    x._Fld8019,
    x._Fld8020,
    x._Fld3216
FROM dbo._AccumRg3206 AS x
JOIN #target_refs AS tr
  ON tr.ref IN (
      x._RecorderRRef, x._Fld3207RRef, x._Fld3208RRef, x._Fld3209RRef,
      x._Fld3210RRef, x._Fld3211_RRRef, x._Fld3212RRef,
      x._Fld3215RRef, x._Fld8017_RRRef, x._Fld8018RRef
  )
ORDER BY x._Period DESC, tr.document_number;

SELECT TOP (80)
    'accumrg3233_rows_matching_targets' AS probe,
    tr.document_number,
    tr.ref_kind,
    x._Period,
    CONVERT(varchar(8), x._RecorderTRef, 2) AS recorder_tref,
    CONVERT(varchar(32), x._RecorderRRef, 2) AS recorder_ref,
    x._LineNo,
    CONVERT(varchar(2), x._Active, 2) AS active_hex,
    CONVERT(varchar(32), x._Fld3234RRef, 2) AS fld3234_ref,
    CONVERT(varchar(32), x._Fld3236RRef, 2) AS fld3236_ref,
    CONVERT(varchar(32), x._Fld3239RRef, 2) AS fld3239_ref,
    CONVERT(varchar(8), x._Fld3235_RTRef, 2) AS fld3235_tref,
    CONVERT(varchar(32), x._Fld3235_RRRef, 2) AS fld3235_ref,
    CONVERT(varchar(32), x._Fld3243RRef, 2) AS fld3243_ref,
    CONVERT(varchar(32), x._Fld3244RRef, 2) AS fld3244_ref,
    CONVERT(varchar(32), x._Fld3237RRef, 2) AS fld3237_ref,
    CONVERT(varchar(8), x._Fld3240_RTRef, 2) AS fld3240_tref,
    CONVERT(varchar(32), x._Fld3240_RRRef, 2) AS fld3240_ref,
    CONVERT(varchar(32), x._Fld3241RRef, 2) AS fld3241_ref,
    CONVERT(varchar(32), x._Fld3238RRef, 2) AS fld3238_ref,
    CONVERT(varchar(32), x._Fld8024RRef, 2) AS fld8024_ref,
    CONVERT(varchar(8), x._Fld3242_RTRef, 2) AS fld3242_tref,
    CONVERT(varchar(32), x._Fld3242_RRRef, 2) AS fld3242_ref,
    CONVERT(varchar(32), x._Fld8025RRef, 2) AS fld8025_ref,
    x._Fld3245,
    x._Fld3249,
    x._Fld3246,
    x._Fld3247,
    x._Fld3248,
    x._Fld8026
FROM dbo._AccumRg3233 AS x
JOIN #target_refs AS tr
  ON tr.ref IN (
      x._RecorderRRef, x._Fld3234RRef, x._Fld3236RRef, x._Fld3239RRef,
      x._Fld3235_RRRef, x._Fld3243RRef, x._Fld3244RRef, x._Fld3237RRef,
      x._Fld3240_RRRef, x._Fld3241RRef, x._Fld3238RRef, x._Fld8024RRef,
      x._Fld3242_RRRef, x._Fld8025RRef
  )
ORDER BY x._Period DESC, tr.document_number;

