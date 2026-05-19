# Part 2 Trial Purchase Classification

Date: 2026-05-20
Cutoff: `2026-04-29`

## Files

- full approval table:
  `output/part2_20260429/reports/trial_purchase_classification_for_approval.csv`
- source classification report:
  `output/part2_20260429/reports/product_classification_report.csv`
- business review report:
  `output/part2_20260429/reports/product_classification_review_report.csv`

## Current Logic

`Новые заявки` are clients without any product classified as
`full_subscription`. Trial/test purchases do not by themselves create the
funnel; they are used as the preferred `create_date` source for new
applications.

Current baseline:

- `Новые заявки`: 34,006 clients
- new applications with `create_date_source = first_trial_or_guest_product`:
  4,821 clients
- new applications with `create_date_source = first_non_full_sale_requires_review`:
  6,231 clients
- new applications with `create_date_source = client_created_at_no_sales`:
  22,954 clients

## Used As Trial/Test

Rule: product class `trial_or_guest`.

Products that actually affected current `Новые заявки`:

- `Абонемент НЕДЕЛЯ САЙТ`: 2,202 current-new clients with this subscription;
  2,158 clients used it as the trial create-date source.
- `Абонемент НЕДЕЛЯ ДРУГ`: 1,907 / 1,870.
- `Абонемент Неделя Фитнес`: 203 / 192.
- `Абонемент НЕДЕЛЯ ФИТНЕСА БЕСПЛАТНО`: 201 / 185.
- `Абонемент Неделя сайт 2023`: 183 / 171.
- `Абонемент Неделя Фитнес 1 рубль`: 41 / 36.
- `Абонемент 10 ДНЕЙ`: 41 / 36.
- `Абонемент НЕДЕЛЯ КАРЕЛЬСКИЙ`: 40 / 34.
- `Абонемент НЕДЕЛЯ ХОЛОДНЫЕ`: 38 / 28.
- `Абонемент 2 недели Фитнес`: 35 / 22.
- `Пробное посещение АКВА`: 33 / 32.
- `Абонемент Неделя марафон`: 28 / 26.
- `Разовое посещение АКВА`: 25 / 17.
- `Абонемент Неделя Фитнес (НОВЫЕ КЛИЕНТЫ)`: 10 / 10.
- `Абонемент Неделя Фитнес 190 рублей`: 2 / 2.
- `СУБАРЕНДА безлимит неделя Савостьянова Ксения`: 1 / 1.
- `144 полотенца для ПитерСтрой`: 1 / 1.

Total classified as `trial_or_guest` in the product report: 52 products.
The full list is in
`trial_purchase_classification_for_approval.csv`.

## Not Used As Trial/Test

- `full_subscription`: 92 products. These define active/reactivation status.
- `unknown_review_required`: 43 products. These are currently not trial and not
  full; they keep affected clients in `Новые заявки` unless another full
  subscription exists.
- `other_sale`: 14 report rows with 0 observed clients/sales in the selected
  product report. These are not trial.

There are also 6,084 current-new clients whose first non-full date came from a
payment document without product SKU (`dbo._Document152`). These are not
trial/test purchases; they only supply a first-sale date.

## Questions For Approval

High-impact `unknown_review_required` products among current `Новые заявки`:

- `АКВА 40 посещений`: 365 current-new clients.
- `АКВА 24 посещения`: 159.
- `АКВА 46 посещений`: 147.
- `АКВА 30 посещений`: 146.
- `АКВА 36 посещений`: 145.
- `АКВА 8 посещений`: 118.
- `АКВА 18 посещений`: 100 and 93 across two product codes.
- `Подарочный сертификат 1 месяц безлимитного фитнеса`: 88.
- `АКВА 4 посещения`: 69.
- `АКВА 32 посещения`: 66.
- `СУБАРЕНДА безлимит`: 24 clients, 446 subscription rows.
- `Пакет 12 (персональные тренировки)`: 13 current-new clients.
- `Пакет 8`: 8 current-new clients.

Questions to close:

- Should `АКВА ... посещений` be full subscriptions, trial/test products, or
  service packages outside these funnels?
- Should `Пакет 8/10/12` and VIP personal-training packages count as
  full subscriptions or remain outside active/reactivation?
- Should `СУБАРЕНДА ...` remain outside client funnels?
- Should `Подарочный сертификат 1 месяц безлимитного фитнеса` be a full
  subscription when activated/sold?
- Should obvious test/internal names such as `Наталья триггер`,
  `Катя проверка триггер`, and `Танцевальная тренировка (не использовать!!!)`
  be excluded as `other_sale`?

## Rebuild Without Restoring SQL

If `FitnessRestored` is still present in the SQL container, no backup restore is
needed: update the product classification rules and rerun the stage/build.

If SQL is gone, the saved staging CSVs are enough in principle to recompute the
funnels locally because they contain product refs, sale dates, subscription
dates, client refs, and current product classes:

- `output/part2_20260429/staging/stg_products.csv`
- `output/part2_20260429/staging/stg_sales_all.csv`
- `output/part2_20260429/staging/stg_subscriptions_all.csv`
- `output/part2_20260429/staging/stg_clients.csv`
- `output/part2_20260429/staging/stg_client_contacts.csv`
- `output/part2_20260429/staging/stg_plastic_cards.csv`

Current build scripts do not yet have a pure-CSV reclassifier wired in. Without
SQL, changing funnels from only the final XLSX is not reliable; keep the staging
CSV folder if later classification changes must be possible without restoring
the backup.
