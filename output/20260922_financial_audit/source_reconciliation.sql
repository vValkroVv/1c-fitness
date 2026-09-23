
WITH links AS (
 SELECT DISTINCT m.subscription_ref, sale._IDRRef AS sale_ref
 FROM fitbase_part2.membership_import_facts m
 JOIN dbo._Document154_VT1137 line
  ON line._Fld1148_RTRef=0x000000A3
  AND line._Fld1148_RRRef=CONVERT(binary(16),m.subscription_ref,2)
 JOIN dbo._Document154 sale ON sale._IDRRef=line._Document154_IDRRef
 WHERE sale._Posted=0x01 AND sale._Marked=0x00
 AND CASE WHEN sale._Date_Time>'30000101' THEN DATEADD(year,-2000,sale._Date_Time)
     ELSE sale._Date_Time END <= '2026-09-22T20:12:12'
), by_sale AS (
 SELECT _Fld3308_RRRef AS sale_ref, COUNT_BIG(*) AS movements,
 SUM(CASE WHEN _RecordKind=1 THEN CAST(_Fld3311 AS decimal(15,2)) ELSE 0 END) AS charge,
 SUM(CASE WHEN _RecordKind=0 THEN CAST(_Fld3311 AS decimal(15,2)) ELSE 0 END) AS paid,
 SUM(CASE WHEN _RecordKind=1 THEN CAST(_Fld3311 AS decimal(15,2))
          WHEN _RecordKind=0 THEN -CAST(_Fld3311 AS decimal(15,2)) ELSE 0 END) AS debt
 FROM dbo._AccumRg3305
 WHERE _Active=0x01 AND _Fld3308_RTRef=0x0000009A
 AND CASE WHEN _Period>'30000101' THEN DATEADD(year,-2000,_Period)
     ELSE _Period END <= '2026-09-22T20:12:12'
 GROUP BY _Fld3308_RRRef
), by_membership AS (
 SELECT links.subscription_ref, SUM(COALESCE(s.movements,0)) AS movements,
 SUM(COALESCE(s.charge,0)) AS charge,SUM(COALESCE(s.paid,0)) AS paid,
 SUM(COALESCE(s.debt,0)) AS debt
 FROM links LEFT JOIN by_sale s ON s.sale_ref=links.sale_ref
 GROUP BY links.subscription_ref
)
SELECT COUNT_BIG(*) AS checked_facts,
 SUM(CASE WHEN m.financial_register_row_count<>COALESCE(r.movements,0) THEN 1 ELSE 0 END) AS movement_count_mismatches,
 SUM(CASE WHEN m.financial_register_charge_sum<>COALESCE(r.charge,0) THEN 1 ELSE 0 END) AS charge_mismatches,
 SUM(CASE WHEN m.financial_register_payment_sum<>COALESCE(r.paid,0) THEN 1 ELSE 0 END) AS paid_mismatches,
 SUM(CASE WHEN m.financial_register_signed_debt<>COALESCE(r.debt,0) THEN 1 ELSE 0 END) AS debt_mismatches,
 SUM(CASE WHEN m.financial_register_allocation_unambiguous=1 AND m.financial_register_row_count>0 THEN 1 ELSE 0 END) AS unambiguous_with_register,
 SUM(CASE WHEN m.financial_register_allocation_unambiguous=1 AND m.financial_register_signed_debt<0 THEN 1 ELSE 0 END) AS negative_register_debt_cases
FROM fitbase_part2.membership_import_facts m
LEFT JOIN by_membership r ON r.subscription_ref=m.subscription_ref
