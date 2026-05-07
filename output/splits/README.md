# Fitbase Active Clients Splits

Source:

```text
output/fitbase_active_clients_import_zayavki_20260429.xlsx
output/final_active_clients_20260429.csv
```

Each group directory contains two XLSX files:

- main Fitbase import file with the same 9-column structure as `fitbase_active_clients_import_zayavki_20260429.xlsx`;
- plastic-card file with the same 3-column structure as `fitbase_active_clients_plastic_cards_20260429.xlsx`.

| # | Group | Rows | Main XLSX | Cards XLSX |
|---:|---|---:|---|---|
| 1 | ok | 2885 | `output/splits/01_ok/fitbase_active_clients_import_zayavki_20260429__01_ok.xlsx` | `output/splits/01_ok/fitbase_active_clients_plastic_cards_20260429__01_ok.xlsx` |
| 2 | только несколько карт | 7201 | `output/splits/02_tolko_neskolko_kart/fitbase_active_clients_import_zayavki_20260429__02_tolko_neskolko_kart.xlsx` | `output/splits/02_tolko_neskolko_kart/fitbase_active_clients_plastic_cards_20260429__02_tolko_neskolko_kart.xlsx` |
| 3 | несколько абонементов + несколько карт | 366 | `output/splits/03_neskolko_abonementov_i_neskolko_kart/fitbase_active_clients_import_zayavki_20260429__03_neskolko_abonementov_i_neskolko_kart.xlsx` | `output/splits/03_neskolko_abonementov_i_neskolko_kart/fitbase_active_clients_plastic_cards_20260429__03_neskolko_abonementov_i_neskolko_kart.xlsx` |
| 4 | только нет карты | 228 | `output/splits/04_tolko_net_karty/fitbase_active_clients_import_zayavki_20260429__04_tolko_net_karty.xlsx` | `output/splits/04_tolko_net_karty/fitbase_active_clients_plastic_cards_20260429__04_tolko_net_karty.xlsx` |
| 5 | только несколько абонементов | 92 | `output/splits/05_tolko_neskolko_abonementov/fitbase_active_clients_import_zayavki_20260429__05_tolko_neskolko_abonementov.xlsx` | `output/splits/05_tolko_neskolko_abonementov/fitbase_active_clients_plastic_cards_20260429__05_tolko_neskolko_abonementov.xlsx` |
| 6 | несколько абонементов + нет карты | 13 | `output/splits/06_neskolko_abonementov_i_net_karty/fitbase_active_clients_import_zayavki_20260429__06_neskolko_abonementov_i_net_karty.xlsx` | `output/splits/06_neskolko_abonementov_i_net_karty/fitbase_active_clients_plastic_cards_20260429__06_neskolko_abonementov_i_net_karty.xlsx` |
| 7 | только нет телефона | 6 | `output/splits/07_tolko_net_telefona/fitbase_active_clients_import_zayavki_20260429__07_tolko_net_telefona.xlsx` | `output/splits/07_tolko_net_telefona/fitbase_active_clients_plastic_cards_20260429__07_tolko_net_telefona.xlsx` |
| 8 | нет телефона + несколько карт | 3 | `output/splits/08_net_telefona_i_neskolko_kart/fitbase_active_clients_import_zayavki_20260429__08_net_telefona_i_neskolko_kart.xlsx` | `output/splits/08_net_telefona_i_neskolko_kart/fitbase_active_clients_plastic_cards_20260429__08_net_telefona_i_neskolko_kart.xlsx` |
| 9 | нет телефона + нет карты | 2 | `output/splits/09_net_telefona_i_net_karty/fitbase_active_clients_import_zayavki_20260429__09_net_telefona_i_net_karty.xlsx` | `output/splits/09_net_telefona_i_net_karty/fitbase_active_clients_plastic_cards_20260429__09_net_telefona_i_net_karty.xlsx` |

Total rows across split files: `10796`.
