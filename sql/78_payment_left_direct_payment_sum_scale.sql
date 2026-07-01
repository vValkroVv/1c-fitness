SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';

WITH direct_payment_rows AS (
    SELECT
        f.document_number AS contract_id,
        p._Number AS payment_number,
        CASE WHEN p._Date_Time > '3000-01-01'
             THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END AS payment_datetime,
        CAST(p._Fld1080 AS decimal(15, 2)) AS payment_amount,
        pm._Description AS payment_method
    FROM fitbase_part2.membership_import_facts AS f
    JOIN dbo._Document154_VT1137 AS sale_line
      ON sale_line._Fld1148_RTRef = 0x000000A3
     AND sale_line._Fld1148_RRRef = CONVERT(binary(16), f.subscription_ref, 2)
    JOIN dbo._Document154 AS sale_doc
      ON sale_doc._IDRRef = sale_line._Document154_IDRRef
     AND sale_doc._Posted = 0x01
     AND sale_doc._Marked = 0x00
    JOIN dbo._Document152_VT1083 AS payment_line
      ON payment_line._Fld1087_RTRef = 0x0000009A
     AND payment_line._Fld1087_RRRef = sale_doc._IDRRef
    JOIN dbo._Document152 AS p
      ON p._IDRRef = payment_line._Document152_IDRRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = p._Fld1074RRef
    WHERE p._Posted = 0x01
      AND p._Marked = 0x00
      AND p._Fld1080 IS NOT NULL
      AND p._Fld1080 > 0
      AND CASE WHEN p._Date_Time > '3000-01-01'
               THEN DATEADD(year, -2000, p._Date_Time) ELSE p._Date_Time END <= @cutoff_at
),
direct_payment_sum AS (
    SELECT
        contract_id,
        COUNT_BIG(*) AS direct_payment_count,
        SUM(payment_amount) AS direct_payment_sum,
        STRING_AGG(CONCAT(payment_number, N'@', CONVERT(varchar(19), payment_datetime, 120), N'=', payment_amount), N'; ') AS direct_payment_numbers,
        STRING_AGG(COALESCE(payment_method, N'<empty>'), N'; ') AS direct_payment_methods
    FROM direct_payment_rows
    GROUP BY contract_id
)
SELECT
    CONCAT(
        contract_id, N'|',
        direct_payment_count, N'|',
        direct_payment_sum, N'|',
        REPLACE(COALESCE(direct_payment_numbers, N''), CHAR(10), N' '), N'|',
        REPLACE(COALESCE(direct_payment_methods, N''), CHAR(10), N' ')
    ) AS audit_line
FROM direct_payment_sum
ORDER BY contract_id;
