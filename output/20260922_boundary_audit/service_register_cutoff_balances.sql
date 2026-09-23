WITH scope AS (
 SELECT DISTINCT linked_service_doc_ref FROM fitbase_part2.services_import_facts
 WHERE linked_service_doc_ref IS NOT NULL
), movements AS (
 SELECT scope.linked_service_doc_ref,CASE WHEN r._Period > '3000-01-01' THEN DATEADD(year,-2000,r._Period) ELSE r._Period END AS period_at,
  CASE WHEN r._RecordKind=0 THEN CAST(r._Fld3339 AS decimal(15,3))
       WHEN r._RecordKind=1 THEN -CAST(r._Fld3339 AS decimal(15,3)) ELSE 0 END AS quantity
 FROM scope JOIN dbo._AccumRg3336 AS r
  ON r._Fld3337_RRRef=CONVERT(binary(16),scope.linked_service_doc_ref,2)
 WHERE r._Active=0x01 AND r._Fld3339<>0
), balances AS (
 SELECT linked_service_doc_ref,
  SUM(CASE WHEN period_at<='2026-09-22 20:12:12' THEN quantity ELSE 0 END) AS expected_at_cutoff,
  SUM(CASE WHEN period_at>'2026-09-22 20:12:12' THEN quantity ELSE 0 END) AS excluded_future_balance,
  SUM(CASE WHEN period_at>'2026-09-22 20:12:12' THEN 1 ELSE 0 END) AS excluded_future_rows,
  MAX(period_at) AS latest_register_movement
 FROM movements GROUP BY linked_service_doc_ref
)
SELECT s.sale_line_id,s.service_doc_number,s.linked_service_doc_ref,
 s.rg3336_signed_balance AS actual_staging_balance,
 COALESCE(b.expected_at_cutoff,0) AS expected_at_cutoff,
 COALESCE(b.excluded_future_balance,0) AS excluded_future_balance,
 COALESCE(b.excluded_future_rows,0) AS excluded_future_rows,b.latest_register_movement
FROM fitbase_part2.services_import_facts AS s
LEFT JOIN balances AS b ON b.linked_service_doc_ref=s.linked_service_doc_ref
ORDER BY s.sale_line_id;
