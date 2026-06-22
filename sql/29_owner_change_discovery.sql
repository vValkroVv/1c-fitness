USE [$(database_name)];
GO

SET NOCOUNT ON;

DECLARE @cutoff_at datetime2 = '$(cutoff_at)';
DECLARE @backup_finish_at datetime2 = '$(backup_finish_at)';
DECLARE @cutoff_sql_at datetime2 = DATEADD(year, 2000, @cutoff_at);
DECLARE @backup_finish_sql_at datetime2 = DATEADD(year, 2000, @backup_finish_at);

SELECT
    CONVERT(varchar(32), d._IDRRef, 2) AS owner_change_ref,
    d._Number AS owner_change_number,
    DATEADD(year, -2000, d._Date_Time) AS owner_change_datetime,
    CONVERT(varchar(32), d._Fld763RRef, 2) AS membership_ref,
    sale._Number AS membership_number,
    DATEADD(year, -2000, sale._Date_Time) AS membership_datetime,
    product._Description AS membership_name,
    CONVERT(varchar(32), d._Fld762RRef, 2) AS old_client_ref,
    old_client._Code AS old_client_id,
    old_client._Description AS old_client_fio,
    CONVERT(varchar(32), d._Fld767RRef, 2) AS new_client_ref,
    new_client._Code AS new_client_id,
    new_client._Description AS new_client_fio,
    CONVERT(varchar(32), d._Fld764RRef, 2) AS modifier_ref,
    modifier._Description AS modifier_name,
    CONVERT(int, d._Posted) AS is_posted,
    CASE WHEN d._Marked = 0x00 THEN 0 ELSE 1 END AS is_marked,
    ROW_NUMBER() OVER (
        PARTITION BY d._Fld763RRef
        ORDER BY d._Date_Time DESC, d._IDRRef DESC
    ) AS owner_change_rank,
    COUNT(*) OVER (PARTITION BY d._Fld763RRef) AS owner_change_count_for_membership
FROM dbo._Document138 AS d
JOIN dbo._Reference72 AS modifier
  ON modifier._IDRRef = d._Fld764RRef
LEFT JOIN dbo._Reference64 AS old_client
  ON old_client._IDRRef = d._Fld762RRef
LEFT JOIN dbo._Reference64 AS new_client
  ON new_client._IDRRef = d._Fld767RRef
LEFT JOIN dbo._Document163 AS sale
  ON sale._IDRRef = d._Fld763RRef
LEFT JOIN dbo._Reference72 AS product
  ON product._IDRRef = sale._Fld1446RRef
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
  AND d._Date_Time <= @cutoff_sql_at
  AND d._Date_Time <= @backup_finish_sql_at
  AND LTRIM(RTRIM(modifier._Description)) = N'Смена владельца'
ORDER BY d._Fld763RRef, owner_change_rank;
