USE [master];
GO

IF DB_ID(N'FitnessRestored_20260630_macos') IS NOT NULL
BEGIN
    ALTER DATABASE [FitnessRestored_20260630_macos] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [FitnessRestored_20260630_macos];
END
GO

RESTORE DATABASE [FitnessRestored_20260630_macos]
FROM DISK = N'/backup/Fitnes-30-06-26.bak'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'/restoredata/FitnessRestored_20260630_macos.mdf',
    MOVE N'Fitness_log' TO N'/restoredata/FitnessRestored_20260630_macos_log.ldf',
    RECOVERY,
    STATS = 5;
GO

ALTER DATABASE [FitnessRestored_20260630_macos] SET RECOVERY SIMPLE;
GO
