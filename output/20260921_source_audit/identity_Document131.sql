SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT N'_Document131' table_name,
COUNT_BIG(j.[_IDRRef]) june_rows,
COUNT_BIG(s.[_IDRRef]) september_rows,
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL THEN 1 ELSE 0 END)) [retained],
SUM(CONVERT(bigint,CASE WHEN s.[_IDRRef] IS NULL THEN 1 ELSE 0 END)) [removed],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NULL THEN 1 ELSE 0 END)) [added],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Number])<>CONVERT(varbinary(max),s.[_Number]) OR (j.[_Number] IS NULL AND s.[_Number] IS NOT NULL) OR (j.[_Number] IS NOT NULL AND s.[_Number] IS NULL)) THEN 1 ELSE 0 END)) [changed_Number],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Date_Time])<>CONVERT(varbinary(max),s.[_Date_Time]) OR (j.[_Date_Time] IS NULL AND s.[_Date_Time] IS NOT NULL) OR (j.[_Date_Time] IS NOT NULL AND s.[_Date_Time] IS NULL)) THEN 1 ELSE 0 END)) [changed_Date_Time],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Posted])<>CONVERT(varbinary(max),s.[_Posted]) OR (j.[_Posted] IS NULL AND s.[_Posted] IS NOT NULL) OR (j.[_Posted] IS NOT NULL AND s.[_Posted] IS NULL)) THEN 1 ELSE 0 END)) [changed_Posted],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Marked])<>CONVERT(varbinary(max),s.[_Marked]) OR (j.[_Marked] IS NULL AND s.[_Marked] IS NOT NULL) OR (j.[_Marked] IS NOT NULL AND s.[_Marked] IS NULL)) THEN 1 ELSE 0 END)) [changed_Marked] FROM [FitnessRestored_20260630_original].dbo.[_Document131] j FULL JOIN [FitnessRestored_20260630_macos].dbo.[_Document131] s ON j.[_IDRRef]=s.[_IDRRef] FOR JSON PATH, INCLUDE_NULL_VALUES;
