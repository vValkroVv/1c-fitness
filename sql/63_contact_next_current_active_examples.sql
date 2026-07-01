SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @cutoff_at datetime2(0) = '2026-05-25 08:00:00';
DECLARE @cutoff_date date = CAST(@cutoff_at AS date);

WITH fulls AS (
    SELECT
        f.client_id,
        f.effective_client_fio AS client_fio,
        f.document_number,
        f.subscription_name,
        f.sale_datetime,
        CAST(f.start_date AS date) AS start_date,
        CAST(f.end_date AS date) AS end_date,
        COALESCE(NULLIF(LTRIM(RTRIM(f.status)), N''), N'<blank>') AS status_name,
        f.is_active_on_cutoff,
        f.rg_price,
        f.rg_paid_candidate,
        f.matched_payment_ref,
        f.matched_payment_amount,
        f.matched_payment_method
    FROM fitbase_part2.membership_import_facts AS f
    WHERE f.is_full_subscription = 1
      AND f.sale_datetime <= @cutoff_at
),
paired AS (
    SELECT
        next_f.document_number,
        next_f.client_id,
        next_f.client_fio,
        next_f.subscription_name,
        next_f.sale_datetime,
        next_f.start_date,
        next_f.end_date,
        next_f.status_name,
        next_f.rg_price,
        next_f.rg_paid_candidate,
        next_f.matched_payment_ref,
        next_f.matched_payment_amount,
        next_f.matched_payment_method,
        current_f.document_number AS current_document_number,
        current_f.subscription_name AS current_subscription_name,
        current_f.start_date AS current_start_date,
        current_f.end_date AS current_end_date,
        current_f.status_name AS current_status,
        current_f.matched_payment_ref AS current_matched_payment_ref,
        current_f.matched_payment_amount AS current_matched_payment_amount,
        current_f.matched_payment_method AS current_matched_payment_method,
        ROW_NUMBER() OVER (
            PARTITION BY next_f.document_number
            ORDER BY
                CASE WHEN current_f.matched_payment_ref IS NOT NULL THEN 0 ELSE 1 END,
                current_f.end_date DESC,
                current_f.document_number
        ) AS rn
    FROM fulls AS current_f
    JOIN fulls AS next_f
      ON next_f.client_id = current_f.client_id
     AND next_f.document_number <> current_f.document_number
     AND next_f.sale_datetime >= current_f.sale_datetime
     AND next_f.start_date >= current_f.start_date
     AND next_f.end_date >= @cutoff_date
    WHERE current_f.is_active_on_cutoff = 1
      AND next_f.status_name = N'Контакт с клиентом'
)
SELECT
    document_number,
    client_id,
    client_fio,
    subscription_name,
    sale_datetime,
    start_date,
    end_date,
    status_name,
    rg_price,
    rg_paid_candidate,
    matched_payment_ref,
    matched_payment_amount,
    matched_payment_method,
    current_document_number,
    current_subscription_name,
    current_start_date,
    current_end_date,
    current_status,
    current_matched_payment_ref,
    current_matched_payment_amount,
    current_matched_payment_method
FROM paired
WHERE rn = 1
ORDER BY sale_datetime DESC, document_number;
