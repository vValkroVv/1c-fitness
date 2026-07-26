# Targeted service end-date delivery

- source delivery: `/Users/valerii.kropotin/Папа-работа/1c-preprocess/output/20260630_delivery_register_debts`
- corrected delivery: `/Users/valerii.kropotin/Папа-работа/1c-preprocess/output/20260630_delivery_service_end_dates_fixed_20260727`
- root delivery XLSX files: 7
- XLSX files compared recursively: 8
- service data rows: 522
- rows with changed end_date: 360
- changed cells (end_date only): 360
- blank end_date cells after correction: 0
- end_date number-format changes: 353
- unchanged XLSX verified byte-identical: 7
- preserved non-XLSX baseline reports: 3
- status: PASS

Only `end_date` is authorized to differ inside the service-client workbook.
Every other cell and every other XLSX is checked before the delivery is accepted.
