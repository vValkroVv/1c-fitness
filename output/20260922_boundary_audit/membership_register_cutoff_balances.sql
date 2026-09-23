WITH named AS (
 SELECT *, CASE
  WHEN LOWER(subscription_name) LIKE N'%субаренд%'
   AND LOWER(subscription_name) NOT LIKE N'%безлимит%' THEN 'subrent'
  WHEN LOWER(subscription_name) LIKE N'%сайкл%'
   AND LOWER(subscription_name) NOT LIKE N'%безлимит%'
   AND (LOWER(subscription_name) LIKE N'%8 пос%' OR LOWER(subscription_name) LIKE N'%12 пос%') THEN 'cycle'
 END AS dimension_rule
 FROM fitbase_part2.membership_import_facts
), scope AS (
 SELECT * FROM named WHERE dimension_rule IS NOT NULL
), movements AS (
 SELECT s.subscription_ref,CASE WHEN r._Period > '3000-01-01' THEN DATEADD(year,-2000,r._Period) ELSE r._Period END AS period_at,r._RecordKind,
  CAST(r._Fld3339 AS decimal(15,3)) AS raw_quantity,
  CASE WHEN r._RecordKind=0 THEN CAST(r._Fld3339 AS decimal(15,3))
       WHEN r._RecordKind=1 THEN -CAST(r._Fld3339 AS decimal(15,3)) ELSE 0 END AS quantity
 FROM scope AS s JOIN dbo._AccumRg3336 AS r
  ON r._Fld3337_RRRef=CONVERT(binary(16),s.subscription_ref,2)
 WHERE r._Active=0x01 AND r._Fld3339<>0
 AND ((s.dimension_rule='subrent' AND r._Fld3338_TYPE=0x01 AND r._Fld3338_RTRef=0x00000000
       AND r._Fld3338_RRRef=0x00000000000000000000000000000000)
   OR (s.dimension_rule='cycle' AND r._Fld3338_TYPE=0x08 AND r._Fld3338_RTRef=0x00000048
       AND r._Fld3338_RRRef=0xAA9EA4BF01266AD311E8C6D3BB763918))
), balances AS (
 SELECT subscription_ref,
  SUM(CASE WHEN period_at<='2026-09-22 20:12:12' THEN quantity ELSE 0 END) AS expected_at_cutoff,
  SUM(CASE WHEN period_at<='2026-09-22 20:12:12' AND _RecordKind=0 THEN raw_quantity ELSE 0 END) AS expected_receipt,
  SUM(CASE WHEN period_at<='2026-09-22 20:12:12' AND _RecordKind=1 THEN raw_quantity ELSE 0 END) AS expected_expense,
  SUM(CASE WHEN period_at>'2026-09-22 20:12:12' THEN quantity ELSE 0 END) AS excluded_future_balance,
  SUM(CASE WHEN period_at>'2026-09-22 20:12:12' THEN 1 ELSE 0 END) AS excluded_future_rows,
  MAX(period_at) AS latest_register_movement
 FROM movements GROUP BY subscription_ref
)
SELECT s.document_number,s.client_id,s.subscription_ref,s.dimension_rule,
 s.subrent_rg3336_signed_balance AS actual_staging_balance,
 COALESCE(b.expected_at_cutoff,0) AS expected_at_cutoff,
 s.subrent_rg3336_receipt_qty AS actual_receipt,COALESCE(b.expected_receipt,0) AS expected_receipt,
 s.subrent_rg3336_expense_qty AS actual_expense,COALESCE(b.expected_expense,0) AS expected_expense,
 COALESCE(b.excluded_future_balance,0) AS excluded_future_balance,
 COALESCE(b.excluded_future_rows,0) AS excluded_future_rows,b.latest_register_movement
FROM scope AS s LEFT JOIN balances AS b ON b.subscription_ref=s.subscription_ref
ORDER BY s.document_number;
