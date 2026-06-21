USE [master];
GO

IF DB_ID(N'FitnessRestored_20260523_macos') IS NOT NULL
BEGIN
    ALTER DATABASE [FitnessRestored_20260523_macos] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [FitnessRestored_20260523_macos];
END
GO

RESTORE DATABASE [FitnessRestored_20260523_macos]
FROM DISK = N'/backup/Fitnes-23-05-26.bak'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'/var/opt/mssql/data/FitnessRestored_20260523_macos.mdf',
    MOVE N'Fitness_log' TO N'/var/opt/mssql/data/FitnessRestored_20260523_macos_log.ldf',
    RECOVERY,
    STATS = 5;
GO
