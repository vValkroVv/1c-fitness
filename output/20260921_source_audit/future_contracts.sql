SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT _Number contract_number,CONVERT(varchar(32),_IDRRef,2) contract_ref,
        CONVERT(varchar(19),DATEADD(year,-2000,_Date_Time),126) sale_date,
        CONVERT(int,_Posted) posted,CONVERT(int,_Marked) marked
        FROM [FitnessRestored_20260630_macos].dbo._Document163 WHERE _Date_Time>'4026-09-21T20:12:12' ORDER BY _Date_Time FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);
