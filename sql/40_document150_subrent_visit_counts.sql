SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_date date = CONVERT(date, @cutoff_at);

IF OBJECT_ID('tempdb..#final_active_contracts') IS NOT NULL
    DROP TABLE #final_active_contracts;

CREATE TABLE #final_active_contracts (
    document_number nvarchar(20) COLLATE Cyrillic_General_CI_AS NOT NULL PRIMARY KEY
);

INSERT INTO #final_active_contracts(document_number)
VALUES
    (N'00000149952'),
    (N'00000149697'),
    (N'00000150143'),
    (N'00000149696'),
    (N'00000150128'),
    (N'00000150231'),
    (N'00000150029'),
    (N'00000149630'),
    (N'00000149628'),
    (N'00000149980'),
    (N'00000150031'),
    (N'00000149921');

IF OBJECT_ID('tempdb..#active_subrent') IS NOT NULL
    DROP TABLE #active_subrent;

SELECT
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_date,
    f.start_date,
    f.end_date,
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    CASE
        WHEN f.subscription_name LIKE N'%20 посещ%' THEN 20
        WHEN f.subscription_name LIKE N'%15 посещ%' THEN 15
        WHEN f.subscription_name LIKE N'%12 посещ%' THEN 12
        WHEN f.subscription_name LIKE N'%10 посещ%' THEN 10
        WHEN f.subscription_name LIKE N'%8 посещ%' THEN 8
        ELSE NULL
    END AS visit_limit
INTO #active_subrent
FROM fitbase_part2.membership_import_facts AS f
JOIN #final_active_contracts AS c
  ON c.document_number = f.document_number;

CREATE INDEX IX_active_subrent_subscription_ref_bin
    ON #active_subrent(subscription_ref_bin);

IF OBJECT_ID('tempdb..#doc150_subscription_events') IS NOT NULL
    DROP TABLE #doc150_subscription_events;

SELECT
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.sale_date,
    s.start_date,
    s.end_date,
    s.subscription_ref,
    s.visit_limit,
    d._Number AS doc150_number,
    CONVERT(varchar(32), d._IDRRef, 2) AS doc150_ref,
    DATEADD(year, -2000, d._Date_Time) AS visit_datetime,
    CONVERT(date, DATEADD(year, -2000, d._Date_Time)) AS visit_date,
    DATEADD(year, -2000, d._Fld993) AS visit_entry_datetime,
    DATEADD(year, -2000, d._Fld994) AS visit_exit_datetime,
    d._Fld995 AS duration_seconds,
    d._Fld999 AS fld999,
    d._Fld1000 AS fld1000,
    d._Fld1004 AS fld1004,
    d._Fld7816 AS fld7816,
    d._Fld9144 AS fld9144
INTO #doc150_subscription_events
FROM #active_subrent AS s
JOIN dbo._Document150 AS d
  ON d._Fld991_RRRef = s.subscription_ref_bin
WHERE d._Posted = 0x01
  AND d._Marked = 0x00;

CREATE INDEX IX_doc150_events_document_date
    ON #doc150_subscription_events(document_number, visit_datetime, doc150_number);

SELECT
    'active_final_scope_check' AS probe,
    COUNT(*) AS active_limited_subrent_rows,
    COUNT(DISTINCT document_number) AS distinct_contracts,
    MIN(start_date) AS min_start_date,
    MAX(end_date) AS max_end_date
FROM #active_subrent;

