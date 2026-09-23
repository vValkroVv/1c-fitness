SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT N'_Reference59' table_name,
COUNT_BIG(j.[_IDRRef]) june_rows,
COUNT_BIG(s.[_IDRRef]) september_rows,
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL THEN 1 ELSE 0 END)) [retained],
SUM(CONVERT(bigint,CASE WHEN s.[_IDRRef] IS NULL THEN 1 ELSE 0 END)) [removed],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NULL THEN 1 ELSE 0 END)) [added],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Code])<>CONVERT(varbinary(max),s.[_Code]) OR (j.[_Code] IS NULL AND s.[_Code] IS NOT NULL) OR (j.[_Code] IS NOT NULL AND s.[_Code] IS NULL)) THEN 1 ELSE 0 END)) [changed_Code],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Marked])<>CONVERT(varbinary(max),s.[_Marked]) OR (j.[_Marked] IS NULL AND s.[_Marked] IS NOT NULL) OR (j.[_Marked] IS NOT NULL AND s.[_Marked] IS NULL)) THEN 1 ELSE 0 END)) [changed_Marked],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld3750_RRRef])<>CONVERT(varbinary(max),s.[_Fld3750_RRRef]) OR (j.[_Fld3750_RRRef] IS NULL AND s.[_Fld3750_RRRef] IS NOT NULL) OR (j.[_Fld3750_RRRef] IS NOT NULL AND s.[_Fld3750_RRRef] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld3750_RRRef],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld3753])<>CONVERT(varbinary(max),s.[_Fld3753]) OR (j.[_Fld3753] IS NULL AND s.[_Fld3753] IS NOT NULL) OR (j.[_Fld3753] IS NOT NULL AND s.[_Fld3753] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld3753],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld3756])<>CONVERT(varbinary(max),s.[_Fld3756]) OR (j.[_Fld3756] IS NULL AND s.[_Fld3756] IS NOT NULL) OR (j.[_Fld3756] IS NOT NULL AND s.[_Fld3756] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld3756],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld3751])<>CONVERT(varbinary(max),s.[_Fld3751]) OR (j.[_Fld3751] IS NULL AND s.[_Fld3751] IS NOT NULL) OR (j.[_Fld3751] IS NOT NULL AND s.[_Fld3751] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld3751] FROM [FitnessRestored_20260630_original].dbo.[_Reference59] j FULL JOIN [FitnessRestored_20260630_macos].dbo.[_Reference59] s ON j.[_IDRRef]=s.[_IDRRef] FOR JSON PATH, INCLUDE_NULL_VALUES;
