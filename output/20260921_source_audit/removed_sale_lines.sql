SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT CONVERT(varchar(19),DATEADD(year,-2000,d._Date_Time),126) sale_date,
        CONVERT(int,d._Posted) june_posted,CONVERT(int,sd._Posted) september_posted,
        CONVERT(int,d._Marked) june_marked,CONVERT(int,sd._Marked) september_marked,
        l._Fld1144 old_quantity,l._Fld1160 old_unit_amount,
        (SELECT COUNT_BIG(*) FROM [FitnessRestored_20260630_original].dbo._Document154_VT1137 x WHERE x._Document154_IDRRef=d._IDRRef) june_document_lines,
        (SELECT COUNT_BIG(*) FROM [FitnessRestored_20260630_macos].dbo._Document154_VT1137 x WHERE x._Document154_IDRRef=d._IDRRef) september_document_lines
        FROM [FitnessRestored_20260630_original].dbo._Document154_VT1137 l
        LEFT JOIN [FitnessRestored_20260630_macos].dbo._Document154_VT1137 s
          ON l._Document154_IDRRef=s._Document154_IDRRef AND l._KeyField=s._KeyField AND l._Fld346=s._Fld346
        JOIN [FitnessRestored_20260630_original].dbo._Document154 d ON d._IDRRef=l._Document154_IDRRef
        JOIN [FitnessRestored_20260630_macos].dbo._Document154 sd ON sd._IDRRef=d._IDRRef
        WHERE s._Document154_IDRRef IS NULL FOR JSON PATH, INCLUDE_NULL_VALUES;
