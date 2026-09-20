# Targeted funnel-label delivery

- source delivery: `/Users/valerii.kropotin/Папа-работа/1c-preprocess/output/20260630_delivery_service_end_dates_fixed_20260727`
- corrected delivery: `/Users/valerii.kropotin/Папа-работа/1c-preprocess/output/20260630_delivery_funnel_labels_20260820`
- total owner rows: 39550
- reactivation rows: 28526
- rows with changed labels: 28526
- changed cells (funnel and funnel_step only): 57052
- unchanged root XLSX verified byte-identical: 6
- unchanged recursive XLSX verified byte-identical: 7
- old funnel: `Реактивация(годовые абонементы)`
- new funnel: `Реактивация`
- old funnel_step: `Все закрытые абонементы`
- new funnel_step: `Закрытые годовые абонементы`
- worksheet layout, cell attributes and every style ID: identical
- protected OOXML members: byte-identical
- core metadata difference: modified timestamp only
- status: PASS

Only the two requested labels are authorized to differ inside the owner workbook.
Every other cell and every other XLSX is checked before the delivery is accepted.
