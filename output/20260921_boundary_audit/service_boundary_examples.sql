SELECT TOP (30) sale_line_id,sale_client_id,service_doc_number,sale_datetime,
 service_doc_datetime,payment_datetime,service_start_date,service_register_start_date,
 service_end_date,is_active_on_cutoff,is_active_by_date,is_active_by_balance,rg3336_signed_balance
FROM fitbase_part2.services_import_facts
WHERE service_end_date IN ('2026-09-20','2026-09-21')
 OR service_register_start_date IN ('2026-09-20','2026-09-21')
 OR sale_datetime>'2026-09-20 20:12:12' OR service_doc_datetime>'2026-09-20 20:12:12' OR payment_datetime>'2026-09-20 20:12:12'
ORDER BY service_end_date,sale_line_id;
