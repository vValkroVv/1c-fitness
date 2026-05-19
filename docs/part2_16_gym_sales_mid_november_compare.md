# Part 2 Gym Sales Mid-November Comparison

Run date: `2026-05-20T02:48:32`
Cutoff date: `2025-11-15`

The Part 2 side was recalculated with the same SQL-free reclassifier that rebuilds the three funnels from exported 1C staging CSVs. The gym_sales side uses only `data/gym_sales.csv`: client identity is `phone + normalized name`, product class is derived from product name and the product-level max duration, and only counts are compared.

## Funnel Counts

| Funnel | Part 2 algorithm | gym_sales.csv | Delta Part 2 - gym_sales |
|---|---:|---:|---:|
| Новые заявки | 35891 | 1325 | 34566 |
| Реактивация | 27268 | 20612 | 6656 |
| Действующие клиенты | 9427 | 9374 | 53 |
| TOTAL | 72586 | 31311 | 41275 |

## gym_sales Coverage

- sale date range in CSV: `2018-06-08` to `2025-12-23`
- total rows in CSV: `62381`
- rows after cutoff and ignored: `1219`
- unique clients before cutoff: `31311`
- rows without sale date: `0`
- rows without client key: `0`

## Notes

- `gym_sales.csv` is a sales export, not a full client directory. Because of that, it cannot reproduce the large `Новые заявки` population that exists in 1C without a full membership sale before the cutoff.
- Active-client counts are close because both sources have explicit sale and `valid_to` dates for current memberships.
- Product classification for `gym_sales.csv` intentionally keeps `...заморозки в подарок` as `full_subscription`, matching the current SQL rule where `замороз` is review-only, not an exclude keyword.

## Written Files

- comparison counts: `output/part2_gym_sales_compare_20251115/funnel_counts_comparison.csv`
- gym product class summary: `output/part2_gym_sales_compare_20251115/gym_sales_product_class_summary.csv`
- gym product classification: `output/part2_gym_sales_compare_20251115/gym_sales_product_classification.csv`
- Part 2 recalculated final stage: `output/part2_gym_sales_compare_20251115/our_algorithm/staging/final_funnel_clients.csv`
