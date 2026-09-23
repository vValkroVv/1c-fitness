SELECT d._Number AS document_number, CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year,-2000,d._Date_Time) ELSE d._Date_Time END AS original_document_datetime,
 (SELECT COUNT_BIG(*) FROM fitbase_part2.stg_subscriptions_all AS s
  WHERE s.subscription_ref=CONVERT(varchar(32),d._IDRRef,2)) AS owner_staging_rows,
 (SELECT COUNT_BIG(*) FROM fitbase_part2.membership_import_facts AS m
  WHERE m.subscription_ref=CONVERT(varchar(32),d._IDRRef,2)) AS membership_staging_rows
FROM dbo._Document163 AS d WHERE CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year,-2000,d._Date_Time) ELSE d._Date_Time END>'2026-09-22 20:12:12'
ORDER BY d._Date_Time,d._Number;
