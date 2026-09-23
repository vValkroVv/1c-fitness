WITH ranked AS (
 SELECT m.document_number, m.client_id, m.subscription_ref, m.sale_datetime,
  m.start_date, m.end_date, m.is_active_on_cutoff, m.is_finished_before_cutoff,
  c.funnel AS sql_funnel,
  ROW_NUMBER() OVER (PARTITION BY m.end_date ORDER BY m.document_number,m.subscription_ref) AS rn
 FROM fitbase_part2.membership_import_facts AS m
 LEFT JOIN fitbase_part2.final_funnel_clients AS c ON c.client_ref=m.client_ref
 WHERE m.is_full_subscription=1 AND m.end_date IN ('2026-09-21','2026-09-22')
)
SELECT document_number,client_id,subscription_ref,sale_datetime,start_date,end_date,
 is_active_on_cutoff,is_finished_before_cutoff,sql_funnel
FROM ranked WHERE rn<=8 ORDER BY end_date,document_number;
