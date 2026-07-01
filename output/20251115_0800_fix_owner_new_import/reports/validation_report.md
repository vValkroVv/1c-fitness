# Membership import validation

- source final clients: 64934
- clients with at least one membership row: 43137
- source clients without membership rows: 21797
- client membership rows: 99383
- membership template rows: 114
- duplicate contract_id count: 0
- contract names missing in template file: 0
- uncertainty rows: 330

## Row Classes

- full_subscription: 85253
- trial_or_guest: 12425
- unknown_review_required: 1705

## Money Sources

- assume_paid_full_when_no_installment_marker: 68475
- business_legacy_2018_full_subscription_zero_price_blank_payment: 17129
- business_free_trial_zero_price_blank_payment: 4958
- business_confirmed_free_trial_zero_price_blank_payment: 3626
- business_zero_fallback_payment_type_blank: 1792
- rg_fld3072_paid_candidate: 1559
- business_full_zero_no_payment_initial_balance_corporate_or_modifier: 1312
- business_zero_no_payment_blank_payment_type: 288
- business_historical_document131_refund_zero_direct_blank_payment: 176
- zero_price: 61
- business_direct_free_site_week_sale_line_zero_blank_payment: 4
- matched_payment_amount_for_installment: 3

## Business Overrides

- business_legacy_2018_full_subscription_zero_price_blank_payment: 17129
- business_free_trial_zero_price_blank_payment: 4958
- business_confirmed_free_trial_zero_price_blank_payment: 3626
- business_zero_fallback_payment_type_blank: 1792
- business_full_zero_no_payment_initial_balance_corporate_or_modifier: 1312
- business_zero_no_payment_blank_payment_type: 288
- business_historical_document131_refund_zero_direct_blank_payment: 176
- business_direct_free_site_week_sale_line_zero_blank_payment: 4

## Exclusions

- exclude_active_later_contact_full: 4

## Payment Types

- безналичные: 65383
- blank: 29285
- наличные: 3266
- сбп: 1449

## Visits Left Sources

- not_limited_subrent: 98455
- business_expired_limited_subrent_zero_visits_left: 916
- rg3336_correct_dimension_balance: 12

## Limited Subrent Register Balance Groups

- clean_register_balance: 867
- receipt_not_equal_name_limit: 39
- no_register_movements: 13
- negative_balance: 9

## Required Blank Counts

- none

## Hard Checks

- all row clients are from source final XLSX: yes
- contract_id unique: yes
- every contract_name exists in templates: yes
