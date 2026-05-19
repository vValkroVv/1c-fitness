USE [FitnessRestored];
GO

SELECT COUNT_BIG(*) AS client_rows
FROM dbo._Reference64;
GO

SELECT TOP (5)
    _Code AS client_code,
    _Description AS client_name
FROM dbo._Reference64
WHERE _Description IS NOT NULL
  AND LEN(_Description) > 0;
GO

SELECT TOP (5)
    _Date_Time AS document_datetime,
    _Number AS document_number
FROM dbo._Document150;
GO

SELECT TOP (5)
    _Period,
    _RecordKind,
    _Fld3311
FROM dbo._AccumRg3305;
GO
