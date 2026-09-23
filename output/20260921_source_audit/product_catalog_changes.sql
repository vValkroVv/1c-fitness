SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT s._Code product_code,
        j._Description june_name,s._Description september_name,
        CASE WHEN j._IDRRef IS NULL THEN 'added' ELSE 'renamed' END change_kind,
        (SELECT COUNT_BIG(*) FROM [FitnessRestored_20260630_macos].dbo._Document163 d WHERE d._Fld1446RRef=s._IDRRef) september_contract_count
        FROM [FitnessRestored_20260630_macos].dbo._Reference72 s LEFT JOIN [FitnessRestored_20260630_original].dbo._Reference72 j ON j._IDRRef=s._IDRRef
        WHERE j._IDRRef IS NULL OR CONVERT(varbinary(max),j._Description)<>CONVERT(varbinary(max),s._Description)
        ORDER BY change_kind,s._Code FOR JSON PATH, INCLUDE_NULL_VALUES;
