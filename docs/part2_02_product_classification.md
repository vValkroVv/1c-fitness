# Part 2 Product Classification

Date: 2026-05-20

Outputs:

- `output/part2_20260429/reports/product_classification_preflight.csv`
- `output/part2_20260429/reports/product_classification_report.csv`
- `output/part2_20260429/reports/product_classification_review_report.csv`

## Result

Product classes in the baseline stage:

- `full_subscription`: 92 products
- `trial_or_guest`: 52 products
- `unknown_review_required`: 43 products
- `other_sale`: 1477 products

Rows needing business review: 70.

Unknown active-impact products include mostly `СУБАРЕНДА` and packages such as
`Пакет 12 (персональные тренировки)`. They are not counted as полноценный
абонемент by the automatic rule and are kept in review reports for business
confirmation.

## Decision

The final run treats only products matching the full-subscription rule as
полноценный абонемент. Unknown products are report-only until a manual override
is approved in `config/product_classification.yml`.
