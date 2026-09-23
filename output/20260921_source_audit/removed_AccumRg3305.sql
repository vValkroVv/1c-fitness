SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT CONVERT(varchar(8),j._RecorderTRef,2) recorder_type,
            COUNT_BIG(*) removed_rows,COUNT(DISTINCT j._RecorderRRef) removed_recorders,
            MIN(CONVERT(varchar(19),DATEADD(year,-2000,j._Period),126)) min_period,
            MAX(CONVERT(varchar(19),DATEADD(year,-2000,j._Period),126)) max_period,
            j._RecordKind record_kind,SUM(j._Fld3311) removed_amount_or_quantity,
            CONVERT(int,COALESCE(d152._Posted,d154._Posted,d138._Posted,d163._Posted)) september_recorder_posted,
            CONVERT(int,COALESCE(d152._Marked,d154._Marked,d138._Marked,d163._Marked)) september_recorder_marked
            FROM [FitnessRestored_20260630_original].dbo.[_AccumRg3305] j LEFT JOIN [FitnessRestored_20260630_macos].dbo.[_AccumRg3305] s
              ON j._RecorderRRef=s._RecorderRRef AND j._RecorderTRef=s._RecorderTRef AND j._LineNo=s._LineNo AND j._Fld346=s._Fld346
            LEFT JOIN [FitnessRestored_20260630_macos].dbo._Document152 d152 ON j._RecorderTRef=0x00000098 AND d152._IDRRef=j._RecorderRRef
            LEFT JOIN [FitnessRestored_20260630_macos].dbo._Document154 d154 ON j._RecorderTRef=0x0000009A AND d154._IDRRef=j._RecorderRRef
            LEFT JOIN [FitnessRestored_20260630_macos].dbo._Document138 d138 ON j._RecorderTRef=0x0000008A AND d138._IDRRef=j._RecorderRRef
            LEFT JOIN [FitnessRestored_20260630_macos].dbo._Document163 d163 ON j._RecorderTRef=0x000000A3 AND d163._IDRRef=j._RecorderRRef
            WHERE s._RecorderRRef IS NULL
            GROUP BY j._RecorderTRef,j._RecordKind,
              COALESCE(d152._Posted,d154._Posted,d138._Posted,d163._Posted),
              COALESCE(d152._Marked,d154._Marked,d138._Marked,d163._Marked) FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);
