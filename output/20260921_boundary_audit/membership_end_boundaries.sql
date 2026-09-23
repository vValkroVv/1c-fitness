SELECT end_date, is_full_subscription, is_active_on_cutoff, is_finished_before_cutoff,
 COUNT_BIG(*) AS contract_rows, COUNT(DISTINCT client_id) AS unique_clients
FROM fitbase_part2.membership_import_facts
WHERE end_date IN ('2026-09-20','2026-09-21')
GROUP BY end_date,is_full_subscription,is_active_on_cutoff,is_finished_before_cutoff
ORDER BY end_date,is_full_subscription,is_active_on_cutoff;
