SELECT
 CONVERT(varchar(32),d._IDRRef,2) AS contract_ref,
 LTRIM(RTRIM(d._Number)) AS contract_id,
 CONVERT(varchar(32),p._IDRRef,2) AS product_ref,
 LTRIM(RTRIM(p._Code)) AS product_code,p._Description AS product_name,
 d._Date_Time AS document_date_raw,
 CASE WHEN d._Date_Time>'30000101' THEN DATEADD(year,-2000,d._Date_Time) ELSE d._Date_Time END AS document_date,
 CONVERT(int,d._Posted) AS posted,CONVERT(int,d._Marked) AS marked,
 d._Fld1481 AS document_duration,
 r._Fld3062 AS register_3062_raw,r._Fld3063 AS register_start_raw,r._Fld3064 AS register_end_raw,
 CASE WHEN r._Fld3063>'30000101' THEN DATEADD(year,-2000,r._Fld3063) ELSE r._Fld3063 END AS register_start,
 CASE WHEN r._Fld3064>'30000101' THEN DATEADD(year,-2000,r._Fld3064) ELSE r._Fld3064 END AS register_end,
 DATEDIFF(day,r._Fld3063,r._Fld3064)+1 AS interval_days,
 r._Fld3065 AS register_duration_days,r._Fld3068 AS register_freeze_days,
 r._Fld3069 AS register_guests,r._Fld3070 AS register_price,r._Fld3072 AS register_debt_candidate,
 st._Description AS status
FROM [FitnessRestored_20260630_original].dbo._Document163 d
JOIN [FitnessRestored_20260630_original].dbo._Reference72 p ON p._IDRRef=d._Fld1446RRef
LEFT JOIN [FitnessRestored_20260630_original].dbo._InfoRg3060 r ON r._Fld3061RRef=d._IDRRef
LEFT JOIN [FitnessRestored_20260630_original].dbo._Reference5062 st ON st._IDRRef=r._Fld5960RRef
WHERE LOWER(p._Description) IN (N'абонемент мультикарта 12 месяцев (3 месяца заморозки в подарок)',N'абонемент мультикарта 12 месяцев (рассрочка)',N'абонемент мультикарта 12 месяцев + подарок (спецпредложение) рассрочка',N'абонемент сайкл 12 пос без клубной карты',N'абонемент ультра 15 месяцев + 3 месяца заморозки в подарок(ровио)',N'абонемент ультра 9 месяцев (3 месяца заморозки в подарок)',N'ультра 12 месяцев (рассрочка)',N'абонемент мультикарта 12 месяцев (спецпредложение) рассрочка')
ORDER BY d._Number OPTION (MAXDOP 2);
