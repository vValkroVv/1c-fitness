SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;
SELECT d.name,d.state_desc,d.user_access_desc,
        h.restore_date,b.backup_start_date,b.backup_finish_date,b.backup_set_uuid,
        b.family_guid,b.database_name original_database
        FROM sys.databases d
        OUTER APPLY (SELECT TOP(1) restore_date,backup_set_id FROM msdb.dbo.restorehistory
          WHERE destination_database_name=d.name AND restore_type='D' ORDER BY restore_history_id DESC) h
        LEFT JOIN msdb.dbo.backupset b ON b.backup_set_id=h.backup_set_id
        WHERE d.name IN ('FitnessRestored_20260630_original','FitnessRestored_20260630_macos') ORDER BY d.name FOR JSON PATH, INCLUDE_NULL_VALUES;
