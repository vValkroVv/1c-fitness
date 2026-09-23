SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT COUNT_BIG(*) replaced_lines,
        SUM(CONVERT(bigint,CASE WHEN j._Fld1087_RRRef=replacement._Fld1087_RRRef THEN 1 ELSE 0 END)) [same_linked_sale]
        FROM [FitnessRestored_20260630_original].dbo._Document152_VT1083 j
        LEFT JOIN [FitnessRestored_20260630_macos].dbo._Document152_VT1083 oldkey
          ON j._Document152_IDRRef=oldkey._Document152_IDRRef AND j._KeyField=oldkey._KeyField AND j._Fld346=oldkey._Fld346
        JOIN [FitnessRestored_20260630_macos].dbo._Document152_VT1083 replacement ON replacement._Document152_IDRRef=j._Document152_IDRRef
        WHERE oldkey._Document152_IDRRef IS NULL FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);
