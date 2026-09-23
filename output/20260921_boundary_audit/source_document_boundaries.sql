WITH events AS (SELECT '_Document163' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document163
UNION ALL
SELECT '_Document154' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document154
UNION ALL
SELECT '_Document152' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document152
UNION ALL
SELECT '_Document138' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document138)
SELECT source, COUNT_BIG(*) AS total_documents,
 SUM(CASE WHEN event_at>'2026-09-20 20:12:12' AND event_at<='2026-09-21 20:12:12' THEN 1 ELSE 0 END) AS between_finish_and_cutoff,
 SUM(CASE WHEN event_at>'2026-09-20 20:12:12' AND event_at<='2026-09-21 20:12:12' AND posted_unmarked=1 THEN 1 ELSE 0 END) AS posted_between_finish_and_cutoff,
 SUM(CASE WHEN event_at>'2026-09-21 20:12:12' THEN 1 ELSE 0 END) AS after_cutoff,
 SUM(CASE WHEN event_at='2026-09-21 20:12:12' THEN 1 ELSE 0 END) AS exactly_at_cutoff,
 MIN(CASE WHEN event_at>'2026-09-20 20:12:12' THEN event_at END) AS first_after_finish,
 MAX(event_at) AS latest_source_document
FROM events GROUP BY source ORDER BY source;
