USE [master];
GO

IF DB_ID(N'FitnessRestored_20260523') IS NOT NULL
BEGIN
    ALTER DATABASE [FitnessRestored_20260523] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [FitnessRestored_20260523];
END
GO

RESTORE DATABASE [FitnessRestored_20260523]
FROM DISK = N'/backup/Fitnes-23-05-26.bak'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'/var/opt/mssql/data/FitnessRestored_20260523.mdf',
    MOVE N'Fitness_log' TO N'/var/opt/mssql/data/FitnessRestored_20260523_log.ldf',
    RECOVERY,
    STATS = 5;
GO
