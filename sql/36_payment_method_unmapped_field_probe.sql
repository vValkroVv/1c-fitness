SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF OBJECT_ID('tempdb..#payment_probe') IS NOT NULL
    DROP TABLE #payment_probe;

SELECT
    f.matched_payment_match_source,
    CASE
        WHEN f.matched_payment_method IS NULL OR LTRIM(RTRIM(f.matched_payment_method)) = N'' THEN N'<empty>'
        ELSE f.matched_payment_method
    END AS payment_method,
    f.matched_payment_operation,
    p._Fld1082 AS payment_comment,
    CASE
        WHEN NULLIF(LTRIM(RTRIM(p._Fld1073)), N'') IS NOT NULL
          OR NULLIF(LTRIM(RTRIM(p._Fld1078)), N'') IS NOT NULL
          OR NULLIF(LTRIM(RTRIM(p._Fld1075)), N'') IS NOT NULL
          OR NULLIF(LTRIM(RTRIM(p._Fld1076)), N'') IS NOT NULL
          OR NULLIF(LTRIM(RTRIM(p._Fld1077)), N'') IS NOT NULL THEN 1
        ELSE 0
    END AS has_bank_card_fields,
    CASE WHEN NULLIF(LTRIM(RTRIM(p._Fld1078)), N'') IS NOT NULL THEN 1 ELSE 0 END AS has_masked_card,
    CASE WHEN NULLIF(LTRIM(RTRIM(p._Fld1082)), N'') IS NOT NULL THEN 1 ELSE 0 END AS has_payment_comment,
    f.subscription_ref,
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_datetime,
    f.rg_price,
    f.matched_payment_ref,
    f.matched_payment_amount,
    p._Number AS payment_number,
    p._Fld1073,
    p._Fld1078,
    p._Fld1075,
    p._Fld1076,
    p._Fld1077
INTO #payment_probe
FROM fitbase_part2.membership_import_facts AS f
JOIN dbo._Document152 AS p
  ON CONVERT(varchar(32), p._IDRRef, 2) = f.matched_payment_ref
WHERE f.matched_payment_ref IS NOT NULL
  AND (
      f.matched_payment_method IS NULL
      OR LTRIM(RTRIM(f.matched_payment_method)) = N''
      OR (
          LOWER(f.matched_payment_method) NOT LIKE N'%сбп%'
          AND LOWER(f.matched_payment_method) NOT LIKE N'%сбпр%'
          AND NOT (LOWER(f.matched_payment_method) LIKE N'%налич%' AND LOWER(f.matched_payment_method) NOT LIKE N'%безнал%')
          AND LOWER(f.matched_payment_method) NOT LIKE N'%эквайр%'
          AND LOWER(f.matched_payment_method) NOT LIKE N'%банк%'
          AND LOWER(f.matched_payment_method) NOT LIKE N'%безнал%'
          AND LOWER(f.matched_payment_method) NOT LIKE N'%терминал%'
          AND LOWER(f.matched_payment_method) NOT LIKE N'%карта%'
          AND LOWER(f.matched_payment_method) NOT LIKE N'%р/с%'
      )
  );

SELECT
    'unmapped_payment_field_summary' AS probe,
    payment_method,
    matched_payment_match_source,
    has_bank_card_fields,
    has_masked_card,
    has_payment_comment,
    COUNT_BIG(*) AS rows_count
FROM #payment_probe
GROUP BY
    payment_method,
    matched_payment_match_source,
    has_bank_card_fields,
    has_masked_card,
    has_payment_comment
ORDER BY rows_count DESC;

SELECT TOP (80)
    'unmapped_payment_field_examples' AS probe,
    payment_method,
    matched_payment_match_source,
    client_id,
    effective_client_fio,
    document_number,
    subscription_name,
    sale_datetime,
    rg_price,
    payment_number,
    matched_payment_amount,
    matched_payment_operation,
    payment_comment,
    _Fld1073,
    _Fld1078,
    _Fld1075,
    _Fld1076,
    _Fld1077
FROM #payment_probe
ORDER BY
    payment_method,
    sale_datetime DESC,
    document_number;
