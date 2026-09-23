SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT * FROM (SELECT 'june' snapshot,
            CONVERT(varchar(8),_RecorderTRef,2) recorder_type,_RecordKind record_kind,
            CASE WHEN _Period<='4026-06-30T23:27:03' THEN 'at_or_before_june'
                 WHEN _Period<='4026-09-20T20:12:12' THEN 'july_to_september_backup'
                 WHEN _Period<='4026-09-21T20:12:12' THEN 'extra_effective_day' ELSE 'after_effective' END period_bucket,
            CONVERT(varchar(8),_Fld3338_RTRef,2) dimension_type,COUNT_BIG(*) rows_count,
            SUM(CAST(_Fld3339 AS decimal(38,3))) quantity
            FROM [FitnessRestored_20260630_original].dbo._AccumRg3336 WHERE _Active=0x01
            GROUP BY _RecorderTRef,_RecordKind,_Fld3338_RTRef,
              CASE WHEN _Period<='4026-06-30T23:27:03' THEN 'at_or_before_june'
                   WHEN _Period<='4026-09-20T20:12:12' THEN 'july_to_september_backup'
                   WHEN _Period<='4026-09-21T20:12:12' THEN 'extra_effective_day' ELSE 'after_effective' END UNION ALL SELECT 'september' snapshot,
            CONVERT(varchar(8),_RecorderTRef,2) recorder_type,_RecordKind record_kind,
            CASE WHEN _Period<='4026-06-30T23:27:03' THEN 'at_or_before_june'
                 WHEN _Period<='4026-09-20T20:12:12' THEN 'july_to_september_backup'
                 WHEN _Period<='4026-09-21T20:12:12' THEN 'extra_effective_day' ELSE 'after_effective' END period_bucket,
            CONVERT(varchar(8),_Fld3338_RTRef,2) dimension_type,COUNT_BIG(*) rows_count,
            SUM(CAST(_Fld3339 AS decimal(38,3))) quantity
            FROM [FitnessRestored_20260630_macos].dbo._AccumRg3336 WHERE _Active=0x01
            GROUP BY _RecorderTRef,_RecordKind,_Fld3338_RTRef,
              CASE WHEN _Period<='4026-06-30T23:27:03' THEN 'at_or_before_june'
                   WHEN _Period<='4026-09-20T20:12:12' THEN 'july_to_september_backup'
                   WHEN _Period<='4026-09-21T20:12:12' THEN 'extra_effective_day' ELSE 'after_effective' END) q ORDER BY recorder_type,period_bucket,record_kind,dimension_type,snapshot FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);
