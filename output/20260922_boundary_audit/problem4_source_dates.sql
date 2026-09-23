SELECT m.document_number,m.client_id,m.sale_datetime,m.start_date,m.end_date,m.cutoff_at,
 CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year,-2000,d._Date_Time) ELSE d._Date_Time END AS original_document_datetime,
 CONVERT(date,CASE WHEN r._Fld3063 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3063) ELSE r._Fld3063 END) AS original_start_date,
 CONVERT(date,CASE WHEN r._Fld3064 > '3000-01-01' THEN DATEADD(year,-2000,r._Fld3064) ELSE r._Fld3064 END) AS original_end_date
FROM fitbase_part2.membership_import_facts AS m
JOIN dbo._Document163 AS d ON d._IDRRef=CONVERT(binary(16),m.subscription_ref,2)
JOIN dbo._InfoRg3060 AS r ON r._Fld3061RRef=d._IDRRef
WHERE TRY_CONVERT(bigint,m.document_number)=151350;
