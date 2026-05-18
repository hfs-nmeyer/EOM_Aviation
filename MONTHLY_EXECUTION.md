# EOM Aviation — Monthly Execution Guide

## Automated Execution

The SQL Server Agent job **`EOM_Aviation_Monthly_Test`** runs automatically on the **1st of each month at 06:00 AM** on `200-ACT-DBS-01`.

To monitor or trigger manually from SSMS:

```
SQL Server Agent → Jobs → EOM_Aviation_Monthly_Test → Start Job at Step...
```

---

## Manual Execution Order

If you need to run the pipeline manually, execute the stored procedures in this sequence:

```sql
USE [Pricing_AIM];

-- 1. Backup production tables before any changes
EXEC dbo.run_aim_backup;

-- 2. Apollo loss data (from Icarus via HSQ-DB01)
EXEC dbo.run_test_AIM_Apollo_Loss;

-- 3. Diamond written/earned premium (prior-month period)
EXEC dbo.run_test_Diamond_WP_EP;

-- 4. AIM loss data
EXEC dbo.run_test_AIMLoss;

-- 5. Diamond airport table (coverage pivot)
EXEC dbo.run_test_Diamond_Airport_Table;

-- 6. Diamond Apollo rating + STT (longest step, ~10–20 min)
EXEC dbo.run_test_Diamond_Apollo;
```

> **Do not change the order.** Steps 2–5 populate tables that step 6 reads.

---

## Validation

After all procedures complete, run the validation script to compare test_ outputs against the current production tables:

```sql
:r 05_validation.sql
```

The script reports:

| Section | What It Checks |
|---|---|
| Row counts | Production vs test row totals for all 8 table pairs |
| Premium totals | Written, earned, unearned sums by period |
| Missing rows | Rows in prod not found in test (key mismatch) |
| Extra rows | Rows in test not found in prod |
| Financial diffs | Matched rows with premium variance > $0.01 |
| Coverage distribution | Written premium by Hull / Liability / Airport groups |
| STT summary | Average schedule-to-technical ratios |

---

## What Each Step Does

| Step | Procedure | Source | Target |
|---|---|---|---|
| 1 | `run_aim_backup` | Pricing_AIM production tables | Backup copies |
| 2 | `run_test_AIM_Apollo_Loss` | `[HSQ-DB01].Icarus` | `test_AIM_Apollo_Loss` |
| 3 | `run_test_Diamond_WP_EP` | `[AHI-S06].Diamond.EOPMonthlyPremiums` | `test_DiamondEarnedPremium_Aviation_JChenVScopy` |
| 4 | `run_test_AIMLoss` | Pricing_AIM loss tables | `test_aim_loss_data` |
| 5 | `run_test_Diamond_Airport_Table` | `[AHI-S06].Diamond` coverage tables | `test_Diamond_Airport_Table` |
| 6 | `run_test_Diamond_Apollo` | Diamond + Apollo rating tables | `test_diamond_data_aim`, `test_FlagRTransPol`, `test_aim_diamond_STT`, `test_aim_STT` |

---

## Timing

| Step | Typical Duration |
|---|---|
| run_aim_backup | 1–3 min |
| run_test_AIM_Apollo_Loss | 2–5 min |
| run_test_Diamond_WP_EP | 1–3 min |
| run_test_AIMLoss | 2–5 min |
| run_test_Diamond_Airport_Table | 1–3 min |
| run_test_Diamond_Apollo | 10–20 min |
| **Total** | **~20–40 min** |

---

## Troubleshooting

**Linked server timeout** — If a step fails with a linked server error, check connectivity to `[AHI-S06]` or `[HSQ-DB01]` and retry the failed step.

**Duplicate key on MERGE** — The natural key uniqueness constraints will raise an error if the same period is loaded twice with conflicting keys. The MERGE `WHEN MATCHED` clause handles reruns for `test_DiamondEarnedPremium_Aviation_JChenVScopy`. For the DROP/SELECT INTO tables (`test_aim_diamond_STT`, `test_aim_STT`), rerunning simply recreates them.

**Row count mismatch > 5%** — Investigate whether Diamond or Apollo source data has been reprocessed or if the prior-month date range calculation is correct (`DATEADD(MONTH, -1, GETDATE())`).

**Job history** — View in SSMS under `SQL Server Agent → Jobs → EOM_Aviation_Monthly_Test → View History`.
