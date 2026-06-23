# Rassrochka validation

- installment rows by name marker: 21
- installment rows with positive payment_left: 18
- installment rows with missing paid candidate: 0

Rule used: `amount_of_payments = InfoRg3060._Fld3072` when it is positive; otherwise, for rows with `рассрочка` in the name, fallback to the nearest matched `Document152` payment amount. `payment_left = price - amount_of_payments`. Rows are flagged only when both sources are empty.

## First Flagged Rows

- none
