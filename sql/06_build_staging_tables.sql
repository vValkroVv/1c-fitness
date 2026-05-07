USE [FitnessRestored];
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

DECLARE @cutoff_date date = '$(cutoff_date)';
DECLARE @cutoff_sql_date date = DATEADD(year, 2000, @cutoff_date);
DECLARE @backup_finish_at datetime2 = '$(backup_finish_at)';
DECLARE @cutoff_sql_end_at datetime2 = DATEADD(year, 2000, @backup_finish_at);

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'fitbase_stg')
    EXEC(N'CREATE SCHEMA fitbase_stg');

DROP TABLE IF EXISTS fitbase_stg.mart_active_clients;
DROP TABLE IF EXISTS fitbase_stg.stg_plastic_cards;
DROP TABLE IF EXISTS fitbase_stg.stg_bookings;
DROP TABLE IF EXISTS fitbase_stg.stg_sales;
DROP TABLE IF EXISTS fitbase_stg.stg_subscriptions;
DROP TABLE IF EXISTS fitbase_stg.stg_client_contacts;
DROP TABLE IF EXISTS fitbase_stg.stg_clients;
DROP TABLE IF EXISTS fitbase_stg.staging_run_metadata;
GO

DECLARE @cutoff_date date = '$(cutoff_date)';
DECLARE @cutoff_sql_date date = DATEADD(year, 2000, @cutoff_date);
DECLARE @backup_finish_at datetime2 = '$(backup_finish_at)';
DECLARE @cutoff_sql_end_at datetime2 = DATEADD(year, 2000, @backup_finish_at);

CREATE TABLE fitbase_stg.staging_run_metadata (
    cutoff_date date NOT NULL,
    cutoff_sql_date date NOT NULL,
    cutoff_sql_end_at datetime2 NOT NULL,
    backup_finish_at datetime2 NOT NULL,
    built_at datetime2 NOT NULL,
    source_database sysname NOT NULL,
    note nvarchar(400) NOT NULL
);

INSERT INTO fitbase_stg.staging_run_metadata (
    cutoff_date,
    cutoff_sql_date,
    cutoff_sql_end_at,
    backup_finish_at,
    built_at,
    source_database,
    note
)
VALUES (
    @cutoff_date,
    @cutoff_sql_date,
    @cutoff_sql_end_at,
    @backup_finish_at,
    SYSDATETIME(),
    DB_NAME(),
    N'Intermediate Fitbase staging sets before XLSX generation'
);

SELECT
    CONVERT(varchar(32), c._IDRRef, 2) AS client_ref,
    c._Code AS client_id,
    c._Description AS client_fio,
    CASE
        WHEN c._Fld3822 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, c._Fld3822))
        WHEN c._Fld3822 > '1900-01-01' THEN CONVERT(date, c._Fld3822)
        ELSE NULL
    END AS client_created_at,
    N'dbo._Reference64' AS raw_source_table
INTO fitbase_stg.stg_clients
FROM dbo._Reference64 AS c;

CREATE INDEX IX_stg_clients_client_ref ON fitbase_stg.stg_clients(client_ref);

SELECT
    CONVERT(varchar(32), c._IDRRef, 2) AS client_ref,
    c._Fld3832 AS phone_raw,
    CAST(NULL AS nvarchar(400)) AS email_raw,
    N'phone' AS contact_type,
    c._Fld3832 AS raw_value,
    N'dbo._Reference64._Fld3832' AS raw_source
INTO fitbase_stg.stg_client_contacts
FROM dbo._Reference64 AS c
WHERE NULLIF(LTRIM(RTRIM(c._Fld3832)), N'') IS NOT NULL

UNION ALL

SELECT DISTINCT
    CONVERT(varchar(32), e._Fld5256RRef, 2) AS client_ref,
    CAST(NULL AS nvarchar(190)) AS phone_raw,
    LOWER(LTRIM(RTRIM(e._Fld5257))) AS email_raw,
    N'email' AS contact_type,
    LOWER(LTRIM(RTRIM(e._Fld5257))) AS raw_value,
    N'dbo._InfoRg5255._Fld5257' AS raw_source
FROM dbo._InfoRg5255 AS e
JOIN dbo._Reference64 AS c
  ON c._IDRRef = e._Fld5256RRef
