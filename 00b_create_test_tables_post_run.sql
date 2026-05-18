USE [Pricing_AIM]
GO

/*=============================================================================
  00b_create_test_tables_post_run.sql
  Purpose : Create test_ shadow tables for the two post-run procedures:
              run_test_AIM_Status_Pol      (steps 7)
              run_test_Rate_Monitor_Table  (step 8)

  All four tables are also created dynamically by their respective procedures
  via DROP + SELECT INTO on every run.  This script lets you pre-create them
  (e.g. to apply grants or indexes before the first run, or to restore the
  schema after a DROP without re-running the pipeline).

  Run once during initial setup, after 00_create_test_tables.sql.
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 1. test_aim_status_pol
--    One row per system/policy/edition with new/renewal/lost status flags.
--    Source proc : run_test_AIM_Status_Pol
-- ============================================================================
IF OBJECT_ID('dbo.test_aim_status_pol') IS NOT NULL
    DROP TABLE dbo.test_aim_status_pol;
GO

CREATE TABLE dbo.test_aim_status_pol
(
    -- Business columns
    System          VARCHAR(10)     NULL,
    client_id       INT             NULL,
    polid           INT             NULL,
    pol_ed          INT             NULL,
    eff_date        DATE            NULL,
    exp_date        DATE            NULL,
    status_pol_rn   VARCHAR(10)     NULL,   -- New | Ren
    status_pol_rl   VARCHAR(10)     NULL,   -- Ren | Lost | Inf | Cncl Pre
    pol_id_future   INT             NULL,
    pol_ed_future   INT             NULL,
    system_future   VARCHAR(10)     NULL,
    selector        INT             NULL,

    -- Audit / change-tracking
    row_hash        BINARY(32)      NULL,
    created_date    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated    DATETIME2(0)    NOT NULL DEFAULT GETDATE()
);

CREATE NONCLUSTERED INDEX IX_test_aim_status_pol_system_polid
    ON dbo.test_aim_status_pol (system, polid, pol_ed);
GO


-- ============================================================================
-- 2. test_aim_status_pol_policy_mapping
--    Rewrite-consolidation detail: maps each policy image to its
--    revised (rewrite-collapsed) policy ID.
--    Source proc : run_test_AIM_Status_Pol
-- ============================================================================
IF OBJECT_ID('dbo.test_aim_status_pol_policy_mapping') IS NOT NULL
    DROP TABLE dbo.test_aim_status_pol_policy_mapping;
GO

CREATE TABLE dbo.test_aim_status_pol_policy_mapping
(
    -- Business columns
    client_id                   INT             NULL,
    policy_id                   INT             NULL,
    policy                      VARCHAR(40)     NULL,
    renewal_ver                 INT             NULL,
    eff_date                    DATE            NULL,
    exp_date                    DATE            NULL,
    cancelled                   INT             NULL,
    cancelledon_date            DATE            NULL,
    firstwritten_date           DATE            NULL,
    rewrittenfrom_policy_id     INT             NULL,
    rewrittenfrom_policy        VARCHAR(40)     NULL,
    legacy_policynumber         VARCHAR(40)     NULL,
    premium_written             FLOAT           NULL,
    premium_fullterm            FLOAT           NULL,
    rewrite_policyimage_num     INT             NULL,
    rewrite_renewal_ver         INT             NULL,
    rewrite_eff_date            DATE            NULL,
    rewrite_exp_date            DATE            NULL,
    rewrite_cancelled           INT             NULL,
    rewrite_cancelledon_date    DATE            NULL,
    rewrite_premium_written     FLOAT           NULL,
    rewrite_premium_fullterm    FLOAT           NULL,
    written_term                INT             NULL,
    exp_term                    INT             NULL,
    revised_pol_id              INT             NULL,
    revised_pol_renewal_ver     INT             NULL,
    revised_eff_date            DATE            NULL,
    revised_exp_date            DATE            NULL,

    -- Audit / change-tracking
    row_hash        BINARY(32)      NULL,
    created_date    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated    DATETIME2(0)    NOT NULL DEFAULT GETDATE()
);

CREATE NONCLUSTERED INDEX IX_test_status_pol_mapping_policy
    ON dbo.test_aim_status_pol_policy_mapping (policy_id, renewal_ver);

CREATE NONCLUSTERED INDEX IX_test_status_pol_mapping_revised
    ON dbo.test_aim_status_pol_policy_mapping (revised_pol_id, revised_pol_renewal_ver);
GO


-- ============================================================================
-- 3. test_rate_monitor_data
--    Policy-level adequacy dataset: test_aim_STT joined to status_pol
--    with prior and future policy context columns added.
--    Wide table — inherits all columns from test_aim_STT plus ~20 extra.
--    Source proc : run_test_Rate_Monitor_Table
--
--    Key columns documented here; full column list is determined at runtime
--    by the SELECT * from test_aim_STT in the procedure.
-- ============================================================================
IF OBJECT_ID('dbo.test_rate_monitor_data') IS NOT NULL
    DROP TABLE dbo.test_rate_monitor_data;
GO

-- Pre-create as a minimal placeholder; the procedure will DROP and
-- recreate with the full column set on first run.
CREATE TABLE dbo.test_rate_monitor_data
(
    -- Surrogate / audit
    row_hash        BINARY(32)      NULL,
    created_date    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated    DATETIME2(0)    NOT NULL DEFAULT GETDATE()
);
GO


-- ============================================================================
-- 4. test_rate_monitor_summary
--    Aggregated expiry/renewal adequacy report by month and status bucket.
--    Source proc : run_test_Rate_Monitor_Table
-- ============================================================================
IF OBJECT_ID('dbo.test_rate_monitor_summary') IS NOT NULL
    DROP TABLE dbo.test_rate_monitor_summary;
GO

CREATE TABLE dbo.test_rate_monitor_summary
(
    -- Business columns
    mth_val                     INT             NULL,   -- YYYYMM of valuation month
    expr_flag_where             INT             NULL,
    expr_pol_ct                 INT             NULL,
    status_pol_rl               VARCHAR(20)     NULL,   -- Ren | Lost | Inf | Cncl Pre | No Covg
    mth_pol_exp                 INT             NULL,   -- YYYYMM of policy expiry
    prem_written                FLOAT           NULL,
    r_adq_written               FLOAT           NULL,
    r_adq_tech_written          FLOAT           NULL,
    rr_adq_tech_written         FLOAT           NULL,
    rr_adq_tech_annual          FLOAT           NULL,
    rr_padq_tech_annual         FLOAT           NULL,
    rr_blpadq_tech_annual       FLOAT           NULL,
    [ren flag where]            INT             NULL,
    [ren pol ct]                INT             NULL,
    [ren status]                VARCHAR(20)     NULL,
    [ren mth pol eff]           INT             NULL,
    [ren prem written]          FLOAT           NULL,
    [ren r_adq written]         FLOAT           NULL,
    [ren r_adq tech written]    FLOAT           NULL,
    [ren rr_adq tech written]   FLOAT           NULL,
    [ren rr_adq tech annual]    FLOAT           NULL,
    [ren rr_padq tech annual]   FLOAT           NULL,
    [ren rr_blpadq tech annual] FLOAT           NULL,

    -- Audit / change-tracking
    row_hash        BINARY(32)      NULL,
    created_date    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated    DATETIME2(0)    NOT NULL DEFAULT GETDATE()
);

CREATE NONCLUSTERED INDEX IX_test_rate_monitor_summary_mth
    ON dbo.test_rate_monitor_summary (mth_val, mth_pol_exp, status_pol_rl);
GO

PRINT 'Post-run test tables created: test_aim_status_pol, test_aim_status_pol_policy_mapping, test_rate_monitor_data, test_rate_monitor_summary';
