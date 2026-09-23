SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT COUNT_BIG(*) replaced_lines,
        SUM(CONVERT(bigint,CASE WHEN j._Fld1146RRef=replacement._Fld1146RRef AND j._Fld1148_RRRef=replacement._Fld1148_RRRef AND j._Fld1144=replacement._Fld1144 AND j._Fld1145=replacement._Fld1145 AND j._Fld1154=replacement._Fld1154 AND j._Fld1140=replacement._Fld1140 AND j._Fld1160=replacement._Fld1160 THEN 1 ELSE 0 END)) [same_product_contract_quantities_amounts]
        FROM [FitnessRestored_20260630_original].dbo._Document154_VT1137 j
        LEFT JOIN [FitnessRestored_20260630_macos].dbo._Document154_VT1137 oldkey
          ON j._Document154_IDRRef=oldkey._Document154_IDRRef AND j._KeyField=oldkey._KeyField AND j._Fld346=oldkey._Fld346
        JOIN [FitnessRestored_20260630_macos].dbo._Document154_VT1137 replacement ON replacement._Document154_IDRRef=j._Document154_IDRRef
        WHERE oldkey._Document154_IDRRef IS NULL FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);