WHERE e._Fld5257 LIKE N'%[A-Za-z0-9._%+-]@[A-Za-z0-9.-]%.[A-Za-z][A-Za-z]%';

CREATE INDEX IX_stg_client_contacts_client_ref ON fitbase_stg.stg_client_contacts(client_ref);

WITH subscription_rows AS (
    SELECT
        CASE
            WHEN holder._IDRRef IS NOT NULL THEN d._Fld9152RRef
            WHEN d._Fld1447_RTRef = 0x00000040 THEN d._Fld1447_RRRef
            ELSE NULL
        END AS client_ref_bin,
        d._IDRRef AS subscription_ref_bin,
        d._Fld9152RRef AS holder_client_ref_bin,
        CASE WHEN d._Fld1447_RTRef = 0x00000040 THEN d._Fld1447_RRRef END AS payer_client_ref_bin,
        CASE
            WHEN holder._IDRRef IS NOT NULL THEN N'holder_9152'
            WHEN d._Fld1447_RTRef = 0x00000040 THEN N'payer_1447_fallback'
            ELSE N'unknown'
        END AS client_role_source,
        p._Code AS product_code,
        p._Description AS subscription_name,
        CASE
            WHEN d._Date_Time > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, d._Date_Time))
            ELSE CONVERT(date, d._Date_Time)
        END AS sale_date,
        CASE
            WHEN r._Fld3063 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3063))
            ELSE CONVERT(date, d._Date_Time)
        END AS start_date,
        CASE
            WHEN r._Fld3064 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, r._Fld3064))
            ELSE CONVERT(date, r._Fld3064)
        END AS end_date,
        st._Description AS status,
        d._Posted AS doc_posted,
        d._Marked AS doc_marked,
        r._Fld3065 AS register_duration_days,
        r._Fld5960RRef AS booking_status_ref
    FROM dbo._InfoRg3060 AS r
    JOIN dbo._Document163 AS d
      ON d._IDRRef = r._Fld3061RRef
    LEFT JOIN dbo._Reference64 AS holder
      ON holder._IDRRef = d._Fld9152RRef
    LEFT JOIN dbo._Reference72 AS p
      ON p._IDRRef = d._Fld1446RRef
    LEFT JOIN dbo._Reference5062 AS st
      ON st._IDRRef = r._Fld5960RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND p._Description IS NOT NULL
      AND (
          LOWER(p._Description) LIKE N'%абонемент%'
          OR LOWER(p._Description) LIKE N'%мульти%'
          OR LOWER(p._Description) LIKE N'%ультра%'
          OR LOWER(p._Description) LIKE N'%членств%'
      )
)
SELECT
    CONVERT(varchar(32), client_ref_bin, 2) AS client_ref,
    CONVERT(varchar(32), subscription_ref_bin, 2) AS subscription_ref,
    CONVERT(varchar(32), holder_client_ref_bin, 2) AS holder_client_ref,
    CONVERT(varchar(32), payer_client_ref_bin, 2) AS payer_client_ref,
    client_role_source,
    product_code,
    subscription_name,
    sale_date,
    start_date,
    end_date,
    status,
    CASE
        WHEN start_date <= @cutoff_date AND end_date >= @cutoff_date THEN 1
        ELSE 0
    END AS is_active_on_cutoff,
    CASE
        WHEN start_date <= @cutoff_date AND end_date >= @cutoff_date THEN 1
        ELSE 0
    END AS is_active,
    CASE
        WHEN start_date <= @cutoff_date
             AND end_date >= @cutoff_date
             AND DATEDIFF(day, start_date, end_date) + 1 < 30
            THEN 1
        ELSE 0
    END AS is_short_duration_active,
    DATEDIFF(day, start_date, end_date) + 1 AS duration_days,
    DATEDIFF(day, sale_date, end_date) + 1 AS duration_days_from_sale,
    register_duration_days,
    CONVERT(varchar(32), booking_status_ref, 2) AS booking_status_ref,
    N'dbo._InfoRg3060 + dbo._Document163' AS raw_source
INTO fitbase_stg.stg_subscriptions
FROM subscription_rows
WHERE client_ref_bin IS NOT NULL;

CREATE INDEX IX_stg_subscriptions_client_ref ON fitbase_stg.stg_subscriptions(client_ref);
CREATE INDEX IX_stg_subscriptions_active ON fitbase_stg.stg_subscriptions(is_active, client_ref);

