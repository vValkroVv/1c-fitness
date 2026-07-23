SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

USE FitnessRestored_20260630_macos;

DECLARE @cutoff_at datetime2(0) = '2026-06-30 23:27:03';

DROP TABLE IF EXISTS #targets;
DROP TABLE IF EXISTS #memberships;
DROP TABLE IF EXISTS #sales;
DROP TABLE IF EXISTS #register_totals;
DROP TABLE IF EXISTS #direct_payment_docs;
DROP TABLE IF EXISTS #direct_payment_totals;

CREATE TABLE #targets (
    case_no int NOT NULL PRIMARY KEY,
    contract_id nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL UNIQUE,
    manager_sale_number bigint NOT NULL,
    manager_sold decimal(15, 2) NOT NULL,
    manager_paid decimal(15, 2) NOT NULL,
    manager_debt decimal(15, 2) NOT NULL
);

INSERT INTO #targets (
    case_no,
    contract_id,
    manager_sale_number,
    manager_sold,
    manager_paid,
    manager_debt
)
VALUES
    (1, N'00000152426', 35181, 10990, 10990, 10990),
    (2, N'00000148035', 15279, 11990, 11989,  2998),
    (3, N'00000141165', 57938, 15990,  7995,  7995),
    (4, N'00000146238',  5970, 11990,  5995,  5995),
    (5, N'00000146001',  5200,  9900,  4950,  4950),
    (6, N'00000151758', 33506, 10990,  8243,  2747),
    (7, N'00000142187', 63153, 12990,  6496,  6494),
    (8, N'00000146660',  8317, 14990, 14990,  7495),
    (9, N'00000146533',  7610, 11990, 10000,  1990),
    (10, N'00000151875', 33846, 10990, 8243, 5495);

SELECT
    t.*,
    d163._IDRRef AS membership_ref,
    client._Code AS client_id,
    client._Description AS client_fio,
    CASE
        WHEN d163._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, d163._Date_Time)
        ELSE d163._Date_Time
    END AS membership_datetime,
    CAST(info._Fld3070 AS decimal(15, 2)) AS info_fld3070,
    CAST(info._Fld3072 AS decimal(15, 2)) AS info_fld3072
INTO #memberships
FROM #targets AS t
JOIN dbo._Document163 AS d163
  ON d163._Number = t.contract_id
LEFT JOIN dbo._Reference64 AS client
  ON client._IDRRef = d163._Fld1447_RRRef
OUTER APPLY (
    SELECT TOP (1)
        rg._Fld3070,
        rg._Fld3072
    FROM dbo._InfoRg3060 AS rg
    WHERE rg._Fld3061RRef = d163._IDRRef
) AS info;

SELECT
    m.case_no,
    m.contract_id,
    sale._IDRRef AS sale_ref,
    sale._Number AS sale_number,
    CASE
        WHEN sale._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, sale._Date_Time)
        ELSE sale._Date_Time
    END AS sale_datetime,
    SUM(CAST(line._Fld1160 AS decimal(15, 2))) AS sale_line_sum,
    COUNT_BIG(*) AS sale_line_count
INTO #sales
FROM #memberships AS m
JOIN dbo._Document154_VT1137 AS line
  ON line._Fld1148_RTRef = 0x000000A3
 AND line._Fld1148_RRRef = m.membership_ref
JOIN dbo._Document154 AS sale
  ON sale._IDRRef = line._Document154_IDRRef
 AND sale._Posted = 0x01
 AND sale._Marked = 0x00
WHERE
    CASE
        WHEN sale._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, sale._Date_Time)
        ELSE sale._Date_Time
    END <= @cutoff_at
GROUP BY
    m.case_no,
    m.contract_id,
    sale._IDRRef,
    sale._Number,
    CASE
        WHEN sale._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, sale._Date_Time)
        ELSE sale._Date_Time
    END;

SELECT
    s.case_no,
    s.contract_id,
    SUM(
        CASE WHEN rg._RecordKind = 1
             THEN CAST(rg._Fld3311 AS decimal(15, 2))
             ELSE 0 END
    ) AS register_charge_sum,
    SUM(
        CASE WHEN rg._RecordKind = 0
             THEN CAST(rg._Fld3311 AS decimal(15, 2))
             ELSE 0 END
    ) AS register_payment_sum,
    SUM(
        CASE
            WHEN rg._RecordKind = 1 THEN CAST(rg._Fld3311 AS decimal(15, 2))
            WHEN rg._RecordKind = 0 THEN -CAST(rg._Fld3311 AS decimal(15, 2))
            ELSE 0
        END
    ) AS register_signed_debt,
    COUNT_BIG(*) AS register_rows
INTO #register_totals
FROM #sales AS s
JOIN dbo._AccumRg3305 AS rg
  ON rg._Active = 0x01
 AND rg._Fld3308_RTRef = 0x0000009A
 AND rg._Fld3308_RRRef = s.sale_ref
WHERE
    CASE
        WHEN rg._Period > '3000-01-01'
        THEN DATEADD(year, -2000, rg._Period)
        ELSE rg._Period
    END <= @cutoff_at
GROUP BY
    s.case_no,
    s.contract_id;