SELECT
    'active_direct_doc150_counts' AS probe,
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.sale_date,
    s.start_date,
    s.end_date,
    s.visit_limit,
    COUNT(e.doc150_ref) AS linked_doc150_rows_all_time,
    SUM(CASE WHEN e.visit_datetime <= @cutoff_at THEN 1 ELSE 0 END) AS linked_doc150_rows_to_cutoff_all_dates,
    SUM(CASE
            WHEN e.visit_datetime <= @cutoff_at
             AND e.visit_date BETWEEN s.start_date AND
                 CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END
            THEN 1 ELSE 0
        END) AS visits_used_inside_period_to_cutoff,
    COUNT(DISTINCT CASE
            WHEN e.visit_datetime <= @cutoff_at
             AND e.visit_date BETWEEN s.start_date AND
                 CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END
            THEN e.visit_date
        END) AS distinct_visit_dates_inside_period_to_cutoff,
    MIN(CASE
            WHEN e.visit_datetime <= @cutoff_at
             AND e.visit_date BETWEEN s.start_date AND
                 CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END
            THEN e.visit_datetime
        END) AS first_counted_visit,
    MAX(CASE
            WHEN e.visit_datetime <= @cutoff_at
             AND e.visit_date BETWEEN s.start_date AND
                 CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END
            THEN e.visit_datetime
        END) AS last_counted_visit,
    s.visit_limit - SUM(CASE
            WHEN e.visit_datetime <= @cutoff_at
             AND e.visit_date BETWEEN s.start_date AND
                 CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END
            THEN 1 ELSE 0
        END) AS visits_left_by_doc150_count,
    s.visit_limit - COUNT(DISTINCT CASE
            WHEN e.visit_datetime <= @cutoff_at
             AND e.visit_date BETWEEN s.start_date AND
                 CASE WHEN s.end_date < @cutoff_date THEN s.end_date ELSE @cutoff_date END
            THEN e.visit_date
        END) AS visits_left_by_distinct_visit_date
FROM #active_subrent AS s
LEFT JOIN #doc150_subscription_events AS e
  ON e.document_number = s.document_number
GROUP BY
    s.document_number,
    s.client_id,
    s.effective_client_fio,
    s.subscription_name,
    s.sale_date,
    s.start_date,
    s.end_date,
    s.visit_limit
ORDER BY s.document_number;

WITH active_events AS (
    SELECT
        e.*,
        ROW_NUMBER() OVER (
            PARTITION BY e.document_number
            ORDER BY e.visit_datetime, e.doc150_number, e.doc150_ref
        ) AS visit_no_inside_period_to_cutoff
    FROM #doc150_subscription_events AS e
    WHERE e.visit_datetime <= @cutoff_at
      AND e.visit_date BETWEEN e.start_date AND
          CASE WHEN e.end_date < @cutoff_date THEN e.end_date ELSE @cutoff_date END
)
SELECT
    'active_direct_doc150_event_details' AS probe,
    document_number,
    client_id,
    effective_client_fio,
    subscription_name,
    start_date,
    end_date,
    visit_limit,
    visit_no_inside_period_to_cutoff,
    visit_limit - visit_no_inside_period_to_cutoff AS visits_left_after_event,
    doc150_number,
    visit_datetime,
    visit_entry_datetime,
    visit_exit_datetime,
    duration_seconds,
    doc150_ref
FROM active_events
ORDER BY document_number, visit_datetime, doc150_number;

WITH duplicate_days AS (
    SELECT
        document_number,
        visit_date,
        COUNT(*) AS docs_on_same_day
    FROM #doc150_subscription_events
    WHERE visit_datetime <= @cutoff_at
      AND visit_date BETWEEN start_date AND
          CASE WHEN end_date < @cutoff_date THEN end_date ELSE @cutoff_date END
    GROUP BY document_number, visit_date
    HAVING COUNT(*) > 1
)
SELECT
    'active_same_day_duplicates' AS probe,
    COUNT(*) AS duplicate_contract_days,
    COALESCE(SUM(docs_on_same_day), 0) AS docs_on_duplicate_days,
    COALESCE(MAX(docs_on_same_day), 0) AS max_docs_on_one_day
FROM duplicate_days;

IF OBJECT_ID('tempdb..#all_limited_sql_facts') IS NOT NULL
    DROP TABLE #all_limited_sql_facts;

