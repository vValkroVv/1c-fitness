SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT N'_Document152_VT1083' table_name,
COUNT_BIG(j.[_Document152_IDRRef]) june_rows,
COUNT_BIG(s.[_Document152_IDRRef]) september_rows,
SUM(CONVERT(bigint,CASE WHEN j.[_Document152_IDRRef] IS NOT NULL AND s.[_Document152_IDRRef] IS NOT NULL THEN 1 ELSE 0 END)) [retained],
SUM(CONVERT(bigint,CASE WHEN s.[_Document152_IDRRef] IS NULL THEN 1 ELSE 0 END)) [removed],
SUM(CONVERT(bigint,CASE WHEN j.[_Document152_IDRRef] IS NULL THEN 1 ELSE 0 END)) [added],
SUM(CONVERT(bigint,CASE WHEN j.[_Document152_IDRRef] IS NOT NULL AND s.[_Document152_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld1087_RRRef])<>CONVERT(varbinary(max),s.[_Fld1087_RRRef]) OR (j.[_Fld1087_RRRef] IS NULL AND s.[_Fld1087_RRRef] IS NOT NULL) OR (j.[_Fld1087_RRRef] IS NOT NULL AND s.[_Fld1087_RRRef] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld1087_RRRef] FROM [FitnessRestored_20260630_original].dbo.[_Document152_VT1083] j FULL JOIN [FitnessRestored_20260630_macos].dbo.[_Document152_VT1083] s ON j.[_Document152_IDRRef]=s.[_Document152_IDRRef] AND j.[_KeyField]=s.[_KeyField] AND j.[_Fld346]=s.[_Fld346] FOR JSON PATH, INCLUDE_NULL_VALUES;
