# Services import build report

- source final clients: 39550
- raw service facts: 50710
- client rows selected: 522
- active client rows selected: 352
- active rows with live InfoRg3060 end date: 19
- live rows whose client has an active membership: 19
- rows with real InfoRg3060 end date: 343
- rows with conservative sale-date fallback: 179
- historical fallback rows selected: 169
- outside import_zayavki fallback rows selected: 1
- template rows: 51
- services with selected rows: 44
- services template-only/no final-client rows: 7
- payment type counts: {'безналичные': 501, 'сбп': 7, 'default_cash_no_payment_method': 8, 'blank': 6}
- branch counts: {'Фитнес Империя (Гоголевский)': 237, 'Фитнес Империя (Ровио)': 108, 'Фитнес Империя (Промышленная)': 89, 'Фитнес Империя (Столица)': 88}

## Output

- `work/20260630_service_end_dates_fixed_20260727/imports/fitbase_import_uslugi_clientov_20260630.xlsx`
- `work/20260630_service_end_dates_fixed_20260727/imports/fitbase_import_shablony_uslug_20260630.xlsx`

## Reports

- `work/20260630_service_end_dates_fixed_20260727/imports/reports/services_coverage_report.csv`
- `work/20260630_service_end_dates_fixed_20260727/imports/reports/services_import_uncertainties.csv`
- `work/20260630_service_end_dates_fixed_20260727/imports/reports/services_end_dates_audit.csv`
- `work/20260630_service_end_dates_fixed_20260727/imports/reports/services_active_rows_audit.csv`
- `work/20260630_service_end_dates_fixed_20260727/imports/reports/services_live_active_membership_audit.csv`
- `work/20260630_service_end_dates_fixed_20260727/imports/reports/services_end_date_fallbacks.csv`
- `work/20260630_service_end_dates_fixed_20260727/imports/reports/services_branch_distribution.csv`
