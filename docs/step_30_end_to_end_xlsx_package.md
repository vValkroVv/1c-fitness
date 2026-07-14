# Step 30: standalone end-to-end package for nine XLSX

Date: `2026-07-14`

## Goal

Create a customer-transferable folder that reproduces
`output/20260630_delivery_full_cutoff/` from the restored
`Fitnes-30-06-26.bak` database without depending on the repository's macOS or
Docker restore implementation. Every export layer must use the backup finish
time `2026-06-30 23:27:03` as its only cutoff.

## Result

Package:

```text
end-to-end-xlsx/
```

The package contains:

- a cross-platform Python/TDS orchestrator;
- all three production SQL staging scripts and two stable export queries;
- the exact product decisions, manager pools and branch mapping;
- all seven required XLSX templates/reference workbooks;
- the final 6+3 delivery builder and validator;
- backup SHA-256 verification;
- Russian README, restore contract, runbook, business rules, source mapping,
  validation, troubleshooting and file manifest;
- safe runtime cleanup and release-ZIP creation.

It does not include the backup, SQL credentials, MDF/LDF, output XLSX,
intermediate exports or personal data.

## Input identity

```text
path used for verification: data/Fitnes-30-06-26.bak
size: 13137564672 bytes
sha256: 7e684086442f0eeac44014b9f5170da5c2873620c57788dbc59f58efed1d0810
verification: PASS
```

## Database preflight

The full package was run against the already restored database through a plain
TCP TDS connection. Package code did not invoke the macOS/Docker wrappers.

```text
database: FitnessRestored_20260630_macos
state: ONLINE
compatibility_level: 130
dbo source tables: 2503
required source tables: 17/17
```

## Full-run counters

```text
stg_clients: 73292
stg_subscriptions_all: 116267
stg_sales_all: 510407
final_funnel_clients: 73292
membership_import_facts: 101436
services_import_facts: 50710
problem 1: 10
problem 2: 41
problem 3: 203
problem union: 254
removed from clean membership: 254
delivery validation: PASS
```

The pipeline status also records `101436/101436` and `50710/50710` non-null
cutoff values, identical `MIN/MAX(cutoff_at)`, and maximum sale/payment times
not later than the backup finish time.

## Delivery and format comparison

After the built-in manifest validator passed, the root delivery was compared
byte-for-byte with the package delivery. All nine files matched.

The workbooks were also compared with the previous delivery templates on:

- sheet names and count;
- technical and Russian headers;
- cell styles and used number formats;
- freeze panes, filters, merged cells and column widths;
- visual rendering of all nine workbooks.

Expected delivery counts were reproduced exactly:

```text
39524 / 10907 / 121242 / 119 / 51 / 522 / 10 / 41 / 203
```

## Standalone ZIP audit

`scripts/create_release_zip.py` was executed after the corrected full run while
the work directory and generated XLSX existed. The resulting test ZIP:

```text
files: 46
ZIP size: 172039 bytes
runtime/personal files included: 0
backup/secrets included: 0
extracted scripts --help smoke with installed requirements: PASS
```

Markdown links were checked: `0` missing. All Python files compiled
successfully.

## Runtime cleanup

Generated work/output/logs inside `end-to-end-xlsx/` are runtime artifacts. The
customer-safe ZIP excludes them and keeps only empty `.gitkeep` files for the
directory layout. A future full run recreates all runtime artifacts.

The detailed rebuild report is
`docs/20260630_full_cutoff_rebuild_20260714.md`.
