# Membership import validation

- source final clients: 65231
- clients with at least one membership row: 64176
- source clients without membership rows: 1055
- client membership rows: 120040
- membership template rows: 114
- duplicate contract_id count: 0
- contract names missing in template file: 0
- uncertainty rows: 291
- refuser source clients: 25707
- refuser clients present in membership rows: 25707
- refuser real membership rows: 5854
- refuser placeholder rows: 21096

## Row Classes

- full_subscription: 84832
- refuser_without_membership: 21096
- trial_or_guest: 12406
- unknown_review_required: 1706

## Money Sources

- assume_paid_full_when_no_installment_marker: 68588
- refuser_without_membership: 21096
- business_legacy_2018_full_subscription_zero_price_blank_payment: 17125
- business_free_trial_zero_price_blank_payment: 4960
- business_confirmed_free_trial_zero_price_blank_payment: 3627
- business_zero_fallback_payment_type_blank: 1793
- business_full_zero_no_payment_initial_balance_corporate_or_modifier: 1313
- rg_fld3072_paid_candidate: 998
- business_zero_no_payment_blank_payment_type: 288
- business_historical_document131_refund_zero_direct_blank_payment: 177
- zero_price: 66
- matched_payment_amount_for_installment: 5
- business_direct_free_site_week_sale_line_zero_blank_payment: 4

## Business Overrides

- business_legacy_2018_full_subscription_zero_price_blank_payment: 17125
- business_free_trial_zero_price_blank_payment: 4960
- business_confirmed_free_trial_zero_price_blank_payment: 3627
- business_zero_fallback_payment_type_blank: 1793
- business_full_zero_no_payment_initial_balance_corporate_or_modifier: 1313
- business_zero_no_payment_blank_payment_type: 288
- business_historical_document131_refund_zero_direct_blank_payment: 177
- business_direct_free_site_week_sale_line_zero_blank_payment: 4

## Exclusions

- exclude_active_later_contact_full: 1

## Payment Types

- безналичные: 65247
- blank: 50383
- наличные: 2966
- сбп: 1444

## Visits Left Sources

- not_limited_subrent: 98015
- refuser_without_membership: 21096
- business_expired_limited_subrent_zero_visits_left: 916
- rg3336_correct_dimension_balance: 13

## Limited Subrent Register Balance Groups

- clean_register_balance: 868
- receipt_not_equal_name_limit: 39
- no_register_movements: 13
- negative_balance: 9

## Refusers

- placeholder_rows: 21096
- real_membership_rows: 5854

## Branches

- Фитнес Империя (Гоголевский): 72927
- Фитнес Империя (Столица): 18047
- Фитнес Империя (Промышленная): 15327
- Фитнес Империя (Ровио): 13739

## Required Blank Counts

- none

## Hard Checks

- all row clients are from source final XLSX: yes
- contract_id unique: yes
- every contract_name exists in templates: yes
- every refuser client has a tagged row: yes
