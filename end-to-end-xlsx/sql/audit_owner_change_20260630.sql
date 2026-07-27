USE [$(database_name)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2 = '$(cutoff_at)';
DECLARE @backup_finish_at datetime2 = '$(backup_finish_at)';
DECLARE @cutoff_sql_at datetime2 = DATEADD(year, 2000, @cutoff_at);
DECLARE @backup_finish_sql_at datetime2 = DATEADD(year, 2000, @backup_finish_at);
DECLARE @owner_change_operation_ref binary(16) = 0x9C10896C259288044EBD0A4A7A054001;

IF @cutoff_at <> CAST('2026-06-30T23:27:03' AS datetime2)
   OR @backup_finish_at <> CAST('2026-06-30T23:27:03' AS datetime2)
    THROW 51000, 'This regression audit is pinned to the 2026-06-30 backup cutoff.', 1;

IF NOT EXISTS (
    SELECT 1
    FROM dbo._Enum186
    WHERE _IDRRef = @owner_change_operation_ref
      AND _EnumOrder = 5
)
    THROW 51000, 'Owner-change operation enum reference is absent or has changed.', 1;

DROP TABLE IF EXISTS #eligible_owner_change_docs;
DROP TABLE IF EXISTS #latest_owner_change_correct;
DROP TABLE IF EXISTS #latest_owner_change_legacy;

SELECT
    d._IDRRef AS owner_change_ref_bin,
    d._Number AS owner_change_number,
    d._Date_Time AS owner_change_sql_datetime,
    d._Fld761RRef AS operation_ref_bin,
    d._Fld764RRef AS modifier_ref_bin,
    modifier._Description AS modifier_name,
    d._Fld763RRef AS membership_ref_bin,
    sale._Number AS membership_number,
    d._Fld762RRef AS old_client_ref_bin,
    d._Fld767RRef AS new_client_ref_bin
INTO #eligible_owner_change_docs
FROM dbo._Document138 AS d
LEFT JOIN dbo._Reference72 AS modifier
  ON modifier._IDRRef = d._Fld764RRef
JOIN dbo._Document163 AS sale
  ON sale._IDRRef = d._Fld763RRef
WHERE d._Posted = 0x01
  AND d._Marked = 0x00
  AND d._Date_Time <= @cutoff_sql_at
  AND d._Date_Time <= @backup_finish_sql_at
  AND d._Fld762RRef <> 0x00000000000000000000000000000000
  AND d._Fld767RRef <> 0x00000000000000000000000000000000
  AND d._Fld763RRef <> 0x00000000000000000000000000000000;

DECLARE @operation_owner_rows bigint;
DECLARE @legacy_modifier_filter_rows bigint;
DECLARE @overlap_rows bigint;
DECLARE @missed_rows bigint;

SELECT
    @operation_owner_rows = SUM(CASE
        WHEN operation_ref_bin = @owner_change_operation_ref THEN 1 ELSE 0
    END),
    @legacy_modifier_filter_rows = SUM(CASE
        WHEN LTRIM(RTRIM(modifier_name)) IN (
            N'Смена владельца',
            N'Смена владельца подарочной карты'
        ) THEN 1 ELSE 0
    END),
    @overlap_rows = SUM(CASE
        WHEN operation_ref_bin = @owner_change_operation_ref
         AND LTRIM(RTRIM(modifier_name)) IN (
            N'Смена владельца',
            N'Смена владельца подарочной карты'
         ) THEN 1 ELSE 0
    END)
FROM #eligible_owner_change_docs;

SET @missed_rows = @operation_owner_rows - @overlap_rows;

SELECT
    @operation_owner_rows AS operation_owner_rows,
    @legacy_modifier_filter_rows AS legacy_modifier_filter_rows,
    @overlap_rows AS overlap_rows,
    @missed_rows AS operation_owner_missed_by_legacy_filter;

IF @operation_owner_rows <> 5528
   OR @legacy_modifier_filter_rows <> 4595
   OR @overlap_rows <> 4595
   OR @missed_rows <> 933
    THROW 51000, 'Owner-change source mass counters differ from the verified baseline.', 1;

WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY membership_ref_bin
            ORDER BY owner_change_sql_datetime DESC, owner_change_ref_bin DESC
        ) AS owner_change_rank
    FROM #eligible_owner_change_docs
    WHERE operation_ref_bin = @owner_change_operation_ref
)
SELECT *
INTO #latest_owner_change_correct
FROM ranked
WHERE owner_change_rank = 1;

WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY membership_ref_bin
            ORDER BY owner_change_sql_datetime DESC, owner_change_ref_bin DESC
        ) AS owner_change_rank
    FROM #eligible_owner_change_docs
    WHERE LTRIM(RTRIM(modifier_name)) IN (
        N'Смена владельца',
        N'Смена владельца подарочной карты'
    )
)
SELECT *
INTO #latest_owner_change_legacy
FROM ranked
WHERE owner_change_rank = 1;

DECLARE @correct_latest_memberships bigint;
DECLARE @missing_entirely_legacy bigint;
DECLARE @wrong_older_legacy bigint;
DECLARE @different_effective_owner bigint;

SELECT
    @correct_latest_memberships = COUNT_BIG(*),
    @missing_entirely_legacy = SUM(CASE
        WHEN legacy.owner_change_ref_bin IS NULL THEN 1 ELSE 0
    END),
    @wrong_older_legacy = SUM(CASE
        WHEN legacy.owner_change_ref_bin IS NOT NULL
         AND legacy.owner_change_ref_bin <> correct.owner_change_ref_bin
            THEN 1 ELSE 0
    END),
    @different_effective_owner = SUM(CASE
        WHEN legacy.new_client_ref_bin IS NULL
          OR legacy.new_client_ref_bin <> correct.new_client_ref_bin
            THEN 1 ELSE 0
    END)
FROM #latest_owner_change_correct AS correct
LEFT JOIN #latest_owner_change_legacy AS legacy
  ON legacy.membership_ref_bin = correct.membership_ref_bin;

SELECT
    @correct_latest_memberships AS correct_latest_memberships,
    @missing_entirely_legacy AS missing_entirely_legacy,
    @wrong_older_legacy AS wrong_older_legacy,
    @different_effective_owner AS different_effective_owner;

IF @correct_latest_memberships <> 5277
   OR @missing_entirely_legacy <> 819
   OR @wrong_older_legacy <> 42
   OR @different_effective_owner <> 861
    THROW 51000, 'Effective-owner mass counters differ from the verified baseline.', 1;

DECLARE @expected_named_cases TABLE (
    membership_number nvarchar(20) NOT NULL PRIMARY KEY,
    expected_owner_change_number nvarchar(20) NOT NULL,
    expected_new_client_id nvarchar(20) NOT NULL
);

INSERT INTO @expected_named_cases (
    membership_number,
    expected_owner_change_number,
    expected_new_client_id
)
VALUES
    (N'00000133547', N'00000052842', N'000004598'),
    (N'00000144947', N'00000056656', N'000074154');

IF EXISTS (
    SELECT 1
    FROM @expected_named_cases AS expected
    LEFT JOIN #latest_owner_change_correct AS actual
      ON actual.membership_number = expected.membership_number
    LEFT JOIN dbo._Reference64 AS new_client
      ON new_client._IDRRef = actual.new_client_ref_bin
    WHERE actual.owner_change_ref_bin IS NULL
       OR actual.owner_change_number <> expected.expected_owner_change_number
       OR new_client._Code <> expected.expected_new_client_id
)
    THROW 51000, 'Named owner-change source regression failed.', 1;

