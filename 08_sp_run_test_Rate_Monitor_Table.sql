USE [Pricing_AIM]
GO

/*=============================================================================
  sp_run_test_Rate_Monitor_Table.sql
  Purpose : Join test_aim_STT with test_aim_status_pol to produce a
            policy-level adequacy dataset and an aggregated rate monitor
            report by expiry month and renewal status.

  Outputs (DROP + SELECT INTO each run):
    dbo.test_rate_monitor_data    -- policy-level with prior/future policy links
    dbo.test_rate_monitor_summary -- expiry/renewal adequacy aggregated by month

  Depends on (run after):
    run_test_Diamond_Apollo   -> dbo.test_aim_STT
    run_test_AIM_Status_Pol   -> dbo.test_aim_status_pol
                              -> dbo.test_aim_status_pol_policy_mapping

  Improvements over original:
    - Wrapped in CREATE OR ALTER PROCEDURE with BEGIN TRY/CATCH
    - SET NOCOUNT ON
    - Diagnostic SELECTs at top removed
    - 1=1 AND 1=1... placeholder filter stubs removed; filter written directly
    - Dead code comment block removed
    - Final SELECT stored into test_rate_monitor_summary (DROP + SELECT INTO)
    - Row hash added to both output tables
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[run_test_Rate_Monitor_Table]
AS
BEGIN TRY
    SET NOCOUNT ON;
    DECLARE @startTime DATETIME = GETDATE();

    -- -----------------------------------------------------------------------
    -- Diamond policy mapping: one row per policy_id/renewal_ver -> revised IDs
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#diamond_mapping') IS NOT NULL DROP TABLE #diamond_mapping;

    SELECT DISTINCT
        policy_id,
        renewal_ver,
        revised_pol_id,
        revised_pol_renewal_ver
    INTO #diamond_mapping
    FROM dbo.test_aim_status_pol_policy_mapping;

    -- Uniqueness guards: duplicates would corrupt the subsequent joins
    IF (SELECT COUNT(*) FROM (
            SELECT system, polid, pol_ed
            FROM dbo.test_aim_status_pol
            GROUP BY system, polid, pol_ed
            HAVING COUNT(*) > 1
        ) a) > 0
        THROW 50001, 'Duplicate key in test_aim_status_pol (system, polid, pol_ed)', 1;

    IF (SELECT COUNT(*) FROM (
            SELECT policy_id, renewal_ver
            FROM #diamond_mapping
            GROUP BY policy_id, renewal_ver
            HAVING COUNT(*) > 1
        ) a) > 0
        THROW 50001, 'Duplicate key in #diamond_mapping (policy_id, renewal_ver)', 1;

    -- -----------------------------------------------------------------------
    -- Join test_aim_STT to status_pol to get AC-adjusted date/status columns
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp01') IS NOT NULL DROP TABLE #temp01;

    SELECT
        a.*,
        ISNULL(c.polid,      a.policy_id)                       AS pol_id_ac,
        ISNULL(c.pol_ed,     a.pol_edition)                     AS pol_ed_ac,
        CAST(ISNULL(c.eff_date, a.date_pol_eff) AS DATE)        AS eff_date_ac,
        CAST(ISNULL(c.exp_date, a.date_pol_exp) AS DATE)        AS exp_date_ac,
        DATEPART(yy, ISNULL(c.eff_date, a.date_pol_eff)) * 100
            + DATEPART(mm, ISNULL(c.eff_date, a.date_pol_eff)) AS mth_pol_eff_ac,
        DATEPART(yy, ISNULL(c.exp_date, a.date_pol_exp)) * 100
            + DATEPART(mm, ISNULL(c.exp_date, a.date_pol_exp)) AS mth_pol_exp_ac,
        YEAR(ISNULL(c.eff_date, a.date_pol_eff)) * 10
            + CEILING((MONTH(ISNULL(c.eff_date, a.date_pol_eff)) - 1) / 3.0) + 1
                                                                AS qtr_pol_eff_ac,
        YEAR(ISNULL(c.eff_date, a.date_pol_eff)) * 10
            + CEILING((MONTH(ISNULL(c.eff_date, a.date_pol_eff)) - 1) / 3.0) + 1
                                                                AS qtr_pol_exp_ac,
        YEAR(ISNULL(c.eff_date, a.date_pol_eff))               AS yr_pol_ac,
        YEAR(ISNULL(c.exp_date, a.date_pol_exp))               AS yr_pol_exp_ac,
        1                                                        AS yr_pol_exp,
        c.status_pol_rn,
        c.status_pol_rl,
        c.pol_id_future                                          AS pol_id_ac_future,
        c.pol_ed_future                                          AS pol_ed_ac_future,
        c.system_future,
        CAST(ISNULL(c.polid, a.policy_id) AS FLOAT) * 100
            + CAST(ISNULL(c.pol_ed, a.pol_edition) AS FLOAT)   AS pol_num_full_clean_ac,
        ISNULL(
            CAST(c.pol_id_future AS FLOAT) * 100
                + CAST(c.pol_ed_future AS FLOAT),
            0
        )                                                        AS pol_num_full_clean_future_ac
    INTO #temp01
    FROM dbo.test_aim_STT a
    LEFT JOIN #diamond_mapping b
        ON  a.policy_id   = b.policy_id
        AND a.system      = 'Diamond'
        AND b.renewal_ver = a.pol_edition
    LEFT JOIN dbo.test_aim_status_pol c
        ON  c.system = a.system
        AND c.polid  = ISNULL(b.revised_pol_id,          a.policy_id)
        AND c.pol_ed = ISNULL(b.revised_pol_renewal_ver, a.pol_edition)
    WHERE a.policy_id IS NOT NULL;

    -- -----------------------------------------------------------------------
    -- Future/prior policy lookup with dedup selectors
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp02') IS NOT NULL DROP TABLE #temp02;

    SELECT
        pol_id_ac,
        pol_num_full_clean_ac,
        pol_num_full_clean_future_ac,
        CAST(eff_date_ac AS DATE)  AS eff_date_ac,
        CAST(exp_date_ac AS DATE)  AS exp_date_ac,
        mth_pol_eff_ac,
        mth_pol_exp_ac,
        status_pol_rl,
        status_pol_rn,
        ROW_NUMBER() OVER (
            PARTITION BY pol_num_full_clean_future_ac
            ORDER BY status_pol_rl DESC
        ) AS selector_future,
        ROW_NUMBER() OVER (
            PARTITION BY pol_num_full_clean_ac
            ORDER BY status_pol_rn DESC
        ) AS selector_current
    INTO #temp02
    FROM #temp01
    GROUP BY
        pol_id_ac, pol_num_full_clean_ac, pol_num_full_clean_future_ac,
        CAST(eff_date_ac AS DATE), CAST(exp_date_ac AS DATE),
        mth_pol_eff_ac, mth_pol_exp_ac, status_pol_rl, status_pol_rn;

    -- -----------------------------------------------------------------------
    -- Write: test_rate_monitor_data (policy-level with prior/future context)
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('dbo.test_rate_monitor_data') IS NOT NULL
        DROP TABLE dbo.test_rate_monitor_data;

    SELECT
        a.*,
        CAST(b.eff_date_ac AS DATE)  AS future_date_pol_eff,
        CAST(b.exp_date_ac AS DATE)  AS future_date_pol_exp,
        b.mth_pol_eff_ac             AS future_mth_eff,
        b.mth_pol_exp_ac             AS future_mth_exp,
        b.status_pol_rl              AS future_status_pol_rl,
        b.status_pol_rn              AS future_status_pol_rn,
        b.pol_num_full_clean_ac      AS pol_num_full_clean_future,
        CAST(c.eff_date_ac AS DATE)  AS prior_date_pol_eff,
        CAST(c.exp_date_ac AS DATE)  AS prior_date_pol_exp,
        c.mth_pol_eff_ac             AS prior_mth_eff,
        c.mth_pol_exp_ac             AS prior_mth_exp,
        c.status_pol_rl              AS prior_status_pol_rl,
        c.status_pol_rn              AS prior_status_pol_rn,
        c.pol_num_full_clean_ac      AS prior_pol_num_full_clean,
        YEAR(DATEADD(MONTH, -1, GETDATE())) * 100
            + MONTH(DATEADD(MONTH, -1, GETDATE())) AS mth_val
    INTO dbo.test_rate_monitor_data
    FROM #temp01 a
    LEFT JOIN #temp02 b
        ON  b.pol_num_full_clean_ac          = a.pol_num_full_clean_future_ac
        AND b.selector_current               = 1
    LEFT JOIN #temp02 c
        ON  c.pol_num_full_clean_future_ac   = a.pol_num_full_clean_ac
        AND c.selector_future                = 1;

    -- Overwrite date/period columns with the AC-adjusted values
    UPDATE dbo.test_rate_monitor_data SET
        mth_pol_eff  = mth_pol_eff_ac,
        mth_pol_exp  = mth_pol_exp_ac,
        date_pol_exp = exp_date_ac,
        date_pol_eff = eff_date_ac,
        pol_edition  = pol_ed_ac,
        policy_id    = pol_id_ac,
        yr_pol       = yr_pol_ac,
        yr_pol_exp   = yr_pol_exp_ac,
        qtr_pol_eff  = qtr_pol_eff_ac,
        qtr_pol_exp  = qtr_pol_exp_ac;

    ALTER TABLE dbo.test_rate_monitor_data ADD
        row_hash     BINARY(32)   NULL,
        created_date DATETIME2(0) NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0) NOT NULL DEFAULT GETDATE();

    UPDATE dbo.test_rate_monitor_data
    SET row_hash = CONVERT(BINARY(32), HASHBYTES('SHA2_256',
        ISNULL(CAST(pol_num_full_clean_ac AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(mth_val               AS NVARCHAR(10)), '') + '|' +
        ISNULL(CAST(prem_written          AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(r_adq_written         AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(rr_adq_tech_written   AS NVARCHAR(30)), '')));

    -- -----------------------------------------------------------------------
    -- Write: test_rate_monitor_summary
    --   Aggregates expiring and renewing policy pairs by month.
    --   Filter: LOB = Aircraft Liability (reserving = 'ACL'), policy year >= 2017
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('dbo.test_rate_monitor_summary') IS NOT NULL
        DROP TABLE dbo.test_rate_monitor_summary;

    SELECT
        mth_val,
        SUM(expr_flag_where)              AS expr_flag_where,
        SUM(expr_pol_ct)                  AS expr_pol_ct,
        CASE WHEN prem_written = 0 AND status_pol_rl = 'Ren'
             THEN 'No Covg' ELSE status_pol_rl END AS status_pol_rl,
        mth_pol_exp,
        SUM(prem_written)                 AS prem_written,
        SUM(r_adq_written)                AS r_adq_written,
        SUM(r_adq_tech_written)           AS r_adq_tech_written,
        SUM(rr_adq_tech_written)          AS rr_adq_tech_written,
        SUM(rr_adq_tech_annual)           AS rr_adq_tech_annual,
        SUM(rr_padq_tech_annual)          AS rr_padq_tech_annual,
        SUM(rr_blpadq_tech_annual)        AS rr_blpadq_tech_annual,
        SUM([ren flag where])             AS [ren flag where],
        SUM([ren pol ct])                 AS [ren pol ct],
        CASE WHEN [ren prem written] = 0 AND [ren status] = 'Renewal'
             THEN 'No Covg' ELSE [ren status] END AS [ren status],
        ISNULL([ren mth pol eff], 0)      AS [ren mth pol eff],
        SUM([ren prem written])           AS [ren prem written],
        SUM([ren r_adq written])          AS [ren r_adq written],
        SUM([ren r_adq tech written])     AS [ren r_adq tech written],
        SUM([ren rr_adq tech written])    AS [ren rr_adq tech written],
        SUM([ren rr_adq tech annual])     AS [ren rr_adq tech annual],
        SUM([ren rr_padq tech annual])    AS [ren rr_padq tech annual],
        SUM([ren rr_blpadq tech annual])  AS [ren rr_blpadq tech annual]
    INTO dbo.test_rate_monitor_summary
    FROM (
        -- Inner aggregate: per expiry-bucket / renewal-bucket pair
        SELECT
            mth_val,
            pol_num_full_exp,
            SUM(expr_flag_where)              AS expr_flag_where,
            SUM(expr_pol_ct)                  AS expr_pol_ct,
            ISNULL(status_pol_rl, 'null')     AS status_pol_rl,
            mth_pol_exp,
            SUM(prem_written)                 AS prem_written,
            SUM(r_adq_written)                AS r_adq_written,
            SUM(r_adq_tech_written)           AS r_adq_tech_written,
            SUM(rr_adq_tech_written)          AS rr_adq_tech_written,
            SUM(rr_adq_tech_annual)           AS rr_adq_tech_annual,
            SUM(rr_padq_tech_annual)          AS rr_padq_tech_annual,
            SUM(rr_blpadq_tech_annual)        AS rr_blpadq_tech_annual,
            SUM([ren flag where])             AS [ren flag where],
            SUM([ren pol ct])                 AS [ren pol ct],
            pol_num_full_clean_future,
            ISNULL([ren status], 'null')      AS [ren status],
            ISNULL([ren mth pol eff], 0)      AS [ren mth pol eff],
            SUM([ren prem written])           AS [ren prem written],
            SUM([ren r_adq written])          AS [ren r_adq written],
            SUM([ren r_adq tech written])     AS [ren r_adq tech written],
            SUM([ren rr_adq tech written])    AS [ren rr_adq tech written],
            SUM([ren rr_adq tech annual])     AS [ren rr_adq tech annual],
            SUM([ren rr_padq tech annual])    AS [ren rr_padq tech annual],
            SUM([ren rr_blpadq tech annual])  AS [ren rr_blpadq tech annual]
        FROM (
            -- Expiring policies looking forward to their renewal
            SELECT
                a.mth_val,
                a.pol_num_full_clean_ac             AS pol_num_full_exp,
                COUNT(DISTINCT a.pol_num_full_clean) AS expr_flag_where,
                COUNT(DISTINCT a.pol_num_full_clean) AS expr_pol_ct,
                a.status_pol_rl,
                a.mth_pol_exp_ac                    AS mth_pol_exp,
                SUM(a.prem_written)                 AS prem_written,
                SUM(a.r_adq_written)                AS r_adq_written,
                SUM(a.r_adq_tech_written)           AS r_adq_tech_written,
                SUM(a.rr_adq_tech_written)          AS rr_adq_tech_written,
                SUM(a.rr_adq_tech_annual)           AS rr_adq_tech_annual,
                SUM(a.rr_padq_tech_annual)          AS rr_padq_tech_annual,
                SUM(a.rr_blpadq_tech_annual)        AS rr_blpadq_tech_annual,
                0                                   AS [ren flag where],
                0                                   AS [ren pol ct],
                pol_num_full_clean_future,
                ISNULL(future_status_pol_rn, 'null') AS [ren status],
                ISNULL(future_mth_eff, 0)           AS [ren mth pol eff],
                0 AS [ren prem written],
                0 AS [ren r_adq written],
                0 AS [ren r_adq tech written],
                0 AS [ren rr_adq tech written],
                0 AS [ren rr_adq tech annual],
                0 AS [ren rr_padq tech annual],
                0 AS [ren rr_blpadq tech annual]
            FROM dbo.test_rate_monitor_data a
            WHERE a.yr_pol    >= 2017
              AND a.reserving  = 'ACL'
            GROUP BY
                a.mth_val, a.status_pol_rl, a.mth_pol_exp_ac,
                ISNULL(future_mth_eff, 0), ISNULL(future_status_pol_rn, 'null'),
                a.pol_num_full_clean_ac, pol_num_full_clean_future

            UNION ALL

            -- Renewing policies looking back to their expiring predecessor
            SELECT
                a.mth_val,
                a.prior_pol_num_full_clean,
                0                                    AS [expr flag where],
                0                                    AS [expr pol ct],
                ISNULL(prior_status_pol_rl, 'Null')  AS [expr status],
                prior_mth_exp                        AS [expr mth pol ex],
                0 AS [expr prem written],
                0 AS [expr r_adq written],
                0 AS [expr r_adq tech written],
                0 AS [expr rr_adq tech written],
                0 AS [expr rr_adq tech annual],
                0 AS [expr rr_padq tech annual],
                0 AS [expr rr_blpadq tech annual],
                COUNT(DISTINCT a.pol_num_full_clean)  AS [ren flag where],
                COUNT(DISTINCT a.pol_num_full_clean)  AS [ren pol ct],
                a.pol_num_full_clean_ac,
                a.status_pol_rn,
                a.mth_pol_eff_ac,
                SUM(a.prem_written)                  AS prem_written,
                SUM(a.r_adq_written)                 AS r_adq_written,
                SUM(a.r_adq_tech_written)            AS r_adq_tech_written,
                SUM(a.rr_adq_tech_written)           AS rr_adq_tech_written,
                SUM(a.rr_adq_tech_annual)            AS rr_adq_tech_annual,
                SUM(a.rr_padq_tech_annual)           AS rr_padq_tech_annual,
                SUM(a.rr_blpadq_tech_annual)         AS rr_blpadq_tech_annual
            FROM dbo.test_rate_monitor_data a
            WHERE a.yr_pol    >= 2017
              AND a.reserving  = 'ACL'
            GROUP BY
                a.mth_val, a.status_pol_rn, a.mth_pol_eff_ac,
                ISNULL(prior_status_pol_rl, 'Null'), a.pol_num_full_clean_ac,
                a.prior_pol_num_full_clean, prior_status_pol_rl, prior_mth_exp
        ) a1
        GROUP BY
            mth_val, ISNULL(status_pol_rl, 'null'), mth_pol_exp,
            ISNULL([ren status], 'null'), ISNULL([ren mth pol eff], 0),
            pol_num_full_clean_future, pol_num_full_exp
    ) a2
    GROUP BY
        mth_val,
        CASE WHEN prem_written = 0 AND status_pol_rl = 'Ren'
             THEN 'No Covg' ELSE status_pol_rl END,
        mth_pol_exp,
        CASE WHEN [ren prem written] = 0 AND [ren status] = 'Renewal'
             THEN 'No Covg' ELSE [ren status] END,
        ISNULL([ren mth pol eff], 0);

    ALTER TABLE dbo.test_rate_monitor_summary ADD
        row_hash     BINARY(32)   NULL,
        created_date DATETIME2(0) NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0) NOT NULL DEFAULT GETDATE();

    UPDATE dbo.test_rate_monitor_summary
    SET row_hash = CONVERT(BINARY(32), HASHBYTES('SHA2_256',
        ISNULL(CAST(mth_val             AS NVARCHAR(10)), '') + '|' +
        ISNULL(CAST(mth_pol_exp         AS NVARCHAR(10)), '') + '|' +
        ISNULL(CAST(status_pol_rl       AS NVARCHAR(20)), '') + '|' +
        ISNULL(CAST(prem_written        AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(r_adq_written       AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(rr_adq_tech_written AS NVARCHAR(30)), '')));

    DROP TABLE #diamond_mapping, #temp01, #temp02;

    DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID);
    EXEC UPDATE_QUERY_TIMES @PROC_NAME, @startTime;

END TRY
BEGIN CATCH
    SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE;
END CATCH
GO