SELECT
    f.document_number,
    f.client_id,
    f.effective_client_fio,
    f.subscription_name,
    f.sale_date,
    f.start_date,
    f.end_date,
    f.subscription_ref,
    CONVERT(binary(16), f.subscription_ref, 2) AS subscription_ref_bin,
    CASE
        WHEN f.subscription_name LIKE N'%20 посещ%' THEN 20
        WHEN f.subscription_name LIKE N'%15 посещ%' THEN 15
        WHEN f.subscription_name LIKE N'%12 посещ%' THEN 12
        WHEN f.subscription_name LIKE N'%10 посещ%' THEN 10
        WHEN f.subscription_name LIKE N'%8 посещ%' THEN 8
        ELSE NULL
    END AS visit_limit
INTO #all_limited_sql_facts
FROM fitbase_part2.membership_import_facts AS f
WHERE f.is_limited_subrent = 1;

CREATE INDEX IX_all_limited_sql_subscription_ref_bin
    ON #all_limited_sql_facts(subscription_ref_bin);

WITH all_event_counts AS (
    SELECT
        s.document_number,
        s.subscription_name,
        s.visit_limit,
        COUNT(d._IDRRef) AS doc150_rows_inside_subscription_period,
        COUNT(DISTINCT CONVERT(date, DATEADD(year, -2000, d._Date_Time))) AS distinct_visit_dates_inside_subscription_period
    FROM #all_limited_sql_facts AS s
    LEFT JOIN dbo._Document150 AS d
      ON d._Fld991_RRRef = s.subscription_ref_bin
     AND d._Posted = 0x01
     AND d._Marked = 0x00
     AND CONVERT(date, DATEADD(year, -2000, d._Date_Time)) BETWEEN s.start_date AND s.end_date
    GROUP BY s.document_number, s.subscription_name, s.visit_limit
)
SELECT
    'all_sql_limited_subrent_doc150_validation_by_name' AS probe,
    subscription_name,
    COUNT(*) AS sql_fact_rows,
    SUM(CASE WHEN doc150_rows_inside_subscription_period = 0 THEN 1 ELSE 0 END) AS zero_doc150_rows,
    SUM(CASE WHEN doc150_rows_inside_subscription_period > visit_limit THEN 1 ELSE 0 END) AS over_limit_by_doc_count,
    SUM(CASE WHEN distinct_visit_dates_inside_subscription_period > visit_limit THEN 1 ELSE 0 END) AS over_limit_by_distinct_date,
    MAX(doc150_rows_inside_subscription_period) AS max_doc150_rows_inside_period,
    MAX(distinct_visit_dates_inside_subscription_period) AS max_distinct_visit_dates_inside_period,
    SUM(doc150_rows_inside_subscription_period) AS total_doc150_rows_inside_period
FROM all_event_counts
GROUP BY subscription_name
ORDER BY subscription_name;

WITH all_event_days AS (
    SELECT
        s.document_number,
        CONVERT(date, DATEADD(year, -2000, d._Date_Time)) AS visit_date,
        COUNT(*) AS docs_on_same_day
    FROM #all_limited_sql_facts AS s
    JOIN dbo._Document150 AS d
      ON d._Fld991_RRRef = s.subscription_ref_bin
     AND d._Posted = 0x01
     AND d._Marked = 0x00
     AND CONVERT(date, DATEADD(year, -2000, d._Date_Time)) BETWEEN s.start_date AND s.end_date
    GROUP BY s.document_number, CONVERT(date, DATEADD(year, -2000, d._Date_Time))
)
SELECT
    'all_sql_limited_same_day_duplicates' AS probe,
    COUNT(*) AS contract_days_with_events,
    SUM(CASE WHEN docs_on_same_day > 1 THEN 1 ELSE 0 END) AS duplicate_contract_days,
    COALESCE(SUM(CASE WHEN docs_on_same_day > 1 THEN docs_on_same_day ELSE 0 END), 0) AS docs_on_duplicate_days,
    COALESCE(MAX(docs_on_same_day), 0) AS max_docs_on_one_day
FROM all_event_days;
