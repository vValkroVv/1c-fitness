WITH events AS (SELECT '_Document163' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document163
UNION ALL
SELECT '_Document154' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document154
UNION ALL
SELECT '_Document152' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document152
UNION ALL
SELECT '_Document138' AS source, _Number AS document_number, CASE WHEN _Date_Time > '3000-01-01' THEN DATEADD(year,-2000,_Date_Time) ELSE _Date_Time END AS event_at, CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked FROM dbo._Document138), ranked AS (
 SELECT *, ROW_NUMBER() OVER (PARTITION BY source,
  CASE WHEN event_at<='2026-09-22 20:12:12' THEN 'included_interval' ELSE 'after_cutoff' END
  ORDER BY event_at, document_number) AS rn
 FROM events WHERE event_at>'2026-09-20 20:12:12'
)
SELECT source, document_number, event_at, posted_unmarked,
 CASE WHEN event_at<='2026-09-22 20:12:12' THEN 'included_interval' ELSE 'after_cutoff' END AS interval
FROM ranked WHERE rn<=8 ORDER BY source, event_at, document_number;
