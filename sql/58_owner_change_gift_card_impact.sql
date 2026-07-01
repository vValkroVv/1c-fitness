SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

WITH all_owner_changes AS (
    SELECT
        d._IDRRef AS owner_change_ref_bin,
        d._Number AS owner_change_number,
        CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END AS owner_change_datetime,
        d._Fld763RRef AS membership_ref_bin,
        d._Fld762RRef AS old_client_ref_bin,
        d._Fld767RRef AS new_client_ref_bin,
        mod._Description AS modifier_name,
        sale._Number AS membership_number,
        prod._Description AS membership_name,
        ROW_NUMBER() OVER (
            PARTITION BY d._Fld763RRef
            ORDER BY d._Date_Time DESC, d._IDRRef DESC
        ) AS owner_change_rank,
        COUNT(*) OVER (PARTITION BY d._Fld763RRef) AS owner_change_count_for_membership
    FROM dbo._Document138 AS d
    JOIN dbo._Reference72 AS mod
      ON mod._IDRRef = d._Fld764RRef
    LEFT JOIN dbo._Document163 AS sale
      ON sale._IDRRef = d._Fld763RRef
    LEFT JOIN dbo._Reference72 AS prod
      ON prod._IDRRef = sale._Fld1446RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
          END <= @cutoff_at
      AND d._Fld762RRef <> 0x00000000000000000000000000000000
      AND d._Fld767RRef <> 0x00000000000000000000000000000000
      AND d._Fld763RRef <> 0x00000000000000000000000000000000
      AND sale._IDRRef IS NOT NULL
      AND LTRIM(RTRIM(mod._Description)) IN (
          N'Смена владельца',
          N'Смена владельца подарочной карты'
      )
),
latest_any AS (
    SELECT
        CONVERT(varchar(32), owner_change_ref_bin, 2) AS owner_change_ref,
        owner_change_number,
        owner_change_datetime,
        CONVERT(varchar(32), membership_ref_bin, 2) AS membership_ref,
        membership_number,
        membership_name,
        CONVERT(varchar(32), old_client_ref_bin, 2) AS old_client_ref,
        old_client._Code AS old_client_id,
        old_client._Description AS old_client_fio,
        CONVERT(varchar(32), new_client_ref_bin, 2) AS new_client_ref,
        new_client._Code AS new_client_id,
        new_client._Description AS new_client_fio,
        modifier_name,
        owner_change_count_for_membership
    FROM all_owner_changes AS oc
    LEFT JOIN dbo._Reference64 AS old_client
      ON old_client._IDRRef = oc.old_client_ref_bin
    LEFT JOIN dbo._Reference64 AS new_client
      ON new_client._IDRRef = oc.new_client_ref_bin
    WHERE owner_change_rank = 1
)
SELECT
    f.document_number,
    f.subscription_ref,
    f.client_id AS current_effective_client_id,
    f.effective_client_fio AS current_effective_client_fio,
    f.owner_change_number AS current_owner_change_number,
    f.owner_change_datetime AS current_owner_change_datetime,
    f.owner_change_modifier_name AS current_owner_change_modifier_name,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.rg_price,
    f.matched_payment_amount,
    la.owner_change_number AS latest_any_owner_change_number,
    la.owner_change_datetime AS latest_any_owner_change_datetime,
    la.modifier_name AS latest_any_modifier_name,
    la.old_client_id AS latest_any_old_client_id,
    la.old_client_fio AS latest_any_old_client_fio,
    la.new_client_id AS latest_any_new_client_id,
    la.new_client_fio AS latest_any_new_client_fio,
    fc.client_id AS latest_new_client_in_final_import
INTO #current_rows
FROM fitbase_part2.membership_import_facts AS f
JOIN latest_any AS la
  ON la.membership_ref = f.subscription_ref
LEFT JOIN fitbase_part2.final_funnel_clients AS fc
  ON fc.client_id = la.new_client_id;

SELECT
    'impact_summary' AS section,
    COUNT_BIG(*) AS rows_with_any_owner_change,
    SUM(CASE
        WHEN latest_any_new_client_id <> current_effective_client_id THEN 1
        ELSE 0
    END) AS rows_where_effective_owner_would_change,
    SUM(CASE
        WHEN latest_any_new_client_id <> current_effective_client_id
         AND latest_new_client_in_final_import IS NOT NULL THEN 1
        ELSE 0
    END) AS changed_rows_latest_owner_in_final_import,
    SUM(CASE
        WHEN latest_any_new_client_id <> current_effective_client_id
         AND latest_new_client_in_final_import IS NULL THEN 1
        ELSE 0
    END) AS changed_rows_latest_owner_not_in_final_import
FROM #current_rows;

SELECT
    'impact_by_latest_modifier' AS section,
    latest_any_modifier_name,
    COUNT_BIG(*) AS rows_count,
    SUM(CASE
        WHEN latest_any_new_client_id <> current_effective_client_id THEN 1
        ELSE 0
    END) AS owner_would_change,
    SUM(CASE
        WHEN latest_any_new_client_id <> current_effective_client_id
         AND latest_new_client_in_final_import IS NOT NULL THEN 1
        ELSE 0
    END) AS owner_would_change_to_final_client,
    SUM(CASE
        WHEN latest_any_new_client_id <> current_effective_client_id
         AND latest_new_client_in_final_import IS NULL THEN 1
        ELSE 0
    END) AS owner_would_change_to_non_final_client
FROM #current_rows
GROUP BY latest_any_modifier_name
ORDER BY rows_count DESC;

SELECT TOP (50)
    'changed_owner_samples' AS section,
    document_number,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    current_effective_client_id,
    current_effective_client_fio,
    current_owner_change_number,
    current_owner_change_datetime,
    current_owner_change_modifier_name,
    latest_any_owner_change_number,
    latest_any_owner_change_datetime,
    latest_any_modifier_name,
    latest_any_old_client_id,
    latest_any_old_client_fio,
    latest_any_new_client_id,
    latest_any_new_client_fio,
    latest_new_client_in_final_import,
    rg_price,
    matched_payment_amount
FROM #current_rows
WHERE latest_any_new_client_id <> current_effective_client_id
ORDER BY latest_any_owner_change_datetime DESC, document_number;

SELECT
    'target_contract_after_corrected_owner_change' AS section,
    document_number,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    current_effective_client_id,
    current_effective_client_fio,
    current_owner_change_number,
    current_owner_change_datetime,
    latest_any_owner_change_number,
    latest_any_owner_change_datetime,
    latest_any_modifier_name,
    latest_any_old_client_id,
    latest_any_old_client_fio,
    latest_any_new_client_id,
    latest_any_new_client_fio,
    latest_new_client_in_final_import
FROM #current_rows
WHERE document_number = N'00000100483';
