# Part 2 CSV Reclassifier

Date: 2026-05-20

## Purpose

This adds a SQL-free way to change product classification decisions after the
initial SQL export. It is meant for validating `unknown_review_required` and
`other_sale` locally, then recalculating the three funnels without restoring the
backup again.

## Decision File

Edit:

- `config/product_reclassification_decisions.csv`

Only fill `approved_product_class` for rows you want to change. Blank means
keep the current class.

Allowed values:

- `full_subscription`
- `trial_or_guest`
- `other_sale`
- `unknown_review_required`

Important buckets in the file:

- `needs_business_decision_can_change_funnels`: usually
  `unknown_review_required`; these can move clients between `Новые заявки`,
  `Действующие клиенты`, and `Реактивация`.
- `review_other_sale_usually_no_funnel_effect`: usually service/unused
  `other_sale` rows.
- `optional_full_subscription_review`: currently full subscriptions flagged
  for review because their names include words such as freeze/gift.

## Run

Create or refresh the decision template:

```bash
scripts/16_reclassify_part2_from_csv.py \
  --write-decision-template \
  --decisions config/product_reclassification_decisions.csv
```

Do not run `--write-decision-template` after manually filling
`approved_product_class`; it rewrites the template from the current review
report.

Recompute stage CSVs without SQL:

```bash
scripts/16_reclassify_part2_from_csv.py \
  --cutoff-date 2026-04-29 \
  --source-stage-dir output/part2_20260429/staging \
  --source-reports-dir output/part2_20260429/reports \
  --decisions config/product_reclassification_decisions.csv \
  --output-stage-dir output/part2_20260429_reclassified/staging \
  --output-reports-dir output/part2_20260429_reclassified/reports
```

Build XLSX from the recalculated stage:

```bash
scripts/12_build_part2_three_funnel_xlsx.py \
  --cutoff-date 2026-04-29 \
  --stage-dir output/part2_20260429_reclassified/staging \
  --output-dir output/part2_20260429_reclassified \
  --reports-dir output/part2_20260429_reclassified/reports \
  --csv-dir output/part2_20260429_reclassified/csv \
  --doc-suffix reclassified_csv
```

Validate:

```bash
scripts/13_validate_part2_outputs.py \
  --cutoff-date 2026-04-29 \
  --stage-dir output/part2_20260429_reclassified/staging \
  --output-dir output/part2_20260429_reclassified \
  --reports-dir output/part2_20260429_reclassified/reports
```

Optional strict mode:

```bash
scripts/16_reclassify_part2_from_csv.py ... --fail-on-unresolved-review
```

## Outputs

- recalculated stage: `output/part2_20260429_reclassified/staging/`
- recalculated XLSX: `output/part2_20260429_reclassified/`
- validation report:
  `output/part2_20260429_reclassified/reports/validation_report.md`
- product decisions applied:
  `output/part2_20260429_reclassified/reports/product_reclassification_applied.csv`
- client-level impact:
  `output/part2_20260429_reclassified/reports/product_reclassification_funnel_impact.csv`
- summary:
  `output/part2_20260429_reclassified/reports/product_reclassification_impact.md`

## Verified Baseline

With the current decision file empty, local CSV reclassification applies 0
product decisions and produces the same funnel counts as the SQL-built baseline:

- `Действующие клиенты`: 10,813
- `Новые заявки`: 34,006
- `Реактивация`: 27,767

Validation result for the no-change CSV run: `PASS`.

## Limits

Product rows can be reclassified by `product_ref` or `product_code`. Payment
documents without product SKU remain `other_sale`; they can provide a
first-sale date, but cannot become a full subscription without a product link.

Do not delete `output/part2_20260429/staging/` if SQL restore should be avoided:
these staging CSVs are the local source of truth for this reclassifier.
