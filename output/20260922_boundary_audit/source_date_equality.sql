SELECT 'membership_sale_start_end' AS check_name,COUNT_BIG(*) AS checked_rows,
 (SELECT COUNT_BIG(*) FROM fitbase_part2.membership_import_facts AS m WHERE NOT EXISTS (
SELECT 1 FROM dbo._Document163 AS d JOIN dbo._InfoRg3060 AS r ON r._Fld3061RRef=d._IDRRef
WHERE d._IDRRef=CONVERT(binary(16),m.subscription_ref,2)
 AND m.sale_datetime=CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year,-2000,d._Date_Time) ELSE d._Date_Time END
 AND m.start_date=CONVERT(date,CASE WHEN r._Fld3063 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3063) ELSE r._Fld3063 END)
 AND m.end_date=CONVERT(date,CASE WHEN r._Fld3064 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3064) ELSE r._Fld3064 END)
)) AS mismatched_rows
FROM fitbase_part2.membership_import_facts
UNION ALL
SELECT 'service_sale',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE NOT EXISTS (
SELECT 1 FROM dbo._Document154 AS d WHERE d._IDRRef=CONVERT(binary(16),s.sale_doc_ref,2)
AND s.sale_datetime=CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year,-2000,d._Date_Time) ELSE d._Date_Time END
))
FROM fitbase_part2.services_import_facts
UNION ALL
SELECT 'service_document',COUNT_BIG(service_doc_datetime),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE service_doc_datetime IS NOT NULL AND NOT EXISTS (
SELECT 1 FROM dbo._Document163 AS d WHERE d._IDRRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND s.service_doc_datetime=CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year,-2000,d._Date_Time) ELSE d._Date_Time END
))
FROM fitbase_part2.services_import_facts
UNION ALL
SELECT 'service_document_start',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE linked_service_doc_ref IS NOT NULL AND NOT EXISTS (
SELECT 1 FROM dbo._Document163 AS d WHERE d._IDRRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND (s.service_start_date=CONVERT(date,CASE WHEN d._Fld1450 > '3000-01-01' THEN DATEADD(year,-2000,d._Fld1450) ELSE d._Fld1450 END)
 OR (s.service_start_date IS NULL AND CONVERT(date,CASE WHEN d._Fld1450 > '3000-01-01' THEN DATEADD(year,-2000,d._Fld1450) ELSE d._Fld1450 END)<='2001-01-02'))
))
FROM fitbase_part2.services_import_facts WHERE linked_service_doc_ref IS NOT NULL
UNION ALL
SELECT 'service_register_start',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE linked_service_doc_ref IS NOT NULL AND NOT EXISTS (
SELECT 1 FROM dbo._InfoRg3060 AS r WHERE r._Fld3061RRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND (s.service_register_start_date=CONVERT(date,CASE WHEN r._Fld3063 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3063) ELSE r._Fld3063 END)
 OR (s.service_register_start_date IS NULL AND CONVERT(date,CASE WHEN r._Fld3063 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3063) ELSE r._Fld3063 END)<='2001-01-02'))
))
FROM fitbase_part2.services_import_facts WHERE linked_service_doc_ref IS NOT NULL
UNION ALL
SELECT 'service_real_end_date',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE linked_service_doc_ref IS NOT NULL AND NOT EXISTS (
SELECT 1 FROM dbo._InfoRg3060 AS r WHERE r._Fld3061RRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND (s.service_end_date=CONVERT(date,CASE WHEN r._Fld3064 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3064) ELSE r._Fld3064 END)
 OR (s.service_end_date IS NULL AND CONVERT(date,CASE WHEN r._Fld3064 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3064) ELSE r._Fld3064 END)<='2001-01-02'))
))
FROM fitbase_part2.services_import_facts WHERE linked_service_doc_ref IS NOT NULL;