SELECT
    actual.membership_number,
    actual.owner_change_number,
    DATEADD(year, -2000, actual.owner_change_sql_datetime) AS owner_change_datetime,
    old_client._Code AS old_client_id,
    old_client._Description AS old_client_fio,
    new_client._Code AS new_client_id,
    new_client._Description AS new_client_fio,
    actual.modifier_name
FROM #latest_owner_change_correct AS actual
JOIN @expected_named_cases AS expected
  ON expected.membership_number = actual.membership_number
LEFT JOIN dbo._Reference64 AS old_client
  ON old_client._IDRRef = actual.old_client_ref_bin
LEFT JOIN dbo._Reference64 AS new_client
  ON new_client._IDRRef = actual.new_client_ref_bin
ORDER BY actual.membership_number;

IF OBJECT_ID(N'fitbase_part2.stg_membership_owner_changes', N'U') IS NULL
   OR OBJECT_ID(N'fitbase_part2.stg_subscriptions_all', N'U') IS NULL
    THROW 51000, 'Run owner_sql before the post-build owner-change audit.', 1;

DECLARE @stage_owner_change_rows bigint = (
    SELECT COUNT_BIG(*)
    FROM fitbase_part2.stg_membership_owner_changes
);
DECLARE @stage_effective_owner_change_rows bigint = (
    SELECT COUNT_BIG(*)
    FROM fitbase_part2.stg_membership_owner_changes
    WHERE is_effective_owner_change_on_cutoff = 1
);

SELECT
    @stage_owner_change_rows AS stage_owner_change_rows,
    @stage_effective_owner_change_rows AS stage_effective_owner_change_rows;

IF @stage_owner_change_rows <> 5528
   OR @stage_effective_owner_change_rows <> 5277
    THROW 51000, 'Built owner-change stage counters differ from the verified baseline.', 1;

IF EXISTS (
    SELECT 1
    FROM @expected_named_cases AS expected
    LEFT JOIN fitbase_part2.stg_membership_owner_changes AS actual
      ON actual.membership_number = expected.membership_number
     AND actual.is_effective_owner_change_on_cutoff = 1
    WHERE actual.owner_change_ref IS NULL
       OR actual.owner_change_number <> expected.expected_owner_change_number
       OR actual.new_client_id <> expected.expected_new_client_id
)
    THROW 51000, 'Named owner-change stage regression failed.', 1;

IF EXISTS (
    SELECT 1
    FROM @expected_named_cases AS expected
    LEFT JOIN dbo._Document163 AS sale
      ON sale._Number = expected.membership_number
    LEFT JOIN fitbase_part2.stg_subscriptions_all AS subscription
      ON subscription.subscription_ref = CONVERT(varchar(32), sale._IDRRef, 2)
    WHERE subscription.subscription_ref IS NULL
       OR subscription.effective_client_id <> expected.expected_new_client_id
       OR subscription.owner_change_number <> expected.expected_owner_change_number
)
    THROW 51000, 'Named subscription effective-owner regression failed.', 1;

SELECT
    owner_change.membership_number,
    owner_change.owner_change_number,
    owner_change.old_client_id,
    owner_change.old_client_fio,
    owner_change.new_client_id,
    owner_change.new_client_fio,
    owner_change.modifier_name,
    subscription.effective_client_id,
    subscription.effective_client_fio
FROM fitbase_part2.stg_membership_owner_changes AS owner_change
JOIN @expected_named_cases AS expected
  ON expected.membership_number = owner_change.membership_number
 AND expected.expected_owner_change_number = owner_change.owner_change_number
JOIN dbo._Document163 AS sale
  ON sale._Number = owner_change.membership_number
JOIN fitbase_part2.stg_subscriptions_all AS subscription
  ON subscription.subscription_ref = CONVERT(varchar(32), sale._IDRRef, 2)
WHERE owner_change.is_effective_owner_change_on_cutoff = 1
ORDER BY owner_change.membership_number;

PRINT 'owner_change_20260630_audit: PASS';
GO
