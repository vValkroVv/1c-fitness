# Step 13: Email Source Deep Search

Date: 2026-05-07

## Goal

Find a canonical client email source after step 11 left email unresolved.

## Scripts And Logs

| Artifact | Purpose |
|---|---|
| `sql/04_email_client_link_probe.sql` | targeted search in client-linked contact registers |
| `sql/04_email_domain_probe.sql` | domain distribution without exposing raw email values |
| `sql/04_email_final_candidate_probe.sql` | final candidate counts and active-client coverage |
| `logs/step11_email_client_link_probe.txt` | targeted client-linked counts |
| `logs/step11_email_domain_probe.txt` | domain distribution counts |
| `logs/step11_email_final_candidate_probe.txt` | final candidate and coverage counts |
| `output/email_candidate_sources.csv` | safe summary for the mapping |

## Result

Canonical email source candidate found:

```text
email table: dbo._InfoRg5255
client join: dbo._InfoRg5255._Fld5256RRef -> dbo._Reference64._IDRRef
email column: dbo._InfoRg5255._Fld5257
```

Counts:

| Metric | Count |
|---|---:|
| `_InfoRg5255` rows | 72,427 |
| rows with email-like `_Fld5257` | 30 |
| distinct clients with email-like `_Fld5257` | 30 |
| current active clients on `2026-04-29` | 10,796 |
| active clients with `_InfoRg5255._Fld5257` email | 11 |

## Rejected Or Non-Canonical Sources

| Source | Finding | Decision |
|---|---|---|
| `dbo._InfoRg5867._Fld5869` | 7,562 values with `@`, all domain `c.us` | not email; looks like WhatsApp/JID contact IDs |
| `dbo._InfoRg5226._Fld5231` | 19 client-linked note/message rows with embedded email text | do not use as canonical email |
| `dbo._InfoRg5211._Fld5222` | 3 client-linked task/note rows with embedded email text | do not use as canonical email |
| `dbo._InfoRg5843` | message/social/chat text contains many `@` values | not a clean client email register |

## Decision For Extraction

Use `dbo._InfoRg5255._Fld5257` as the only structured client email source when
present, joined by `_Fld5256RRef` to `dbo._Reference64._IDRRef`.

For clients without this value, leave email empty and record the count in the
validation report. The low coverage means the restored 1C database likely does
not contain email for most clients, or those emails live in another external
system not present in this backup.
