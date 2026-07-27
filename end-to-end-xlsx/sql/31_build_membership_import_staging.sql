SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- Rendered by scripts/run_pipeline.py from the single backup-finish cutoff.
DECLARE @cutoff_at datetime2(0) = '$(cutoff_at)';

IF OBJECT_ID(N'fitbase_part2.membership_import_facts', N'U') IS NOT NULL
    DROP TABLE fitbase_part2.membership_import_facts;

IF OBJECT_ID('tempdb..#direct_membership_payments') IS NOT NULL
    DROP TABLE #direct_membership_payments;
IF OBJECT_ID('tempdb..#membership_sale_docs') IS NOT NULL
    DROP TABLE #membership_sale_docs;
IF OBJECT_ID('tempdb..#membership_sale_branch_context') IS NOT NULL
    DROP TABLE #membership_sale_branch_context;
IF OBJECT_ID('tempdb..#membership_sale_line_context') IS NOT NULL
    DROP TABLE #membership_sale_line_context;
IF OBJECT_ID('tempdb..#sale_membership_counts') IS NOT NULL
    DROP TABLE #sale_membership_counts;
IF OBJECT_ID('tempdb..#sale_line_scope_context') IS NOT NULL
    DROP TABLE #sale_line_scope_context;
IF OBJECT_ID('tempdb..#membership_sale_identity_context') IS NOT NULL
    DROP TABLE #membership_sale_identity_context;
IF OBJECT_ID('tempdb..#membership_register_financial_context') IS NOT NULL
    DROP TABLE #membership_register_financial_context;
IF OBJECT_ID('tempdb..#membership_document131_context') IS NOT NULL
    DROP TABLE #membership_document131_context;

SELECT
    CONVERT(varchar(32), membership_doc._IDRRef, 2) AS subscription_ref,
    CONVERT(varchar(32), p._IDRRef, 2) AS sale_ref,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END AS sale_datetime,
    SUM(CAST(payment_line._Fld1090 AS decimal(15, 2))) AS amount,
    pm._Description AS payment_method,
    op._Description AS operation_name,
    N'direct_doc152_vt1083_doc154_vt1137_doc163' AS match_source,
    0 AS match_priority
INTO #direct_membership_payments
FROM dbo._Document163 AS membership_doc
JOIN dbo._Document154_VT1137 AS sale_line
  ON sale_line._Fld1148_RTRef = 0x000000A3
 AND sale_line._Fld1148_RRRef = membership_doc._IDRRef
JOIN dbo._Document154 AS sale_doc
  ON sale_doc._IDRRef = sale_line._Document154_IDRRef
 AND sale_doc._Posted = 0x01
 AND sale_doc._Marked = 0x00
JOIN dbo._Document152_VT1083 AS payment_line
  ON payment_line._Fld1087_RTRef = 0x0000009A
 AND payment_line._Fld1087_RRRef = sale_doc._IDRRef
JOIN dbo._Document152 AS p
  ON p._IDRRef = payment_line._Document152_IDRRef
LEFT JOIN dbo._Reference125 AS pm
  ON pm._IDRRef = p._Fld1074RRef
LEFT JOIN dbo._Reference101 AS op
  ON op._IDRRef = p._Fld1072RRef
WHERE p._Posted = 0x01
  AND p._Marked = 0x00
  AND p._Fld1080 IS NOT NULL
  AND p._Fld1080 > 0
  AND CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
      END <= @cutoff_at
GROUP BY
    membership_doc._IDRRef,
    p._IDRRef,
    CASE
        WHEN p._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, p._Date_Time)
        ELSE p._Date_Time
    END,
    pm._Description,
    op._Description;

CREATE INDEX IX_direct_membership_payments_subscription_ref
    ON #direct_membership_payments(subscription_ref);

SELECT
    s.subscription_ref,
    sale_doc._IDRRef AS sale_doc_ref,
    sale_doc._Number AS sale_doc_number,
    CASE
        WHEN sale_doc._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, sale_doc._Date_Time)
        ELSE sale_doc._Date_Time
    END AS sale_doc_datetime,
    SUM(CAST(sale_line._Fld1160 AS decimal(15, 2))) AS membership_sale_line_amount,
    COUNT_BIG(*) AS membership_sale_line_count,
    SUM(CASE WHEN sale_line._Fld1160 <> 0 THEN 1 ELSE 0 END)
        AS membership_sale_nonzero_line_count
