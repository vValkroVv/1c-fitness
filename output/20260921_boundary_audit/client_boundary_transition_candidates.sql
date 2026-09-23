WITH states AS (
 SELECT client_ref, client_id,
 MAX(CASE WHEN sale_datetime<='2026-09-20 20:12:12' AND end_date>='2026-09-20' THEN 1 ELSE 0 END) AS active_at_finish,
 MAX(CASE WHEN sale_datetime<='2026-09-21 20:12:12' AND end_date>='2026-09-21' THEN 1 ELSE 0 END) AS active_at_cutoff,
 MAX(end_date) AS last_end_date
 FROM fitbase_part2.stg_subscriptions_all WHERE is_full_subscription=1
 GROUP BY client_ref,client_id
)
SELECT s.client_id,s.active_at_finish,s.active_at_cutoff,s.last_end_date,c.funnel AS sql_funnel
FROM states AS s LEFT JOIN fitbase_part2.final_funnel_clients AS c ON c.client_ref=s.client_ref
WHERE s.active_at_finish<>s.active_at_cutoff ORDER BY s.client_id;