WITH payment_sales AS (
    SELECT
        CASE
            WHEN d._Fld1057_RTRef = 0x00000040 AND c1057._IDRRef IS NOT NULL THEN d._Fld1057_RRRef
            WHEN c1058._IDRRef IS NOT NULL THEN d._Fld1058RRef
            ELSE NULL
        END AS client_ref_bin,
        d._IDRRef AS sale_ref_bin,
        CASE
            WHEN d._Date_Time > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, d._Date_Time))
            ELSE CONVERT(date, d._Date_Time)
        END AS sale_date,
        CAST(d._Fld1080 AS decimal(15, 2)) AS amount,
        op._Description AS operation_name,
        pm._Description AS payment_method,
        N'dbo._Document152' AS sale_source
    FROM dbo._Document152 AS d
    LEFT JOIN dbo._Reference64 AS c1057
      ON c1057._IDRRef = d._Fld1057_RRRef
     AND d._Fld1057_RTRef = 0x00000040
    LEFT JOIN dbo._Reference64 AS c1058
      ON c1058._IDRRef = d._Fld1058RRef
    LEFT JOIN dbo._Reference101 AS op
      ON op._IDRRef = d._Fld1072RRef
    LEFT JOIN dbo._Reference125 AS pm
      ON pm._IDRRef = d._Fld1074RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND d._Date_Time <= @cutoff_sql_end_at
),
membership_sales AS (
    SELECT
        CASE
            WHEN holder._IDRRef IS NOT NULL THEN d._Fld9152RRef
            WHEN d._Fld1447_RTRef = 0x00000040 THEN d._Fld1447_RRRef
            ELSE NULL
        END AS client_ref_bin,
        d._IDRRef AS sale_ref_bin,
        CASE
            WHEN d._Date_Time > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, d._Date_Time))
            ELSE CONVERT(date, d._Date_Time)
        END AS sale_date,
        CAST(NULL AS decimal(15, 2)) AS amount,
        CAST(NULL AS nvarchar(200)) AS operation_name,
        CAST(NULL AS nvarchar(200)) AS payment_method,
        N'dbo._Document163' AS sale_source
    FROM dbo._Document163 AS d
    LEFT JOIN dbo._Reference64 AS holder
      ON holder._IDRRef = d._Fld9152RRef
    WHERE d._Posted = 0x01
      AND d._Marked = 0x00
      AND d._Date_Time <= @cutoff_sql_end_at
)
SELECT
    CONVERT(varchar(32), client_ref_bin, 2) AS client_ref,
    CONVERT(varchar(32), sale_ref_bin, 2) AS sale_ref,
    sale_date,
    amount,
    operation_name,
    payment_method,
    sale_source
INTO fitbase_stg.stg_sales
FROM (
    SELECT * FROM payment_sales
    UNION ALL
    SELECT * FROM membership_sales
) AS sales
WHERE client_ref_bin IS NOT NULL;

CREATE INDEX IX_stg_sales_client_ref_sale_date ON fitbase_stg.stg_sales(client_ref, sale_date);

SELECT
    client_ref,
    subscription_ref AS booking_ref,
    sale_date AS booking_date,
    status AS booking_status,
    CASE WHEN is_active_on_cutoff = 1 THEN 1 ELSE 0 END AS is_active_booking,
    raw_source
INTO fitbase_stg.stg_bookings
FROM fitbase_stg.stg_subscriptions
WHERE status = N'Бронь абонемента';

CREATE INDEX IX_stg_bookings_client_ref ON fitbase_stg.stg_bookings(client_ref);

SELECT
    CONVERT(varchar(32), card._Fld3750_RRRef, 2) AS client_ref,
    CONVERT(varchar(32), card._IDRRef, 2) AS card_ref,
    NULLIF(LTRIM(RTRIM(COALESCE(NULLIF(card._Fld3753, N''), card._Fld3756))), N'') AS plastic_card_number,
    NULLIF(LTRIM(RTRIM(card._Fld3753)), N'') AS plastic_card_number_primary,
    NULLIF(LTRIM(RTRIM(card._Fld3756)), N'') AS plastic_card_number_secondary,
    CASE WHEN card._Marked = 0x00 THEN N'unmarked' ELSE N'marked' END AS card_status,
    CASE WHEN card._Marked = 0x00 THEN 1 ELSE 0 END AS is_unmarked,
    CASE
        WHEN card._Fld3751 > '3000-01-01' THEN CONVERT(date, DATEADD(year, -2000, card._Fld3751))
        WHEN card._Fld3751 > '1900-01-01' THEN CONVERT(date, card._Fld3751)
        ELSE NULL
    END AS issue_date,
    N'dbo._Reference59' AS raw_source