INTO #membership_sale_docs
FROM fitbase_part2.stg_subscriptions_all AS s
JOIN dbo._Document154_VT1137 AS sale_line
  ON sale_line._Fld1148_RTRef = 0x000000A3
 AND sale_line._Fld1148_RRRef = CONVERT(binary(16), s.subscription_ref, 2)
JOIN dbo._Document154 AS sale_doc
  ON sale_doc._IDRRef = sale_line._Document154_IDRRef
 AND sale_doc._Posted = 0x01
 AND sale_doc._Marked = 0x00
WHERE s.sale_datetime <= @cutoff_at
  AND CASE
        WHEN sale_doc._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, sale_doc._Date_Time)
        ELSE sale_doc._Date_Time
      END <= @cutoff_at
  AND (
      s.product_class IN (N'full_subscription', N'trial_or_guest')
      OR LOWER(s.subscription_name) LIKE N'%субаренд%'
  )
GROUP BY
    s.subscription_ref,
    sale_doc._IDRRef,
    sale_doc._Number,
    CASE
        WHEN sale_doc._Date_Time > '3000-01-01'
        THEN DATEADD(year, -2000, sale_doc._Date_Time)
        ELSE sale_doc._Date_Time
    END;

CREATE INDEX IX_membership_sale_docs_subscription_ref
    ON #membership_sale_docs(subscription_ref);

CREATE INDEX IX_membership_sale_docs_sale_doc_ref
    ON #membership_sale_docs(sale_doc_ref);

SELECT
    sale_doc_ref,
    COUNT_BIG(*) AS sale_membership_count
INTO #sale_membership_counts
FROM #membership_sale_docs
GROUP BY sale_doc_ref;

CREATE UNIQUE INDEX IX_sale_membership_counts_sale_doc_ref
    ON #sale_membership_counts(sale_doc_ref);

SELECT
    scoped_sales.sale_doc_ref,
    COUNT_BIG(*) AS financial_sale_total_line_count,
    SUM(CASE WHEN sale_line._Fld1160 <> 0 THEN 1 ELSE 0 END)
        AS financial_sale_nonzero_line_count,
    SUM(CAST(sale_line._Fld1160 AS decimal(15, 2)))
        AS financial_sale_total_line_amount
INTO #sale_line_scope_context
FROM (
    SELECT DISTINCT sale_doc_ref
    FROM #membership_sale_docs
) AS scoped_sales
JOIN dbo._Document154_VT1137 AS sale_line
  ON sale_line._Document154_IDRRef = scoped_sales.sale_doc_ref
GROUP BY scoped_sales.sale_doc_ref;

CREATE UNIQUE INDEX IX_sale_line_scope_context_sale_doc_ref
    ON #sale_line_scope_context(sale_doc_ref);

SELECT
    msd.subscription_ref,
    COUNT_BIG(*) AS financial_sale_document_count,
    MAX(smc.sale_membership_count) AS financial_sale_membership_count,
    MAX(scope.financial_sale_total_line_count) AS financial_sale_total_line_count,
    MAX(scope.financial_sale_nonzero_line_count)
        AS financial_sale_nonzero_line_count,
    MAX(scope.financial_sale_total_line_amount)
        AS financial_sale_total_line_amount,
    MIN(msd.sale_doc_number) AS financial_sale_document_number,
    MIN(msd.sale_doc_datetime) AS financial_sale_document_datetime,
    MIN(CONVERT(varchar(32), msd.sale_doc_ref, 2)) AS financial_sale_document_ref,
    CASE
        WHEN COUNT_BIG(*) = 1
         AND MAX(smc.sale_membership_count) = 1
         AND MAX(scope.financial_sale_nonzero_line_count)
             = MAX(msd.membership_sale_nonzero_line_count)
        THEN 1
        ELSE 0
    END AS financial_register_allocation_unambiguous
INTO #membership_sale_identity_context
FROM #membership_sale_docs AS msd
JOIN #sale_membership_counts AS smc
  ON smc.sale_doc_ref = msd.sale_doc_ref
JOIN #sale_line_scope_context AS scope
  ON scope.sale_doc_ref = msd.sale_doc_ref
GROUP BY msd.subscription_ref;

