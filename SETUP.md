# EOM Aviation — Setup Guide

## Overview

This repository contains the end-of-month (EOM) aviation insurance premium and loss processing pipeline for **Pricing_AIM** on `200-ACT-DBS-01`.

The pipeline extracts written/earned premium and loss data from linked servers (Diamond, Apollo/NPC_AIM, Icarus) and loads it into test shadow tables for validation before promoting to production.

---

## Prerequisites

| Requirement | Detail |
|---|---|
| SQL Server | 200-ACT-DBS-01 |
| Database | Pricing_AIM |
| Linked server | `[AHI-S06]` → Diamond |
| Linked server | `[HSQ-DB01]` → NPC_AIM, Icarus |
| Linked server | `pricing_hspl` |
| Permissions | `db_datareader`, `db_datawriter`, `db_ddladmin` on Pricing_AIM |
| SQL Server Agent | Running on 200-ACT-DBS-01 |

---

## One-Time Setup

Run these scripts **once** in order to create the test environment:

```sql
-- 1. Create all test_ shadow tables
--    Run as: 200-ACT-DBS-01 > Pricing_AIM
:r 00_create_test_tables.sql

-- 2. Create all test_ stored procedures
:r sp_run_test_Diamond_WP_EP.sql
:r sp_run_test_AIM_Apollo_Loss.sql
:r sp_run_test_AIMLoss.sql
:r sp_run_test_Diamond_Airport_Table.sql
:r sp_run_test_Diamond_Apollo.sql

-- 3. Create the SQL Agent automation job
--    Run against msdb:
:r 04_monthly_job.sql
```

> **Note:** `sp_run_AIM_backup.sql` targets the original backup procedure and is not modified. The Agent job calls `run_aim_backup` directly.

---

## Test Tables Created

| Test Table | Source Table | Populated By |
|---|---|---|
| `test_DiamondEarnedPremium_Aviation_JChenVScopy` | `DiamondEarnedPremium_Aviation_JChenVScopy` | `run_test_Diamond_WP_EP` |
| `test_AIM_Apollo_Loss` | `AIM_Apollo_Loss` | `run_test_AIM_Apollo_Loss` |
| `test_aim_loss_data` | `aim_loss_data` | `run_test_AIMLoss` |
| `test_Diamond_Airport_Table` | `Diamond_Airport_Table` | `run_test_Diamond_Airport_Table` |
| `test_diamond_data_aim` | `diamond_data_aim` | `run_test_Diamond_Apollo` |
| `test_FlagRTransPol` | `FlagRTransPol` | `run_test_Diamond_Apollo` |
| `test_aim_diamond_STT` | `aim_diamond_STT` | `run_test_Diamond_Apollo` |
| `test_aim_STT` | `aim_STT` | `run_test_Diamond_Apollo` |

All test tables include three additional columns not present in the originals:

| Column | Type | Purpose |
|---|---|---|
| `row_hash` | `BINARY(32)` | SHA2-256 fingerprint of key financial columns; drives MERGE updates |
| `created_date` | `DATETIME2(0)` | Set once on first INSERT |
| `last_updated` | `DATETIME2(0)` | Refreshed on every MERGE UPDATE |

---

## Improvements Over Original Procedures

- **MERGE instead of INSERT** — reruns update existing rows rather than duplicating them
- **CTE coverage mappings** — coverage code groups defined once, not repeated in GROUP BY
- **Staging temp tables** — cross-server data pulled into `#staged` before any write to Pricing_AIM, reducing linked-server latch time
- **Dead code removed** — diagnostic SELECT statements that returned result sets without side effects
- **`SET NOCOUNT ON`** — suppresses row-count messages for cleaner Agent job logs
- **`CREATE OR ALTER PROCEDURE`** — idempotent deployment; no separate DROP needed
- **Row hash** — binary fingerprint enables change detection without column-by-column comparison
