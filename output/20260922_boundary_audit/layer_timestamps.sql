SELECT 'final_funnel_clients' AS layer, COUNT_BIG(*) AS rows_count, COUNT_BIG(cutoff_date) AS stamped_rows, CONVERT(varchar(19),MIN(cutoff_date),120) AS minimum, CONVERT(varchar(19),MAX(cutoff_date),120) AS maximum FROM fitbase_part2.final_funnel_clients
UNION ALL
SELECT 'membership_import_facts' AS layer, COUNT_BIG(*) AS rows_count, COUNT_BIG(cutoff_at) AS stamped_rows, CONVERT(varchar(19),MIN(cutoff_at),120) AS minimum, CONVERT(varchar(19),MAX(cutoff_at),120) AS maximum FROM fitbase_part2.membership_import_facts
UNION ALL
SELECT 'services_import_facts' AS layer, COUNT_BIG(*) AS rows_count, COUNT_BIG(cutoff_at) AS stamped_rows, CONVERT(varchar(19),MIN(cutoff_at),120) AS minimum, CONVERT(varchar(19),MAX(cutoff_at),120) AS maximum FROM fitbase_part2.services_import_facts;
