SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @target_amount decimal(15, 2) = 7995.00;
DECLARE @target_sale datetime2(0) = '2026-01-20 15:27:56';
DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @client_ref binary(16) = CONVERT(binary(16), 'AB24A4BF01266AD411EB750008980D3E', 2);

PRINT '01 same client all sales/payments after target';
SELECT
    CASE WHEN rg._Period > '3000-01-01'
         THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END AS movement_datetime,
    CONVERT(varchar(8), rg._RecorderTRef, 2) AS recorder_tref,
    CASE
        WHEN rg._RecorderTRef = 0x00000098 THEN p._Number
        WHEN rg._RecorderTRef = 0x0000009A THEN s._Number
        ELSE CONVERT(varchar(32), rg._RecorderRRef, 2)
    END AS recorder_number,
    rg._RecordKind AS record_kind,
    linked_sale._Number AS linked_sale_number,
    CAST(rg._Fld3311 AS decimal(15, 2)) AS amount_3311,
    pm._Description AS payment_method,
    sale_client._Code AS sale_client_id,
    sale_client._Description AS sale_client_fio
FROM dbo._AccumRg3305 AS rg
LEFT JOIN dbo._Document152 AS p
  ON rg._RecorderTRef = 0x00000098 AND p._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Document154 AS s
  ON rg._RecorderTRef = 0x0000009A AND s._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document154 AS linked_sale
  ON rg._Fld3308_RTRef = 0x0000009A AND linked_sale._IDRRef = rg._Fld3308_RRRef
LEFT JOIN dbo._Reference64 AS sale_client
  ON sale_client._IDRRef = linked_sale._Fld1119RRef
WHERE rg._Fld3307_RTRef = 0x00000040
  AND rg._Fld3307_RRRef = @client_ref
  AND CASE WHEN rg._Period > '3000-01-01'
           THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END >= @target_sale
  AND CASE WHEN rg._Period > '3000-01-01'
           THEN DATEADD(year, -2000, rg._Period) ELSE rg._Period END <= @cutoff_at
ORDER BY movement_datetime, recorder_number;

PRINT '02 global sales with amount 7995 and product like abonement/fitness near target';
WITH sale_lines AS (
    SELECT
        d._IDRRef AS sale_doc_ref_bin,
        d._Number AS sale_number,
        CASE WHEN d._Date_Time > '3000-01-01'
             THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END AS sale_datetime,
        client._Code AS sale_client_id,
        client._Description AS sale_client_fio,
        SUM(CAST(l._Fld1160 AS decimal(15, 2))) AS sale_line_sum,
        STRING_AGG(CONCAT(prod._Description, N' [', CAST(l._Fld1160 AS decimal(15, 2)), N']'), N'; ') AS sale_lines
    FROM dbo._Document154 AS d
    JOIN dbo._Document154_VT1137 AS l
      ON l._Document154_IDRRef = d._IDRRef
    LEFT JOIN dbo._Reference72 AS prod
      ON prod._IDRRef = l._Fld1146RRef
    LEFT JOIN dbo._Reference64 AS client
      ON client._IDRRef = d._Fld1119RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND CASE WHEN d._Date_Time > '3000-01-01'
               THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END >= DATEADD(day, -7, @target_sale)
      AND CASE WHEN d._Date_Time > '3000-01-01'
               THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END <= DATEADD(day, 180, @target_sale)
    GROUP BY
        d._IDRRef,
        d._Number,
        CASE WHEN d._Date_Time > '3000-01-01'
             THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END,
        client._Code,
        client._Description
)
SELECT
    sl.sale_number,
    sl.sale_datetime,
    sl.sale_client_id,
    sl.sale_client_fio,
    sl.sale_line_sum,
    sl.sale_lines
FROM sale_lines AS sl
WHERE ABS(sl.sale_line_sum - @target_amount) <= 5
  AND (
        LOWER(sl.sale_lines) LIKE N'%абонемент%'
     OR LOWER(sl.sale_lines) LIKE N'%фитнес%'
     OR LOWER(sl.sale_lines) LIKE N'%fitness%'
  )
ORDER BY ABS(DATEDIFF(second, sl.sale_datetime, @target_sale)), sl.sale_datetime;

PRINT '03 global payment documents amount 7995 near target';
SELECT TOP (100)
    p._Number AS payment_number,
    CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
    CAST(p._Fld1080 AS decimal(15, 2)) AS payment_total,
    pm._Description AS payment_method,
    op._Description AS payment_operation,
    c1._Code AS client_1057_id,
    c1._Description AS client_1057_fio,
    c2._Code AS client_1058_id,
    c2._Description AS client_1058_fio
FROM dbo._Document152 AS p
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
LEFT JOIN dbo._Reference64 AS c1
  ON p._Fld1057_RTRef = 0x00000040 AND c1._IDRRef = p._Fld1057_RRRef
LEFT JOIN dbo._Reference64 AS c2
  ON c2._IDRRef = p._Fld1058RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND ABS(CAST(p._Fld1080 AS decimal(15, 2)) - @target_amount) <= 5
  AND CASE WHEN p._Date_Time > '3000-01-01'
           THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END >= DATEADD(day, -7, @target_sale)
  AND CASE WHEN p._Date_Time > '3000-01-01'
           THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END <= DATEADD(day, 180, @target_sale)
ORDER BY ABS(DATEDIFF(second, CASE WHEN p._Date_Time > '3000-01-01'
         THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END, @target_sale));
