SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @target_contract nvarchar(20) = N'00000130311';
DECLARE @old_fio nvarchar(200) = N'Сергеев Юрий Александрович';
DECLARE @new_fio nvarchar(200) = N'Сергеева Ирина Борисовна';

PRINT '01 current membership_import_facts rows for Sergeev/Sergeeva and target contract';

SELECT
    f.document_number,
    f.client_id,
    f.original_client_id,
    f.original_client_fio,
    f.effective_client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_datetime,
    f.start_date,
    f.end_date,
    f.rg_price,
    f.matched_payment_amount,
    f.matched_payment_method,
    f.owner_change_number,
    f.owner_change_datetime,
    f.owner_change_modifier_name,
    f.owner_change_count_for_membership,
    f.raw_source,
    f.subscription_ref
FROM fitbase_part2.membership_import_facts AS f
WHERE f.document_number = @target_contract
   OR f.effective_client_fio IN (@old_fio, @new_fio)
   OR f.original_client_fio IN (@old_fio, @new_fio)
ORDER BY f.effective_client_fio, f.sale_datetime, f.document_number;

PRINT '02 raw Document163 target contract';

SELECT
    d._Number AS document_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS document_ref,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS document_datetime,
    d._Posted AS posted,
    d._Marked AS marked,
    prod._Description AS product_name,
    holder._Code AS holder_9152_id,
    holder._Description AS holder_9152_fio,
    payer._Code AS payer_1447_id,
    payer._Description AS payer_1447_fio,
    org._Description AS organization_name
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference72 AS prod
  ON prod._IDRRef = d._Fld1446RRef
LEFT JOIN dbo._Reference64 AS holder
  ON holder._IDRRef = d._Fld9152RRef
LEFT JOIN dbo._Reference64 AS payer
  ON d._Fld1447_RTRef = 0x00000040
 AND payer._IDRRef = d._Fld1447_RRRef
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = d._Fld1443RRef
WHERE d._Number = @target_contract;

PRINT '03 all Document138 changes for target contract';

SELECT
    d._Number AS doc138_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS doc138_ref,
    CASE
        WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
        ELSE d._Date_Time
    END AS doc138_datetime,
    d._Posted AS posted,
    d._Marked AS marked,
    oldc._Code AS old_client_id,
    oldc._Description AS old_client_fio,
    newc._Code AS new_client_id,
    newc._Description AS new_client_fio,
    mod._Description AS modifier_name,
    op._Description AS operation_name
FROM dbo._Document163 AS m
JOIN dbo._Document138 AS d
  ON d._Fld763RRef = m._IDRRef
LEFT JOIN dbo._Reference64 AS oldc
  ON oldc._IDRRef = d._Fld762RRef
LEFT JOIN dbo._Reference64 AS newc
  ON newc._IDRRef = d._Fld767RRef
LEFT JOIN dbo._Reference72 AS mod
  ON mod._IDRRef = d._Fld764RRef
LEFT JOIN dbo._Reference72 AS op
  ON op._IDRRef = d._Fld761RRef
WHERE m._Number = @target_contract
ORDER BY doc138_datetime;

PRINT '04 latest owner if both owner-change modifiers are accepted';

WITH owner_changes AS (
    SELECT
        m._Number AS membership_number,
        d._Number AS owner_change_number,
        CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END AS owner_change_datetime,
        oldc._Code AS old_client_id,
        oldc._Description AS old_client_fio,
        newc._Code AS new_client_id,
        newc._Description AS new_client_fio,
        mod._Description AS modifier_name,
        ROW_NUMBER() OVER (
            PARTITION BY d._Fld763RRef
            ORDER BY d._Date_Time DESC, d._IDRRef DESC
        ) AS rn
    FROM dbo._Document163 AS m
    JOIN dbo._Document138 AS d
      ON d._Fld763RRef = m._IDRRef
    JOIN dbo._Reference72 AS mod
      ON mod._IDRRef = d._Fld764RRef
    LEFT JOIN dbo._Reference64 AS oldc
      ON oldc._IDRRef = d._Fld762RRef
    LEFT JOIN dbo._Reference64 AS newc
      ON newc._IDRRef = d._Fld767RRef
    WHERE m._Number = @target_contract
      AND d._Posted = 0x01
      AND d._Marked = 0x00
      AND LTRIM(RTRIM(mod._Description)) IN (
          N'Смена владельца',
          N'Смена владельца подарочной карты'
      )
)
SELECT *
FROM owner_changes
WHERE rn = 1;

PRINT '05 final funnel clients for Sergeev/Sergeeva';

SELECT
    client_id,
    client_fio,
    phones,
    funnel,
    funnel_step,
    normalized_club,
    selected_subscription_name,
    selected_subscription_start_date,
    selected_subscription_end_date
FROM fitbase_part2.final_funnel_clients
WHERE client_fio IN (@old_fio, @new_fio)
   OR client_id IN (
       SELECT f.client_id
       FROM fitbase_part2.membership_import_facts AS f
       WHERE f.document_number = @target_contract
   )
ORDER BY client_fio;

PRINT '06 visit docs by client for target contract';

DECLARE @target_subscription_ref binary(16) = (
    SELECT TOP (1) d._IDRRef
    FROM dbo._Document163 AS d
    WHERE d._Number = @target_contract
);

SELECT
    c989._Code AS visit_client_id,
    c989._Description AS visit_client_fio,
    COUNT_BIG(*) AS visit_docs,
    MIN(CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END) AS min_visit,
    MAX(CASE
            WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time)
            ELSE d._Date_Time
        END) AS max_visit
FROM dbo._Document150 AS d
LEFT JOIN dbo._Reference64 AS c989
  ON d._Fld989_RTRef = 0x00000040
 AND c989._IDRRef = d._Fld989_RRRef
WHERE d._Fld991_RRRef = @target_subscription_ref
  AND d._Posted = 0x01
  AND d._Marked = 0x00
GROUP BY c989._Code, c989._Description
ORDER BY min_visit;
