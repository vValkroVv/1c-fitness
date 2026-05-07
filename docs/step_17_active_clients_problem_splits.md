# Step 17: Active Clients Split By Validation Group

Date: 2026-05-07

Goal: split the final active-client import files into mutually exclusive XLSX
packages by data-quality group.

Source file:

```text
output/fitbase_active_clients_import_zayavki_20260429.xlsx
output/fitbase_active_clients_plastic_cards_20260429.xlsx
```

Generation command:

```bash
scripts/09_build_validation_split_xlsx.py
```

Output directory:

```text
output/splits/
```

## Groups

| # | Group | Rows | Directory |
|---:|---|---:|---|
| 1 | ok | 2,885 | `output/splits/01_ok/` |
| 2 | только несколько карт | 7,201 | `output/splits/02_tolko_neskolko_kart/` |
| 3 | несколько абонементов + несколько карт | 366 | `output/splits/03_neskolko_abonementov_i_neskolko_kart/` |
| 4 | только нет карты | 228 | `output/splits/04_tolko_net_karty/` |
| 5 | только несколько абонементов | 92 | `output/splits/05_tolko_neskolko_abonementov/` |
| 6 | несколько абонементов + нет карты | 13 | `output/splits/06_neskolko_abonementov_i_net_karty/` |
| 7 | только нет телефона | 6 | `output/splits/07_tolko_net_telefona/` |
| 8 | нет телефона + несколько карт | 3 | `output/splits/08_net_telefona_i_neskolko_kart/` |
| 9 | нет телефона + нет карты | 2 | `output/splits/09_net_telefona_i_net_karty/` |

Total:

```text
10,796 rows
```

This equals the row count of the full active-client import XLSX.

## Artifacts

| Artifact | Purpose |
|---|---|
| `output/splits/split_summary.csv` | machine-readable split summary |
| `output/splits/README.md` | human-readable split package index |
| `output/splits/*/*import_zayavki*.xlsx` | one main Fitbase import XLSX per group |
| `output/splits/*/*plastic_cards*.xlsx` | one plastic-card XLSX per group |

Every main split XLSX keeps the same 9-column structure as the main import file:

```text
client_id, phone, client_fio, email, funnel, funnel_step, budget, create_date, manager
```

Every plastic-card split XLSX keeps the same 3-column structure as the plastic-card file:

```text
телефон, фио, номер пластиковой карты
```

## Verification

All main split XLSX files were opened with `openpyxl` and counted from row 3.
All plastic-card split XLSX files were opened with `openpyxl` and counted from
row 2. Observed counts matched `output/splits/split_summary.csv`; total rows
across the split packages: `10,796`.
