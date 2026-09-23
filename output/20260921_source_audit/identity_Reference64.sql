SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT N'_Reference64' table_name,
COUNT_BIG(j.[_IDRRef]) june_rows,
COUNT_BIG(s.[_IDRRef]) september_rows,
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL THEN 1 ELSE 0 END)) [retained],
SUM(CONVERT(bigint,CASE WHEN s.[_IDRRef] IS NULL THEN 1 ELSE 0 END)) [removed],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NULL THEN 1 ELSE 0 END)) [added],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Code])<>CONVERT(varbinary(max),s.[_Code]) OR (j.[_Code] IS NULL AND s.[_Code] IS NOT NULL) OR (j.[_Code] IS NOT NULL AND s.[_Code] IS NULL)) THEN 1 ELSE 0 END)) [changed_Code],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Description])<>CONVERT(varbinary(max),s.[_Description]) OR (j.[_Description] IS NULL AND s.[_Description] IS NOT NULL) OR (j.[_Description] IS NOT NULL AND s.[_Description] IS NULL)) THEN 1 ELSE 0 END)) [changed_Description],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Marked])<>CONVERT(varbinary(max),s.[_Marked]) OR (j.[_Marked] IS NULL AND s.[_Marked] IS NOT NULL) OR (j.[_Marked] IS NOT NULL AND s.[_Marked] IS NULL)) THEN 1 ELSE 0 END)) [changed_Marked],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld3822])<>CONVERT(varbinary(max),s.[_Fld3822]) OR (j.[_Fld3822] IS NULL AND s.[_Fld3822] IS NOT NULL) OR (j.[_Fld3822] IS NOT NULL AND s.[_Fld3822] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld3822],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld3832])<>CONVERT(varbinary(max),s.[_Fld3832]) OR (j.[_Fld3832] IS NULL AND s.[_Fld3832] IS NOT NULL) OR (j.[_Fld3832] IS NOT NULL AND s.[_Fld3832] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld3832],
SUM(CONVERT(bigint,CASE WHEN j.[_IDRRef] IS NOT NULL AND s.[_IDRRef] IS NOT NULL AND (CONVERT(varbinary(max),j.[_Fld3831RRef])<>CONVERT(varbinary(max),s.[_Fld3831RRef]) OR (j.[_Fld3831RRef] IS NULL AND s.[_Fld3831RRef] IS NOT NULL) OR (j.[_Fld3831RRef] IS NOT NULL AND s.[_Fld3831RRef] IS NULL)) THEN 1 ELSE 0 END)) [changed_Fld3831RRef] FROM [FitnessRestored_20260630_original].dbo.[_Reference64] j FULL JOIN [FitnessRestored_20260630_macos].dbo.[_Reference64] s ON j.[_IDRRef]=s.[_IDRRef] FOR JSON PATH, INCLUDE_NULL_VALUES;
