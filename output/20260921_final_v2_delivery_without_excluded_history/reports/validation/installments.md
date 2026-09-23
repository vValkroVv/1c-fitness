# Rassrochka validation

- installment rows by name marker: 160
- installment rows with positive payment_left: 53
- installment rows without unambiguous register balance: 0

Rule used: `amount_of_payments` and `payment_left` are independent values from the sale-level `_AccumRg3305` balance at the backup cutoff. `InfoRg3060._Fld3072` is treated only as a debt fallback when the sale-to-membership allocation is not unambiguous.

## First Flagged Rows

- none