INTO fitbase_stg.stg_plastic_cards
FROM dbo._Reference59 AS card
JOIN dbo._Reference64 AS c
  ON c._IDRRef = card._Fld3750_RRRef
WHERE card._Fld3750_RTRef = 0x00000040;

CREATE INDEX IX_stg_plastic_cards_client_ref ON fitbase_stg.stg_plastic_cards(client_ref);

WITH active_subscriptions AS (
    SELECT
        s.*,
        COUNT(*) OVER (PARTITION BY s.client_ref) AS active_subscription_count,
        ROW_NUMBER() OVER (
            PARTITION BY s.client_ref
            ORDER BY s.end_date DESC, s.start_date DESC, s.sale_date DESC, s.subscription_ref DESC
        ) AS rn
    FROM fitbase_stg.stg_subscriptions AS s
    WHERE s.is_active = 1
),
first_sales AS (
    SELECT
        client_ref,
        MIN(sale_date) AS first_sale_date
    FROM fitbase_stg.stg_sales
    GROUP BY client_ref
),
phones AS (
    SELECT
        client_ref,
        STRING_AGG(CAST(raw_value AS nvarchar(max)), N', ') AS phones
    FROM (
        SELECT DISTINCT client_ref, raw_value
        FROM fitbase_stg.stg_client_contacts
        WHERE contact_type = N'phone'
          AND NULLIF(LTRIM(RTRIM(raw_value)), N'') IS NOT NULL
    ) AS p
    GROUP BY client_ref
),
emails AS (
    SELECT
        client_ref,
        STRING_AGG(CAST(raw_value AS nvarchar(max)), N', ') AS email
    FROM (
        SELECT DISTINCT client_ref, raw_value
        FROM fitbase_stg.stg_client_contacts
        WHERE contact_type = N'email'
          AND NULLIF(LTRIM(RTRIM(raw_value)), N'') IS NOT NULL
    ) AS e
    GROUP BY client_ref
),
active_bookings AS (
    SELECT
        client_ref,
        MAX(is_active_booking) AS has_active_booking
    FROM fitbase_stg.stg_bookings
    GROUP BY client_ref
),
best_cards AS (
    SELECT
        pc.*,
        COUNT(CASE WHEN pc.is_unmarked = 1 AND pc.plastic_card_number IS NOT NULL THEN 1 END)
            OVER (PARTITION BY pc.client_ref) AS active_card_count,
        ROW_NUMBER() OVER (
            PARTITION BY pc.client_ref
            ORDER BY
                pc.is_unmarked DESC,
                CASE WHEN pc.plastic_card_number IS NULL THEN 0 ELSE 1 END DESC,
                pc.issue_date DESC,
                pc.card_ref DESC
        ) AS rn
    FROM fitbase_stg.stg_plastic_cards AS pc
),
duplicate_keys AS (
    SELECT
        c.client_ref,
        COUNT(*) OVER (
            PARTITION BY LOWER(LTRIM(RTRIM(c.client_fio))), COALESCE(p.phones, N'')
        ) AS duplicate_key_count
    FROM fitbase_stg.stg_clients AS c
    LEFT JOIN phones AS p
      ON p.client_ref = c.client_ref
    WHERE NULLIF(LTRIM(RTRIM(c.client_fio)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(COALESCE(p.phones, N''))), N'') IS NOT NULL
)
SELECT
    c.client_ref,
    c.client_id,
    c.client_fio,
    p.phones,
    e.email,
    fs.first_sale_date,
    c.client_created_at,
    fs.first_sale_date AS create_date,
    CASE WHEN fs.first_sale_date IS NOT NULL THEN N'first_sale' ELSE N'missing_sale' END AS create_date_source,
    a.subscription_ref AS active_subscription_ref,
    a.subscription_name AS active_subscription_name,
    a.sale_date AS active_subscription_sale_date,
    a.start_date AS active_subscription_start_date,
    a.end_date AS active_subscription_end_date,
    a.duration_days AS active_subscription_duration_days,
    a.is_short_duration_active,
    DATEDIFF(day, @cutoff_date, a.end_date) AS days_to_end,
    COALESCE(ab.has_active_booking, 0) AS has_active_booking,
    bc.plastic_card_number,
    N'Действующие клиенты' AS funnel,
    CASE
        WHEN COALESCE(ab.has_active_booking, 0) = 1 THEN N'Бронь'
        WHEN DATEDIFF(day, @cutoff_date, a.end_date) BETWEEN 31 AND 60 THEN N'60-31 день до окончания'
        WHEN DATEDIFF(day, @cutoff_date, a.end_date) BETWEEN 8 AND 30 THEN N'30-8 дней до окончания'
        WHEN DATEDIFF(day, @cutoff_date, a.end_date) BETWEEN 0 AND 7 THEN N'7-0 день до окончания'
        ELSE N'Действующие клиенты'
    END AS funnel_step,
    CAST(0 AS int) AS budget,
    CASE ABS(CHECKSUM(c.client_ref)) % 3
        WHEN 0 THEN N'A1'
        WHEN 1 THEN N'A2'
        ELSE N'A3'
    END AS manager,
    CASE
        WHEN COALESCE(dk.duplicate_key_count, 1) > 1 THEN N'possible_duplicate_phone_fio'
        ELSE N'unique_by_phone_fio'
    END AS dedupe_status,
    CONCAT(
        CASE WHEN NULLIF(LTRIM(RTRIM(COALESCE(c.client_fio, N''))), N'') IS NULL THEN N'missing_fio;' ELSE N'' END,
        CASE WHEN NULLIF(LTRIM(RTRIM(COALESCE(p.phones, N''))), N'') IS NULL THEN N'missing_phone;' ELSE N'' END,
        CASE WHEN fs.first_sale_date IS NULL THEN N'missing_first_sale;' ELSE N'' END,
        CASE WHEN a.active_subscription_count > 1 THEN N'multiple_active_subscriptions;' ELSE N'' END,
        CASE WHEN COALESCE(bc.active_card_count, 0) = 0 THEN N'missing_plastic_card;' ELSE N'' END,
        CASE WHEN COALESCE(bc.active_card_count, 0) > 1 THEN N'multiple_plastic_cards;' ELSE N'' END
    ) AS validation_status,
    a.active_subscription_count,
    COALESCE(bc.active_card_count, 0) AS active_card_count,
    @cutoff_date AS cutoff_date