CREATE UNIQUE INDEX IX_membership_sale_identity_context_subscription_ref
    ON #membership_sale_identity_context(subscription_ref);

SELECT
    msd.subscription_ref,
    COUNT_BIG(rg._Fld3311) AS financial_register_row_count,
    SUM(CASE
        WHEN rg._RecordKind = 1
        THEN CAST(rg._Fld3311 AS decimal(15, 2))
        ELSE 0
    END) AS financial_register_charge_sum,
    SUM(CASE
        WHEN rg._RecordKind = 0
        THEN CAST(rg._Fld3311 AS decimal(15, 2))
        ELSE 0
    END) AS financial_register_payment_sum,
    SUM(CASE
        WHEN rg._RecordKind = 1
        THEN CAST(rg._Fld3311 AS decimal(15, 2))
        WHEN rg._RecordKind = 0
        THEN -CAST(rg._Fld3311 AS decimal(15, 2))
        ELSE 0
    END) AS financial_register_signed_debt,
    SUM(CASE WHEN rg._RecordKind = 1 THEN 1 ELSE 0 END)
        AS financial_register_charge_row_count,
    SUM(CASE WHEN rg._RecordKind = 0 THEN 1 ELSE 0 END)
        AS financial_register_payment_row_count,
    MAX(CASE
        WHEN rg._Period > '3000-01-01' THEN DATEADD(year, -2000, rg._Period)
        ELSE rg._Period
    END) AS financial_register_last_movement_datetime
INTO #membership_register_financial_context
FROM #membership_sale_docs AS msd
LEFT JOIN dbo._AccumRg3305 AS rg
  ON rg._Active = 0x01
 AND rg._Fld3308_RTRef = 0x0000009A
 AND rg._Fld3308_RRRef = msd.sale_doc_ref
 AND CASE
        WHEN rg._Period > '3000-01-01' THEN DATEADD(year, -2000, rg._Period)
        ELSE rg._Period
     END <= @cutoff_at
GROUP BY msd.subscription_ref;

CREATE UNIQUE INDEX IX_membership_register_financial_context_subscription_ref
    ON #membership_register_financial_context(subscription_ref);

SELECT
    msd.subscription_ref,
    org._Description AS sale_branch_raw,
    CASE
        WHEN org._Description LIKE N'%Гоголев%' THEN N'Фитнес Империя (Гоголевский)'
        WHEN org._Description LIKE N'%Столиц%' THEN N'Фитнес Империя (Столица)'
        WHEN org._Description LIKE N'%Карель%' THEN N'Фитнес Империя (Ровио)'
        WHEN org._Description LIKE N'%Ровио%' THEN N'Фитнес Империя (Ровио)'
        WHEN org._Description LIKE N'%Промышлен%' THEN N'Фитнес Империя (Промышленная)'
        ELSE NULL
    END AS sale_branch,
    CASE
        WHEN org._Description IS NOT NULL THEN N'dbo._Document154._Fld1116RRef -> dbo._Reference105'
        ELSE NULL
    END AS sale_branch_source
INTO #membership_sale_branch_context
FROM #membership_sale_docs AS msd
JOIN dbo._Document154 AS sale_doc
  ON sale_doc._IDRRef = msd.sale_doc_ref
LEFT JOIN dbo._Reference105 AS org
  ON org._IDRRef = sale_doc._Fld1116RRef;

CREATE UNIQUE INDEX IX_membership_sale_branch_context_subscription_ref
    ON #membership_sale_branch_context(subscription_ref);

SELECT
    subscription_ref,
    SUM(membership_sale_line_amount) AS membership_sale_line_amount,
    SUM(membership_sale_line_count) AS membership_sale_line_count,
    SUM(membership_sale_nonzero_line_count) AS membership_sale_nonzero_line_count
INTO #membership_sale_line_context
FROM #membership_sale_docs
GROUP BY subscription_ref;

CREATE UNIQUE INDEX IX_membership_sale_line_context_subscription_ref
    ON #membership_sale_line_context(subscription_ref);

SELECT
    subscription_ref,
    COUNT(DISTINCT refund_ref) AS document131_refund_count,
    COUNT(DISTINCT CASE WHEN refund_posted = 0x01 AND refund_marked = 0x00 THEN refund_ref END)
        AS document131_posted_unmarked_refund_count