SELECT
    s.case_no,
    s.contract_id,
    payment._IDRRef AS payment_ref,
    payment._Number AS payment_number,
    CASE
        WHEN payment._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, payment._Date_Time)
        ELSE payment._Date_Time
    END AS payment_datetime,
    CAST(payment._Fld1080 AS decimal(15, 2)) AS payment_document_total,
    SUM(CAST(link._Fld1090 AS decimal(15, 2))) AS payment_link_allocated,
    method._Description AS payment_method
INTO #direct_payment_docs
FROM #sales AS s
JOIN dbo._Document152_VT1083 AS link
  ON link._Fld1087_RTRef = 0x0000009A
 AND link._Fld1087_RRRef = s.sale_ref
JOIN dbo._Document152 AS payment
  ON payment._IDRRef = link._Document152_IDRRef
 AND payment._Posted = 0x01
 AND payment._Marked = 0x00
LEFT JOIN dbo._Reference125 AS method
  ON method._IDRRef = payment._Fld1074RRef
WHERE
    CASE
        WHEN payment._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, payment._Date_Time)
        ELSE payment._Date_Time
    END <= @cutoff_at
GROUP BY
    s.case_no,
    s.contract_id,
    payment._IDRRef,
    payment._Number,
    CASE
        WHEN payment._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, payment._Date_Time)
        ELSE payment._Date_Time
    END,
    CAST(payment._Fld1080 AS decimal(15, 2)),
    method._Description;

SELECT
    case_no,
    contract_id,
    COUNT_BIG(*) AS direct_payment_doc_count,
    SUM(payment_document_total) AS direct_payment_document_sum,
    SUM(payment_link_allocated) AS direct_payment_allocated_sum
INTO #direct_payment_totals
FROM #direct_payment_docs
GROUP BY
    case_no,
    contract_id;

PRINT '01 per-contract reconstruction';
SELECT
    m.case_no,
    m.contract_id,
    m.client_id,
    m.client_fio,
    s.sale_number,
    s.sale_datetime,
    m.manager_sold,
    m.manager_paid,
    m.manager_debt,
    m.info_fld3070,
    m.info_fld3072,
    s.sale_line_sum,
    rt.register_charge_sum,
    rt.register_payment_sum,
    rt.register_signed_debt,
    dpt.direct_payment_doc_count,
    dpt.direct_payment_document_sum,
    dpt.direct_payment_allocated_sum,
    CASE
        WHEN TRY_CONVERT(bigint, s.sale_number) = m.manager_sale_number
        THEN 1 ELSE 0
    END AS assigned_manager_sale_number_matches_db,
    CASE WHEN m.manager_sold = s.sale_line_sum THEN 1 ELSE 0 END
        AS sold_matches_sale_line,
    CASE WHEN m.manager_debt = m.info_fld3072 THEN 1 ELSE 0 END
        AS debt_matches_info_fld3072,
    CASE WHEN m.manager_paid = rt.register_payment_sum THEN 1 ELSE 0 END
        AS paid_matches_register
FROM #memberships AS m
LEFT JOIN #sales AS s
  ON s.case_no = m.case_no
LEFT JOIN #register_totals AS rt
  ON rt.case_no = m.case_no
LEFT JOIN #direct_payment_totals AS dpt
  ON dpt.case_no = m.case_no
ORDER BY m.case_no;

PRINT '02 allocated register movements';
SELECT
    s.case_no,
    s.contract_id,
    CASE
        WHEN rg._Period > '3000-01-01'
        THEN DATEADD(year, -2000, rg._Period)
        ELSE rg._Period
    END AS movement_datetime,
    rg._RecordKind AS record_kind,
    CONVERT(varchar(8), rg._RecorderTRef, 2) AS recorder_tref,
    CASE
        WHEN rg._RecorderTRef = 0x0000009A THEN sale_recorder._Number
        WHEN rg._RecorderTRef = 0x00000098 THEN payment_recorder._Number
        WHEN rg._RecorderTRef = 0x00000083 THEN refund_recorder._Number
        ELSE CONVERT(varchar(32), rg._RecorderRRef, 2)
    END AS recorder_number,
    CAST(rg._Fld3311 AS decimal(15, 2)) AS allocated_amount
FROM #sales AS s
JOIN dbo._AccumRg3305 AS rg
  ON rg._Active = 0x01
 AND rg._Fld3308_RTRef = 0x0000009A
 AND rg._Fld3308_RRRef = s.sale_ref
LEFT JOIN dbo._Document154 AS sale_recorder
  ON rg._RecorderTRef = 0x0000009A
 AND sale_recorder._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document152 AS payment_recorder
  ON rg._RecorderTRef = 0x00000098
 AND payment_recorder._IDRRef = rg._RecorderRRef
LEFT JOIN dbo._Document131 AS refund_recorder
  ON rg._RecorderTRef = 0x00000083
 AND refund_recorder._IDRRef = rg._RecorderRRef
WHERE
    CASE
        WHEN rg._Period > '3000-01-01'
        THEN DATEADD(year, -2000, rg._Period)
        ELSE rg._Period
    END <= @cutoff_at
ORDER BY
    s.case_no,
    movement_datetime,
    rg._RecordKind,
    recorder_number;

PRINT '03 distinct direct payment documents';
SELECT
    case_no,
    contract_id,
    payment_number,
    payment_datetime,
    payment_document_total,
    payment_link_allocated,
    payment_method
FROM #direct_payment_docs
ORDER BY
    case_no,
    payment_datetime,
    payment_number;
