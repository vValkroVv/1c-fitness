# Membership import validation

- source final clients: 66348
- clients with at least one membership row: 65582
- source clients without membership rows: 766
- client membership rows: 124989
- membership template rows: 122
- duplicate contract_id count: 0
- contract names missing in template file: 0
- uncertainty rows: 1128
- refuser source clients: 25840
- refuser clients present in membership rows: 25840
- refuser real membership rows: 5912
- refuser placeholder rows: 21254

## Row Classes

- full_subscription: 89420
- refuser_without_membership: 21254
- trial_or_guest: 12463
- unknown_review_required: 1852

## Money Sources

- accumrg3305_sale_balance__info_rg3060_fld3070: 73662
- refuser_without_membership: 21254
- business_legacy_2018_full_subscription_zero_price_blank_payment: 17127
- business_free_trial_zero_price_blank_payment: 4970
- business_confirmed_free_trial_zero_price_blank_payment: 3649
- business_zero_fallback_payment_type_blank: 1811
- business_full_zero_no_payment_initial_balance_corporate_or_modifier: 1324
- info_rg3060_fld3072_debt_fallback__ambiguous_multi_membership_sale__info_rg3060_fld3070: 586
- business_zero_no_payment_blank_payment_type: 298
- business_historical_document131_refund_zero_direct_blank_payment: 187
- accumrg3305_sale_balance__document154_vt1137_fld1160: 80
- accumrg3305_sale_balance__info_rg3060_fld3070_negative_debt_clamped_to_zero: 18
- info_rg3060_fld3072_debt_fallback__no_unambiguous_register_balance__info_rg3060_fld3070: 16
- business_direct_free_site_week_sale_line_zero_blank_payment: 4
- zero_price_no_balance: 3

## Business Overrides

- business_legacy_2018_full_subscription_zero_price_blank_payment: 17127
- business_free_trial_zero_price_blank_payment: 4970
- business_confirmed_free_trial_zero_price_blank_payment: 3649
- business_zero_fallback_payment_type_blank: 1811
- business_full_zero_no_payment_initial_balance_corporate_or_modifier: 1324
- business_zero_no_payment_blank_payment_type: 298
- business_historical_document131_refund_zero_direct_blank_payment: 187
- business_direct_free_site_week_sale_line_zero_blank_payment: 4

## Exclusions

- exclude_active_later_contact_full: 7

## Payment Types

- безналичные: 69108
- blank: 50625
- наличные: 3063
- сбп: 2193

## Visits Left Sources

- not_visit_limited_membership: 102658
- refuser_without_membership: 21254
- business_expired_visit_limited_zero_visits_left: 1051
- rg3336_correct_dimension_balance: 25
- rg3336_visit_limited_balance_missing: 1

## Visit-Limited Register Balance Groups

- clean_register_balance: 966
- no_register_movements: 63
- receipt_not_equal_name_limit: 39
- negative_balance: 9

## Template Canonicalization

- checked_in_config: 96
- single_observed_variant: 26
- configured_historical_template_variant_preserved: 4
- configured_template_price_preserved_after_transaction_rebuild: 2
- configured_source_contract_absent: 1

## Refusers

- placeholder_rows: 21254
- real_membership_rows: 5912

## Branches

- Фитнес Империя (Гоголевский): 75743
- Фитнес Империя (Столица): 18797
- Фитнес Империя (Промышленная): 15951
- Фитнес Империя (Ровио): 14498

## Required Blank Counts

- none

## Hard Checks

- all row clients are from source final XLSX: yes
- contract_id unique: yes
- every contract_name exists in templates: yes
- every refuser client has a tagged row: yes
- every membership create_date equals its Document163 sale/payment_date: yes (mismatches=0)
