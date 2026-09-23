SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
WITH j AS (SELECT _Fld3337_TYPE,_Fld3337_RTRef,_Fld3337_RRRef,
            _Fld3338_TYPE,_Fld3338_RTRef,_Fld3338_RRRef,
            COUNT_BIG(*) n,SUM(CAST(CASE WHEN _RecordKind=0 THEN _Fld3339 ELSE -_Fld3339 END AS decimal(38,3))) balance
            FROM [FitnessRestored_20260630_original].dbo._AccumRg3336 WHERE _Active=0x01 AND _Period<='4026-06-30T23:27:03'
            GROUP BY _Fld3337_TYPE,_Fld3337_RTRef,_Fld3337_RRRef,_Fld3338_TYPE,_Fld3338_RTRef,_Fld3338_RRRef),s AS (SELECT _Fld3337_TYPE,_Fld3337_RTRef,_Fld3337_RRRef,
            _Fld3338_TYPE,_Fld3338_RTRef,_Fld3338_RRRef,
            COUNT_BIG(*) n,SUM(CAST(CASE WHEN _RecordKind=0 THEN _Fld3339 ELSE -_Fld3339 END AS decimal(38,3))) balance
            FROM [FitnessRestored_20260630_macos].dbo._AccumRg3336 WHERE _Active=0x01 AND _Period<='4026-06-30T23:27:03'
            GROUP BY _Fld3337_TYPE,_Fld3337_RTRef,_Fld3337_RRRef,_Fld3338_TYPE,_Fld3338_RTRef,_Fld3338_RRRef)
        SELECT CONVERT(varchar(8),COALESCE(j._Fld3337_RTRef,s._Fld3337_RTRef),2) contract_dimension_type,
        CONVERT(varchar(8),COALESCE(j._Fld3338_RTRef,s._Fld3338_RTRef),2) secondary_dimension_type,
        COUNT_BIG(*) all_groups,
        SUM(CONVERT(bigint,CASE WHEN j.n IS NOT NULL AND s.n IS NOT NULL THEN 1 ELSE 0 END)) [retained_groups],
        SUM(CONVERT(bigint,CASE WHEN s.n IS NULL THEN 1 ELSE 0 END)) [removed_groups], SUM(CONVERT(bigint,CASE WHEN j.n IS NULL THEN 1 ELSE 0 END)) [added_groups],
        SUM(CONVERT(bigint,CASE WHEN COALESCE(j.balance,0)<>COALESCE(s.balance,0) THEN 1 ELSE 0 END)) [changed_balance_groups],
        SUM(CONVERT(bigint,CASE WHEN COALESCE(j.n,0)<>COALESCE(s.n,0) THEN 1 ELSE 0 END)) [changed_row_count_groups],
        SUM(COALESCE(j.balance,0)) june_balance,SUM(COALESCE(s.balance,0)) september_historical_balance,
        SUM(ABS(COALESCE(s.balance,0)-COALESCE(j.balance,0))) total_absolute_balance_change
        FROM j FULL JOIN s ON j._Fld3337_TYPE=s._Fld3337_TYPE AND j._Fld3337_RTRef=s._Fld3337_RTRef AND j._Fld3337_RRRef=s._Fld3337_RRRef AND j._Fld3338_TYPE=s._Fld3338_TYPE AND j._Fld3338_RTRef=s._Fld3338_RTRef AND j._Fld3338_RRRef=s._Fld3338_RRRef
        GROUP BY COALESCE(j._Fld3337_RTRef,s._Fld3337_RTRef),COALESCE(j._Fld3338_RTRef,s._Fld3338_RTRef) FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);
