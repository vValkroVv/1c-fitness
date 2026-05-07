RESTORE DATABASE [FitnessRestored]
FROM DISK = N'/backup/Fitnes.bak'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'/var/opt/mssql/data/FitnessRestored.mdf',
    MOVE N'Fitness_log' TO N'/var/opt/mssql/data/FitnessRestored_log.ldf',
    RECOVERY,
    STATS = 5;
GO
