# Table Mapping Report

Date: 2026-05-07
Status: draft after step 11, ready for reconciliation before extraction.

## Summary

The strongest mapping is:

| Business entity | Primary source | Confidence |
|---|---|---|
| Клиент | `dbo._Reference64` | high |
| Телефон | `dbo._Reference64._Fld3832` | high |
| Карточка клиента создана | `dbo._Reference64._Fld3822` | high |
| Абонемент / членство | `dbo._InfoRg3060` joined to `dbo._Document163` | medium-high |
| Дата для этапов | candidate `dbo._InfoRg3060._Fld3064` | medium |
| Бронь | candidate `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062` | medium-high |
| Пластиковая карта | `dbo._Reference59` | high |
| Сегмент активных | `dbo._InfoRg2878 + dbo._Reference91` | medium |
| Первая продажа / платеж | candidate `dbo._Document152`, plus `dbo._Document163` | medium |

## Key Findings

### Clients

`dbo._Reference64` is the client master table:

- `_IDRRef` is the client ref.
- `_Code` is the internal client code.
- `_Description` is FIO.
- `_Fld3822` behaves as client card creation date.
- `_Fld3832` stores phone values, including multiple comma-separated phones.
- `_Fld3818` is client note/comment text.
- `_Fld3810` looks like birth date and must not be used as create date.

Evidence: `logs/step11_reference64_text_profile.txt`, `logs/step11_reference64_date_profile.txt`.

### Contacts

Primary phone source is confirmed as `dbo._Reference64._Fld3832`.

Email is not confirmed as a canonical client field:

- `dbo._Reference64` has no email-like values in profiled text columns.
- `dbo._InfoRg5255._Fld5257` has 31 email-like rows and phone values in `_Fld5261`; this is a secondary candidate only.
- `dbo._InfoRg5843` has many email-like rows, but samples look like chat/social messages and business correspondence, not a clean client email register.

Recommendation for first extraction: leave email empty unless a deterministic client join from `_InfoRg5255` is implemented and reported.

### Memberships

`dbo._InfoRg3060` is the strongest membership register candidate:

- It has `116,523` rows.
- `dbo._InfoRg3060._Fld3061RRef` joins to `dbo._Document163._IDRRef` for all `116,523` rows.
- `dbo._Document163._Fld1447_RTRef/_Fld1447_RRRef` joins the membership document to `dbo._Reference64`.
- `dbo._Document163._Fld1446RRef` joins product/service to `dbo._Reference72`.

Important date candidates:

- `dbo._Document163._Date_Time` and `dbo._InfoRg3060._Fld3062`: sale/start candidates.
- `dbo._Document163._Fld1450` and `dbo._InfoRg3060._Fld3063`: document end candidates.
- `dbo._InfoRg3060._Fld3064`: stronger valid-until candidate for active/stage calculations.
- `dbo._InfoRg3060._Fld3065`: duration days candidate.

Using `_Document163._Fld1450` alone gives only `285` active clients by full cutoff day, so it is not sufficient for final active-client logic.

### Active Segment Conflict

There are two strong but conflicting active-client sources:

| Source | Clients |
|---|---:|
| Segment `Активные членства (клиенты)` in `dbo._InfoRg2878` | 8,099 |
| Membership register filter by `_InfoRg3060._Fld3064 >= 4026-04-29`, duration >= 30 and membership-like product | 11,012 |
| Intersection | 4,986 |
| In segment but not in register filter | 3,113 |
| In register filter but not in segment | 6,026 |

This must be reconciled before the final XLSX extraction. The safest current interpretation is: `dbo._InfoRg3060` is the table for membership dates/statuses, while `dbo._InfoRg2878` may be a business-created segment that needs confirmation as authoritative or validation-only.

### Booking

The strongest structured booking candidate is:

```text
dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062._IDRRef
dbo._Reference5062._Description = "Бронь абонемента"
```

Counts from `logs/step11_membership_register_probe.txt`:

- `411` clients have status `Бронь абонемента`.
- `120` clients are active by `_InfoRg3060._Fld3064`.
- In the active-segment preview, `59` clients land in the `Бронь` stage.

Text fallback sources:

- `dbo._Reference64._Fld3818`: 12 rows with `брон`.
- `dbo._InfoRg5226._Fld5231`: 551 rows / 544 clients with `брон`.

`dbo._Document9230` is weak/rejected for booking: it is client-linked, but only 2 rows contain `брон`, and samples look more like one-off visits/services.

### Plastic Cards

`dbo._Reference59` is the plastic card table:

- `_Fld3750_RTRef = 0x00000040` and `_Fld3750_RRRef` joins to `dbo._Reference64._IDRRef`.
- `_Fld3753` and `_Fld3756` are card number candidates; samples match.
- `_Fld3751` is card date candidate.
- `_Marked = 0x00` is the active/not-deleted candidate.

Flag distribution for client-linked cards:

- `100,816` rows unmarked.
- `4,702` rows marked.
- `6` rows with `_Fld3752 = 0x01`.

Final rule candidate: choose latest unmarked card per client and write multiple-card cases to `multiple_cards_report.csv`.

### Sales

`dbo._Document152` is the payment/sale document candidate:

- `_Fld1057_RTRef/_Fld1057_RRRef` links to clients.
- `_Fld1058RRef` also matches `dbo._Reference64`.
- `_Date_Time` is payment/document date candidate.
- `_Fld1072RRef` maps to payment operation (`dbo._Reference101`).
- `_Fld1074RRef` maps to payment method (`dbo._Reference125`).

`dbo._AccumRg3305` is a money/payment movement register and should be used for validation, not as the primary active-membership source.

## Reproducibility

Step 11 scripts and logs:

- `sql/04_find_client_rtrefs.sql` -> `logs/step11_client_rtref_hits.txt`
- `sql/04_candidate_table_samples.sql` -> `logs/step11_candidate_table_samples.txt`
- `sql/04_reference_column_match_probe.sql` -> `logs/step11_reference_column_matches.txt`
- `sql/04_reference64_text_profile.sql` -> `logs/step11_reference64_text_profile.txt`
- `sql/04_client_segments_probe.sql` -> `logs/step11_client_segments_probe.txt`
- `sql/04_document163_active_probe.sql` -> `logs/step11_document163_active_probe.txt`
- `sql/04_membership_register_probe.sql` -> `logs/step11_membership_register_probe.txt`
- `sql/04_active_segment_vs_membership_probe.sql` -> `logs/step11_active_segment_vs_membership_probe.txt`
- `sql/04_booking_candidate_probe.sql` -> `logs/step11_booking_candidate_probe.txt`
- `sql/04_email_targeted_small_probe.sql` -> `logs/step11_email_targeted_small_probe.txt`

Config draft: `config/table_mapping.yml`.
Candidate CSV: `output/step11_candidate_tables.csv`.
