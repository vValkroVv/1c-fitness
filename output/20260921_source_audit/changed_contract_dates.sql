SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT
        CONVERT(varchar(19),DATEADD(year,-2000,j._Date_Time),126) june_date,
        CONVERT(varchar(19),DATEADD(year,-2000,s._Date_Time),126) september_date,
        CONVERT(int,j._Posted) june_posted,CONVERT(int,s._Posted) september_posted,
        CONVERT(int,j._Marked) june_marked,CONVERT(int,s._Marked) september_marked
        FROM [FitnessRestored_20260630_original].dbo._Document163 j JOIN [FitnessRestored_20260630_macos].dbo._Document163 s ON s._IDRRef=j._IDRRef
        WHERE j._Date_Time<>s._Date_Time FOR JSON PATH, INCLUDE_NULL_VALUES;
