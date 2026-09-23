SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT '_Document152' table_name,COUNT_BIG(*) added_total,
            SUM(CONVERT(bigint,CASE WHEN s._Date_Time<='4026-06-30T23:27:03' THEN 1 ELSE 0 END)) [added_at_or_before_june],
            SUM(CONVERT(bigint,CASE WHEN s._Date_Time>'4026-06-30T23:27:03' AND s._Date_Time<='4026-09-20T20:12:12' THEN 1 ELSE 0 END)) [added_between_backups],
            SUM(CONVERT(bigint,CASE WHEN s._Date_Time>'4026-09-20T20:12:12' AND s._Date_Time<='4026-09-21T20:12:12' THEN 1 ELSE 0 END)) [added_in_effective_day],
            SUM(CONVERT(bigint,CASE WHEN s._Date_Time>'4026-09-21T20:12:12' THEN 1 ELSE 0 END)) [added_after_effective_cutoff],
            CONVERT(varchar(19),DATEADD(year,-2000,MIN(s._Date_Time)),126) added_min_date,
            CONVERT(varchar(19),DATEADD(year,-2000,MAX(s._Date_Time)),126) added_max_date
            FROM [FitnessRestored_20260630_macos].dbo.[_Document152] s LEFT JOIN [FitnessRestored_20260630_original].dbo.[_Document152] j ON j._IDRRef=s._IDRRef
            WHERE j._IDRRef IS NULL FOR JSON PATH, INCLUDE_NULL_VALUES;