INTO fitbase_stg.mart_active_clients
FROM active_subscriptions AS a
JOIN fitbase_stg.stg_clients AS c
  ON c.client_ref = a.client_ref
LEFT JOIN first_sales AS fs
  ON fs.client_ref = c.client_ref
LEFT JOIN phones AS p
  ON p.client_ref = c.client_ref
LEFT JOIN emails AS e
  ON e.client_ref = c.client_ref
LEFT JOIN active_bookings AS ab
  ON ab.client_ref = c.client_ref
LEFT JOIN best_cards AS bc
  ON bc.client_ref = c.client_ref
 AND bc.rn = 1
LEFT JOIN duplicate_keys AS dk
  ON dk.client_ref = c.client_ref
WHERE a.rn = 1;

UPDATE fitbase_stg.mart_active_clients
SET validation_status = N'ok'
WHERE validation_status = N'';

CREATE INDEX IX_mart_active_clients_client_ref ON fitbase_stg.mart_active_clients(client_ref);
GO

SELECT
    'stg_clients' AS table_name,
    COUNT_BIG(*) AS rows_count
FROM fitbase_stg.stg_clients
UNION ALL
SELECT 'stg_client_contacts', COUNT_BIG(*) FROM fitbase_stg.stg_client_contacts
UNION ALL
SELECT 'stg_subscriptions', COUNT_BIG(*) FROM fitbase_stg.stg_subscriptions
UNION ALL
SELECT 'stg_sales', COUNT_BIG(*) FROM fitbase_stg.stg_sales
UNION ALL
SELECT 'stg_bookings', COUNT_BIG(*) FROM fitbase_stg.stg_bookings
UNION ALL
SELECT 'stg_plastic_cards', COUNT_BIG(*) FROM fitbase_stg.stg_plastic_cards
UNION ALL
SELECT 'mart_active_clients', COUNT_BIG(*) FROM fitbase_stg.mart_active_clients
ORDER BY table_name;
GO