INTO #membership_document131_context
FROM (
    SELECT
        msd.subscription_ref,
        d131._IDRRef AS refund_ref,
        d131._Posted AS refund_posted,
        d131._Marked AS refund_marked
    FROM #membership_sale_docs AS msd
    JOIN dbo._Document131 AS d131
      ON d131._Fld545_RRRef = msd.sale_doc_ref
      OR d131._Fld547_RRRef = msd.sale_doc_ref
) AS refunds
GROUP BY subscription_ref;

CREATE UNIQUE INDEX IX_membership_document131_context_subscription_ref
    ON #membership_document131_context(subscription_ref);

WITH membership_source AS (
    SELECT
        s.*,
        d._Number AS document_number,
        d._Fld1481 AS doc_duration_value,
        r._Fld3065 AS rg_duration_days,
        r._Fld3068 AS rg_freeze_days,
        r._Fld3069 AS rg_guests,
        r._Fld3070 AS rg_price,
        r._Fld3072 AS rg_paid_candidate,
        r._Fld5963 AS rg_payment_count_candidate,
        r._Fld8007 AS rg_visits_candidate_8007,
        r._Fld8008 AS rg_visits_candidate_8008,
        r._Fld8009 AS rg_visits_candidate_8009,
        CASE WHEN LOWER(s.subscription_name) LIKE N'%субаренд%' THEN 1 ELSE 0 END AS is_subrent,
        CASE
            WHEN LOWER(s.subscription_name) LIKE N'%субаренд%'
             AND LOWER(s.subscription_name) NOT LIKE N'%безлимит%' THEN 1
            ELSE 0
        END AS is_limited_subrent,
        CASE
            WHEN LOWER(s.subscription_name) LIKE N'%сайкл%'
             AND LOWER(s.subscription_name) NOT LIKE N'%безлимит%'
             AND (
                 LOWER(s.subscription_name) LIKE N'%8 пос%'
                 OR LOWER(s.subscription_name) LIKE N'%12 пос%'
             )
            THEN 1
            ELSE 0
        END AS is_cycle_visit_limited,
        CASE
            WHEN (
                LOWER(s.subscription_name) LIKE N'%субаренд%'
                AND LOWER(s.subscription_name) NOT LIKE N'%безлимит%'
            )
            OR (
                LOWER(s.subscription_name) LIKE N'%сайкл%'
                AND LOWER(s.subscription_name) NOT LIKE N'%безлимит%'
                AND (
                    LOWER(s.subscription_name) LIKE N'%8 пос%'
                    OR LOWER(s.subscription_name) LIKE N'%12 пос%'
                )
            )
            THEN 1
            ELSE 0
        END AS is_visit_limited
    FROM fitbase_part2.stg_subscriptions_all AS s
    JOIN dbo._Document163 AS d
      ON CONVERT(varchar(32), d._IDRRef, 2) = s.subscription_ref
    LEFT JOIN dbo._InfoRg3060 AS r
      ON r._Fld3061RRef = d._IDRRef
    WHERE s.sale_datetime <= @cutoff_at
      AND (
          s.product_class IN (N'full_subscription', N'trial_or_guest')
          OR LOWER(s.subscription_name) LIKE N'%субаренд%'
      )
),
with_payment AS (
    SELECT
        ms.*,
        pay.sale_ref AS matched_payment_ref,
        pay.sale_datetime AS matched_payment_datetime,
        pay.amount AS matched_payment_amount,
        pay.payment_method AS matched_payment_method,
        pay.operation_name AS matched_payment_operation,
        pay.match_source AS matched_payment_match_source
    FROM membership_source AS ms
    OUTER APPLY (
        SELECT TOP (1)
            candidates.sale_ref,
            candidates.sale_datetime,
            candidates.amount,
            candidates.payment_method,
            candidates.operation_name,
            candidates.match_source
        FROM (
            SELECT
                direct.sale_ref,
                direct.sale_datetime,
                direct.amount,
                direct.payment_method,
                direct.operation_name,
                direct.match_source,
                direct.match_priority
            FROM #direct_membership_payments AS direct
            WHERE direct.subscription_ref = ms.subscription_ref

            UNION ALL

            SELECT
                p.sale_ref,
                p.sale_datetime,
                p.amount,
                p.payment_method,
                p.operation_name,
                N'client_date_14_days' AS match_source,
                1 AS match_priority
            FROM fitbase_part2.stg_sales_all AS p
            WHERE p.sale_source = N'dbo._Document152'
              AND p.amount IS NOT NULL
              AND p.amount > 0
              AND p.sale_datetime <= @cutoff_at
              AND p.client_ref IN (
                  ms.client_ref,
                  ms.original_client_ref,
                  ms.holder_client_ref,
                  ms.payer_client_ref
              )
              AND ABS(DATEDIFF(day, p.sale_datetime, ms.sale_datetime)) <= 14
        ) AS candidates
        ORDER BY
            candidates.match_priority,
            CASE
                WHEN candidates.payment_method IS NULL OR LTRIM(RTRIM(candidates.payment_method)) = N'' THEN 3
                WHEN LOWER(candidates.payment_method) LIKE N'%сбп%'
                  OR LOWER(candidates.payment_method) LIKE N'%сбпр%'
                  OR LOWER(candidates.payment_method) LIKE N'%налич%'
                  OR LOWER(candidates.payment_method) LIKE N'%эквайр%'
                  OR LOWER(candidates.payment_method) LIKE N'%банк%'
                  OR LOWER(candidates.payment_method) LIKE N'%безнал%'
                  OR LOWER(candidates.payment_method) LIKE N'%терминал%'
                  OR LOWER(candidates.payment_method) LIKE N'%карта%'
                  OR LOWER(candidates.payment_method) LIKE N'%р/с%' THEN 0
                ELSE 1
            END,
            CASE WHEN CONVERT(date, candidates.sale_datetime) = CONVERT(date, ms.sale_datetime) THEN 0 ELSE 1 END,
            ABS(DATEDIFF(second, candidates.sale_datetime, ms.sale_datetime)),
            ABS(COALESCE(candidates.amount, 0) - COALESCE(NULLIF(ms.rg_paid_candidate, 0), NULLIF(ms.rg_price, 0), 0)) ASC,
            candidates.sale_datetime DESC
    ) AS pay
),
with_sale_doc_context AS (
    SELECT
        wp.*,
        COALESCE(line_context.membership_sale_line_amount, 0) AS membership_sale_line_amount,
        COALESCE(line_context.membership_sale_line_count, 0) AS membership_sale_line_count,
        COALESCE(line_context.membership_sale_nonzero_line_count, 0)
            AS membership_sale_nonzero_line_count,
        COALESCE(identity_context.financial_sale_document_count, 0)
            AS financial_sale_document_count,
        COALESCE(identity_context.financial_sale_membership_count, 0)
            AS financial_sale_membership_count,
        COALESCE(identity_context.financial_sale_total_line_count, 0)
            AS financial_sale_total_line_count,
        COALESCE(identity_context.financial_sale_nonzero_line_count, 0)
            AS financial_sale_nonzero_line_count,
        COALESCE(identity_context.financial_sale_total_line_amount, 0)
            AS financial_sale_total_line_amount,
        identity_context.financial_sale_document_number,
        identity_context.financial_sale_document_datetime,
        identity_context.financial_sale_document_ref,
        COALESCE(identity_context.financial_register_allocation_unambiguous, 0)
            AS financial_register_allocation_unambiguous,
        COALESCE(register_context.financial_register_row_count, 0)
            AS financial_register_row_count,
        COALESCE(register_context.financial_register_charge_sum, 0)
            AS financial_register_charge_sum,
        COALESCE(register_context.financial_register_payment_sum, 0)
            AS financial_register_payment_sum,
        COALESCE(register_context.financial_register_signed_debt, 0)
            AS financial_register_signed_debt,
        COALESCE(register_context.financial_register_charge_row_count, 0)
            AS financial_register_charge_row_count,
        COALESCE(register_context.financial_register_payment_row_count, 0)
            AS financial_register_payment_row_count,
        register_context.financial_register_last_movement_datetime,
        COALESCE(branch_context.sale_branch_raw, wp.raw_club) AS sale_branch_raw,
        COALESCE(
            branch_context.sale_branch,
            CASE
                WHEN wp.normalized_club = N'Коммунальная, 20' THEN N'Фитнес Империя (Гоголевский)'
                WHEN wp.normalized_club = N'Лососинское шоссе, 26' THEN N'Фитнес Империя (Столица)'
                WHEN wp.normalized_club = N'Промышленная, 10' THEN N'Фитнес Империя (Промышленная)'
                WHEN wp.normalized_club IN (N'Ровио, 3', N'Карельский (закрыт)') THEN N'Фитнес Империя (Ровио)'
                ELSE NULL
            END
        ) AS sale_branch,
        COALESCE(
            branch_context.sale_branch_source,
            CASE
                WHEN wp.normalized_club IS NOT NULL THEN CONCAT(N'historical_membership_without_document154_fallback: ', wp.club_source)
                ELSE NULL
            END
        ) AS sale_branch_source,
        COALESCE(refund_context.document131_refund_count, 0) AS document131_refund_count,
        COALESCE(refund_context.document131_posted_unmarked_refund_count, 0) AS document131_posted_unmarked_refund_count
    FROM with_payment AS wp
    LEFT JOIN #membership_sale_line_context AS line_context
      ON line_context.subscription_ref = wp.subscription_ref
    LEFT JOIN #membership_sale_identity_context AS identity_context
      ON identity_context.subscription_ref = wp.subscription_ref
    LEFT JOIN #membership_register_financial_context AS register_context
      ON register_context.subscription_ref = wp.subscription_ref
    LEFT JOIN #membership_sale_branch_context AS branch_context
      ON branch_context.subscription_ref = wp.subscription_ref
    LEFT JOIN #membership_document131_context AS refund_context
      ON refund_context.subscription_ref = wp.subscription_ref
),
-- Legacy output column names below retain the `subrent_` prefix to keep the
-- 81-column TSV ABI stable. They now carry the selected RG3336 balance for
-- every visit-limited membership: limited subrent or Cycle.
with_subrent_visits AS (
    SELECT
        wp.*,
        limit_calc.visit_limit AS subrent_visit_limit,
        CASE
            WHEN wp.is_visit_limited = 1
             AND wp.start_date <= CAST(@cutoff_at AS date)
             AND wp.end_date >= CAST(@cutoff_at AS date)
            THEN 1
            ELSE 0
        END AS subrent_active_by_dates_on_cutoff,
        CASE
            WHEN wp.is_visit_limited = 1
             AND wp.end_date < CAST(@cutoff_at AS date)
            THEN 1
            ELSE 0
        END AS subrent_finished_by_dates_before_cutoff,
        COALESCE(balance.receipt_qty, 0) AS subrent_rg3336_receipt_qty,
        COALESCE(balance.expense_qty, 0) AS subrent_rg3336_expense_qty,
        COALESCE(balance.signed_balance, 0) AS subrent_rg3336_signed_balance,
        COALESCE(balance.visit_doc_expense_qty, 0) AS subrent_rg3336_visit_doc_expense_qty,
        COALESCE(balance.receipt_rows, 0) AS subrent_rg3336_receipt_rows,
        COALESCE(balance.expense_rows, 0) AS subrent_rg3336_expense_rows,
        CASE
            WHEN wp.is_visit_limited = 0 THEN N''
            WHEN COALESCE(balance.receipt_qty, 0) = limit_calc.visit_limit
             AND COALESCE(balance.signed_balance, 0) BETWEEN 0 AND limit_calc.visit_limit
            THEN N'clean_register_balance'
            WHEN COALESCE(balance.receipt_qty, 0) = 0
             AND COALESCE(balance.expense_qty, 0) = 0
            THEN N'no_register_movements'
            WHEN COALESCE(balance.receipt_qty, 0) = 0
             AND COALESCE(balance.expense_qty, 0) > 0
            THEN N'expense_without_receipt'
            WHEN COALESCE(balance.receipt_qty, 0) <> limit_calc.visit_limit
            THEN N'receipt_not_equal_name_limit'
            WHEN COALESCE(balance.signed_balance, 0) < 0
            THEN N'negative_balance'
            WHEN COALESCE(balance.signed_balance, 0) > limit_calc.visit_limit
            THEN N'balance_above_name_limit'
            ELSE N'other'
        END AS subrent_rg3336_case_group
    FROM with_sale_doc_context AS wp
    CROSS APPLY (
        SELECT CASE
            WHEN wp.is_visit_limited = 1 AND LOWER(wp.subscription_name) LIKE N'%20 пос%' THEN 20
            WHEN wp.is_visit_limited = 1 AND LOWER(wp.subscription_name) LIKE N'%15 пос%' THEN 15
            WHEN wp.is_visit_limited = 1 AND LOWER(wp.subscription_name) LIKE N'%12 пос%' THEN 12
            WHEN wp.is_visit_limited = 1 AND LOWER(wp.subscription_name) LIKE N'%10 пос%' THEN 10
            WHEN wp.is_visit_limited = 1 AND LOWER(wp.subscription_name) LIKE N'%8 пос%' THEN 8
            ELSE 0
        END AS visit_limit
    ) AS limit_calc
    OUTER APPLY (
        SELECT
            SUM(CASE WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS receipt_qty,
            SUM(CASE WHEN r._RecordKind = 1 THEN CAST(r._Fld3339 AS decimal(15, 3)) ELSE 0 END) AS expense_qty,
            SUM(CASE
                WHEN r._RecordKind = 0 THEN CAST(r._Fld3339 AS decimal(15, 3))
                WHEN r._RecordKind = 1 THEN -CAST(r._Fld3339 AS decimal(15, 3))
                ELSE 0
            END) AS signed_balance,
            SUM(CASE
                WHEN r._RecorderTRef = 0x00000096 AND r._RecordKind = 1
                THEN CAST(r._Fld3339 AS decimal(15, 3))
                ELSE 0
            END) AS visit_doc_expense_qty,
            SUM(CASE WHEN r._RecordKind = 0 THEN 1 ELSE 0 END) AS receipt_rows,
            SUM(CASE WHEN r._RecordKind = 1 THEN 1 ELSE 0 END) AS expense_rows
        FROM dbo._AccumRg3336 AS r
        WHERE wp.is_visit_limited = 1
          AND r._Active = 0x01
          AND r._Fld3337_RRRef = CONVERT(binary(16), wp.subscription_ref, 2)
          AND (
              (
                  wp.is_limited_subrent = 1
                  AND r._Fld3338_TYPE = 0x01
                  AND r._Fld3338_RTRef = 0x00000000
                  AND r._Fld3338_RRRef = 0x00000000000000000000000000000000
              )
              OR (
                  wp.is_cycle_visit_limited = 1
                  AND wp.is_limited_subrent = 0
                  AND r._Fld3338_TYPE = 0x08
                  AND r._Fld3338_RTRef = 0x00000048
                  AND r._Fld3338_RRRef = 0xAA9EA4BF01266AD311E8C6D3BB763918
              )
          )
          AND r._Fld3339 <> 0
          AND DATEADD(year, -2000, r._Period) <= @cutoff_at
    ) AS balance
)
SELECT
    client_ref,
    client_id,
    original_client_ref,
    original_client_id,
    original_client_fio,
    effective_client_ref,
    effective_client_id,
    effective_client_fio,
    owner_change_ref,
    owner_change_number,
    owner_change_datetime,
    owner_change_old_client_ref,
    owner_change_new_client_ref,
    owner_change_modifier_name,
    owner_change_count_for_membership,
    subscription_ref,
    document_number,
    holder_client_ref,
    payer_client_ref,
    client_role_source,
    product_ref,
    product_code,
    subscription_name,
    product_class,
    is_full_subscription,
    is_trial_or_guest,
    is_subrent,
    is_limited_subrent,
    sale_date,
    sale_datetime,
    start_date,
    end_date,
    duration_days,
    status,
    booking_status_ref,
    booking_status_name,
    doc_posted,
    doc_marked,
    register_duration_days,
    is_active_on_cutoff,
    is_finished_before_cutoff,
    days_to_end,
    days_since_end,
    raw_club,
    normalized_club,
    club_source,
    sale_branch_raw,
    sale_branch,
    sale_branch_source,
    raw_source,
    CAST(COALESCE(doc_duration_value, 0) AS decimal(15, 2)) AS doc_duration_value,
    CAST(COALESCE(rg_duration_days, 0) AS decimal(15, 2)) AS rg_duration_days,
    CAST(COALESCE(rg_freeze_days, 0) AS decimal(15, 2)) AS rg_freeze_days,
    CAST(COALESCE(rg_guests, 0) AS decimal(15, 2)) AS rg_guests,
    CAST(COALESCE(rg_price, 0) AS decimal(15, 2)) AS rg_price,
    CAST(COALESCE(rg_paid_candidate, 0) AS decimal(15, 2)) AS rg_paid_candidate,
    CAST(COALESCE(rg_payment_count_candidate, 0) AS decimal(15, 2)) AS rg_payment_count_candidate,
    CAST(COALESCE(rg_visits_candidate_8007, 0) AS decimal(15, 2)) AS rg_visits_candidate_8007,
    CAST(COALESCE(rg_visits_candidate_8008, 0) AS decimal(15, 2)) AS rg_visits_candidate_8008,
    CAST(COALESCE(rg_visits_candidate_8009, 0) AS decimal(15, 2)) AS rg_visits_candidate_8009,
    CAST(COALESCE(subrent_visit_limit, 0) AS decimal(15, 2)) AS subrent_visit_limit,
    subrent_active_by_dates_on_cutoff,
    subrent_finished_by_dates_before_cutoff,
    CAST(COALESCE(subrent_rg3336_receipt_qty, 0) AS decimal(15, 3)) AS subrent_rg3336_receipt_qty,
    CAST(COALESCE(subrent_rg3336_expense_qty, 0) AS decimal(15, 3)) AS subrent_rg3336_expense_qty,
    CAST(COALESCE(subrent_rg3336_signed_balance, 0) AS decimal(15, 3)) AS subrent_rg3336_signed_balance,
    CAST(COALESCE(subrent_rg3336_visit_doc_expense_qty, 0) AS decimal(15, 3)) AS subrent_rg3336_visit_doc_expense_qty,
    subrent_rg3336_receipt_rows,
    subrent_rg3336_expense_rows,
    subrent_rg3336_case_group,
    matched_payment_ref,
    matched_payment_datetime,
    CAST(COALESCE(matched_payment_amount, 0) AS decimal(15, 2)) AS matched_payment_amount,
    matched_payment_method,
    matched_payment_operation,
    matched_payment_match_source,
    CAST(COALESCE(membership_sale_line_amount, 0) AS decimal(15, 2)) AS membership_sale_line_amount,
    membership_sale_line_count,
    membership_sale_nonzero_line_count,
    financial_sale_document_count,
    financial_sale_membership_count,
    financial_sale_total_line_count,
    financial_sale_nonzero_line_count,
    CAST(COALESCE(financial_sale_total_line_amount, 0) AS decimal(15, 2))
        AS financial_sale_total_line_amount,
    financial_sale_document_number,
    financial_sale_document_datetime,
    financial_sale_document_ref,
    financial_register_allocation_unambiguous,
    financial_register_row_count,
    CAST(COALESCE(financial_register_charge_sum, 0) AS decimal(15, 2))
        AS financial_register_charge_sum,
    CAST(COALESCE(financial_register_payment_sum, 0) AS decimal(15, 2))
        AS financial_register_payment_sum,
    CAST(COALESCE(financial_register_signed_debt, 0) AS decimal(15, 2))
        AS financial_register_signed_debt,
    financial_register_charge_row_count,
    financial_register_payment_row_count,
    financial_register_last_movement_datetime,
    document131_refund_count,
    document131_posted_unmarked_refund_count,
    @cutoff_at AS cutoff_at
INTO fitbase_part2.membership_import_facts
FROM with_subrent_visits;

CREATE INDEX IX_membership_import_facts_client_id
    ON fitbase_part2.membership_import_facts(client_id);

CREATE INDEX IX_membership_import_facts_subscription_ref
    ON fitbase_part2.membership_import_facts(subscription_ref);

SELECT
    'membership_import_facts' AS table_name,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS distinct_clients,
    COUNT(DISTINCT subscription_ref) AS distinct_subscriptions,
    SUM(CASE WHEN is_subrent = 1 THEN 1 ELSE 0 END) AS subrent_rows,
    SUM(CASE WHEN is_limited_subrent = 1 THEN 1 ELSE 0 END) AS limited_subrent_rows,
    SUM(CASE WHEN owner_change_ref IS NOT NULL AND owner_change_ref <> '' THEN 1 ELSE 0 END) AS owner_change_rows
FROM fitbase_part2.membership_import_facts;

SELECT
    product_class,
    is_subrent,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT client_id) AS distinct_clients
FROM fitbase_part2.membership_import_facts
GROUP BY product_class, is_subrent
ORDER BY rows_count DESC;
