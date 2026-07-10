# Step 30: standalone end-to-end package for nine XLSX

Date: `2026-07-10`

## Goal

Create a customer-transferable folder that reproduces
`output/20260630_delivery_without_active_problems/` from the restored
`Fitnes-30-06-26.bak` database without depending on the repository's macOS or
Docker restore implementation.

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
membership_import_facts: 99959
services_import_facts: 50215
problem 1: 3
problem 2: 41
problem 3: 179
problem union: 223
removed from clean membership: 223
delivery validation: PASS
```

## Exact comparison

After the built-in manifest validator passed, an independent cell-by-cell
comparison was run against the tracked reference folder
`output/20260630_delivery_without_active_problems/`.

All nine workbooks matched on:

- every cell value;
- every row and its order;
- every cell style id;
- every cell number format.

Expected delivery counts were reproduced exactly:

```text
39524 / 10907 / 119817 / 114 / 51 / 522 / 3 / 41 / 179
```

## Standalone ZIP audit

`scripts/create_release_zip.py` was executed while the 1.3 GiB work directory
and generated XLSX existed. The resulting test ZIP:

```text
files: 46
uncompressed package inputs: about 0.54 MB
runtime/personal files included: 0
backup/secrets included: 0
extracted scripts --help smoke: PASS
extracted backup size-check smoke: PASS
```

Markdown links were checked: `0` missing. All Python files compiled
successfully.

## Runtime cleanup

Generated work/output/logs inside `end-to-end-xlsx/` are test artifacts only
and are removed before handoff. Empty `.gitkeep` files preserve the directory
layout. A future full run recreates the same artifacts.
