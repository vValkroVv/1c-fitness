# Step 11: Candidate Tables For Business Entities

Date: 2026-05-07

## Goal

Find candidate physical 1C SQL tables for:

- clients;
- contacts;
- memberships/subscriptions;
- sales/payments;
- booking;
- plastic cards.

All findings are documented with SQL scripts and logs. No final extraction logic is frozen yet where sources conflict.

## Scripts Added Or Used

| Script | Output log | Purpose |
|---|---|---|
| `sql/04_find_client_rtrefs.sql` | `logs/step11_client_rtref_hits.txt` | find composite references to client table `_Reference64` |
| `sql/04_candidate_table_samples.sql` | `logs/step11_candidate_table_samples.txt` | sample likely tables |
| `sql/04_reference_column_match_probe.sql` | `logs/step11_reference_column_matches.txt` | match direct refs to reference tables |
| `sql/04_reference64_text_profile.sql` | `logs/step11_reference64_text_profile.txt` | profile client text/contact fields |
| `sql/04_client_segments_probe.sql` | `logs/step11_client_segments_probe.txt` | inspect client segments |
| `sql/04_document163_active_probe.sql` | `logs/step11_document163_active_probe.txt` | inspect membership document candidate |
| `sql/04_membership_register_probe.sql` | `logs/step11_membership_register_probe.txt` | inspect membership register `_InfoRg3060` |
| `sql/04_active_segment_vs_membership_probe.sql` | `logs/step11_active_segment_vs_membership_probe.txt` | compare active segment vs membership register |
| `sql/04_booking_candidate_probe.sql` | `logs/step11_booking_candidate_probe.txt` | inspect booking candidates and text fallback |
| `sql/04_email_targeted_small_probe.sql` | `logs/step11_email_targeted_small_probe.txt` | targeted email search |

## Main Results

### Confirmed / Strong Candidates

| Entity | Candidate | Key fields |
|---|---|---|
| Client | `dbo._Reference64` | `_IDRRef`, `_Code`, `_Description`, `_Fld3822`, `_Fld3832` |
| Phone | `dbo._Reference64` | `_Fld3832` |
| Membership | `dbo._InfoRg3060` + `dbo._Document163` | `_Fld3061RRef -> _Document163._IDRRef`, client via `_Document163._Fld1447_*` |
| Membership product | `dbo._Reference72` | `_Document163._Fld1446RRef -> _Reference72._IDRRef` |
| Booking status | `dbo._Reference5062` via `dbo._InfoRg3060._Fld5960RRef` | status `Бронь абонемента` |
| Plastic card | `dbo._Reference59` | `_Fld3750_*`, `_Fld3753`, `_Fld3756`, `_Fld3751`, `_Marked` |
| Active segment | `dbo._InfoRg2878` + `dbo._Reference91` | segment `Активные членства (клиенты)` |
| Payment/sale | `dbo._Document152` | `_Date_Time`, `_Fld1057_*`, `_Fld1058RRef` |

### Counts To Know

| Probe | Result |
|---|---:|
| Client master rows in `_Reference64` | 72,586 |
| Client phones in `_Reference64._Fld3832` | 66,544 non-empty, 66,100 `+7`-like |
| Membership register `_InfoRg3060` rows | 116,523 |
| `_InfoRg3060._Fld3061RRef -> _Document163._IDRRef` matches | 116,523 |
| Active by `_InfoRg3060._Fld3064` | 11,217 clients before product/duration filter |
| Active by membership-like product/duration filter | 11,012 clients |
| Active segment `Активные членства (клиенты)` | 8,099 clients |
| Intersection of active segment and membership filter | 4,986 clients |
| Booking status `Бронь абонемента` total | 411 clients |
| Booking status active by `_Fld3064` | 120 clients |
| Booking status inside active-segment preview | 59 clients |
| Plastic cards in `_Reference59` linked to clients | 105,524 |
| Unmarked client-linked cards | 100,816 |

## Post-Step-12 Result

For table discovery, email was unresolved at the end of step 11, but the deep
search in `docs/step_13_email_discovery.md` found the structured low-coverage
source.

Known sources:

| Entity | Source status |
|---|---|
| Clients, IDs, FIO, phones | known: `dbo._Reference64` |
| Active memberships / active clients | known: `dbo._InfoRg3060 + dbo._Document163`; see `docs/step_12_active_segment_reconciliation.md` |
| Products / membership names | known: `dbo._Reference72` |
| Active date / stage end date candidate | known strongest table/column: `dbo._InfoRg3060._Fld3064` |
| Booking flag candidate | known structured candidate: `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062` |
| Plastic cards | known table: `dbo._Reference59` |
| First sale / create date candidates | known candidate documents: `dbo._Document152` plus membership sales in `dbo._Document163` |
| Email | known low-coverage source: `dbo._InfoRg5255._Fld5257`, joined by `_Fld5256RRef -> dbo._Reference64._IDRRef` |

Important nuance: a few items still need final business rules, but not new table
search. For example, booking semantics, Fitbase acceptance of comma-separated
card numbers, and the exact stage-date rule should be confirmed before XLSX
generation. The physical candidate tables are already identified.

## Important Decisions Still Needed

1. Confirm booking semantics for
   `dbo._Reference5062._Description = 'Бронь абонемента'`.
2. Confirm that Fitbase accepts multiple card numbers in one cell separated by commas.
3. Business-verify that `dbo._InfoRg3060._Fld3064` is the final stage end date.

## Artifacts Produced

- `config/table_mapping.yml`
- `output/table_mapping_report.md`
- `output/step11_candidate_tables.csv`
- `docs/step_11_candidate_tables.md`

## Status

Step 11 is complete as discovery work. Active-client selection was reconciled in
step 12. Email source was found in step 13, but coverage is low: only 30 clients
have structured email, including 11 current active clients.
