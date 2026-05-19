USE [Pricing_AIM]
GO

/*=============================================================================
  sp_run_test_AIMLoss.sql
  Purpose : Combine Apollo loss data (aim_loss_ulae) with Diamond loss
            data (pricing_hspl auto_hspl_loss_15YY_XXXX) into test_AIMLoss.

  Improvements over original:
    - NULL fixups for ISOCatNumber, date_close_act, mth_occ/ft_close_act, and
      date_reopen_act are handled inline in the SELECT rather than via
      separate UPDATE passes, eliminating two full temp-table scans.
    - Diamond data is staged into a global temp table (##diamond_src) instead
      of a permanent dbo.aim_loss_Diamond table, avoiding permanent object
      pollution and explicit cleanup risk.
    - TRUNCATE + INSERT replaces DROP + SELECT INTO, so the test table retains
      its identity seed, indexes, constraints, and metadata columns.
    - Row hash computed over financial columns for downstream change detection.
    - Dead-code comments and duplicate SELECT patterns removed.
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[run_test_AIMLoss]
AS
BEGIN TRY
    SET NOCOUNT ON;
    DECLARE @startTime DATETIME = GETDATE();

    -- -----------------------------------------------------------------------
    -- Derive prior-month suffix used in the Diamond loss table name.
    -- Pattern: auto_hspl_loss_15YY_MMYY  (e.g. auto_hspl_loss_1526_0426)
    -- -----------------------------------------------------------------------
    DECLARE @MMYY  VARCHAR(4) =
        CONCAT(
            RIGHT('00' + CONVERT(NVARCHAR(2), MONTH(DATEADD(MONTH, -1, GETDATE()))), 2),
            RIGHT(YEAR (DATEADD(MONTH, -1, GETDATE())), 2)
        );
    DECLARE @YY    VARCHAR(2) = RIGHT(@MMYY, 2);
    DECLARE @tbl   NVARCHAR(256) =
        N'pricing_hspl.dbo.[auto_hspl_loss_15' + @YY + N'_' + @MMYY + N']';

    -- -----------------------------------------------------------------------
    -- Stage Apollo loss data from aim_loss_ulae (production source table; not a pipeline output).
    -- Normalises column names to the shared AIMLoss schema and resolves the
    -- ISOCatNumber / CAT_indicator inline (avoids a separate UPDATE pass).
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#apollo') IS NOT NULL DROP TABLE #apollo;

    SELECT
        'Apollo'                                                    AS system,
        a.[Claim No]                                                AS clm_ft_num,
        a.[Claim No]                                                AS claim_number,
        a.Clmid                                                     AS claimcontrol_id,
        1                                                           AS claimant_num,
        1                                                           AS claimfeature_num,
        a.Reserving                                                 AS reserving,
        a.[policy no]                                               AS policy,
        a.polid                                                     AS policy_id,
        'ApolloData'                                                AS company,
        RIGHT(a.[policy no], 2)                                     AS policyimage_num,
        a.AircraftID                                                AS aircraft_num,
        a.Claim_state                                               AS state_risk,
        a.AY                                                        AS yr_loss,
        a.qtr_loss,
        a.mth_loss,
        a.DOL                                                       AS date_loss,
        a.[Close Date]                                              AS date_occ_close,
        a.[Close Date]                                              AS date_ft_close,
        DATEPART(yy, a.TRANS_DATE) * 100 + DATEPART(mm, a.TRANS_DATE)
                                                                    AS mth_cal_earn,
        a.mth_val,
        a.qtr_val,
        LEFT(a.qtr_val, 4)                                         AS yr_val,
        CASE WHEN RIGHT(a.mth_val, 1)  IN ('3','6','9')
                  OR RIGHT(a.mth_val, 2) = '12' THEN 1 ELSE 0
        END                                                         AS qtr_ind,
        CASE WHEN RIGHT(a.mth_val, 2) = '12' THEN 1 ELSE 0
        END                                                         AS yr_ind,
        a.mth_rept                                                  AS rept_mth_occ,
        a.qtr_rept                                                  AS rept_qtr_occ,
        LEFT(a.qtr_rept, 4)                                        AS rept_yr_occ,
        a.REPORTED_DATE                                             AS occ_rept_date,
        a.REPORTED_DATE                                             AS occ_rept_date_act,
        a.mth_rept                                                  AS rept_mth_ft,
        a.qtr_rept                                                  AS rept_qtr_ft,
        LEFT(a.qtr_rept, 4)                                        AS rept_yr_ft,
        a.REPORTED_DATE                                             AS ft_rept_date,
        a.Reserving                                                 AS covg,
        CASE a.Reserving
            WHEN 'ACH' THEN 'PD'
            WHEN 'ACL' THEN 'AircraftLiability'
            WHEN 'APL' THEN 'Airport Operations Occurrence'
        END                                                         AS coveragecode,
        -- Treat the literal string 'NULL' same as a true NULL
        CASE WHEN a.D55_CAT_CODE IN ('NULL', '') OR a.D55_CAT_CODE IS NULL
             THEN 0 ELSE 1
        END                                                         AS CAT_indicator,
        NULLIF(NULLIF(a.D55_CAT_CODE, 'NULL'), '')                 AS ISOCatNumber,
        a.clm_status1                                               AS clm_ft_status1,
        a.clm_status2                                               AS clm_ft_status2,
        a.clm_status3                                               AS clm_ft_status3,
        DATEPART(yy, a.date_close_act_kpi) * 100
            + DATEPART(mm, a.date_close_act_kpi)                   AS mth_ft_close_act,
        a.clm_status1                                               AS clm_occ_status1,
        a.clm_status2                                               AS clm_occ_status2,
        a.clm_status3                                               AS clm_occ_status3,
        DATEPART(yy, a.date_close_act_kpi) * 100
            + DATEPART(mm, a.date_close_act_kpi)                   AS mth_occ_close_act,
        a.date_close_act_kpi                                        AS date_close_act,
        DATEPART(yy, a.date_reopen_act_kpi) * 100
            + DATEPART(mm, a.date_reopen_act_kpi)                  AS mth_occ_reopen_act,
        a.date_reopen_act_kpi                                       AS date_reopen_act,
        (LEFT(a.mth_val,  4) * 1 - LEFT(a.mth_loss,  4) * 1) * 12
            + RIGHT(a.mth_val,  2) * 1 - RIGHT(a.mth_loss,  2)    AS mth_age,
        (LEFT(a.qtr_val,  4) * 1 - LEFT(a.qtr_loss,  4) * 1) * 4
            + RIGHT(a.qtr_val,  1) * 1 - RIGHT(a.qtr_loss,  1)    AS qtr_age,
        a.paid_loss                                                 AS paid_l,
        a.incd_loss                                                 AS incd_l,
        a.paid_ulae                                                 AS paid_nlgl,
        a.incd_ulae                                                 AS incd_nlgl,
        a.paid_alae                                                 AS paid_a,
        a.incd_alae                                                 AS incd_a,
        0                                                           AS subro,
        0                                                           AS salvage,
        (a.net_paid_loss - a.paid_loss)                            AS recovery,
        (a.paid_loss + a.paid_alae)                                AS paid_la,
        (a.paid_loss + a.paid_lae)                                 AS paid_llae,
        (a.incd_loss + a.incd_alae)                                AS incd_la,
        (a.incd_loss + a.incd_lae)                                 AS incd_llae,
        a.net_paid_loss                                             AS net_paid_l,
        a.net_incd_loss                                             AS net_incd_l,
        a.net_paid_la,
        (a.net_paid_loss + a.net_paid_lae)                        AS net_paid_llae,
        a.net_incd_la,
        (a.net_incd_loss + a.net_incd_lae)                        AS net_incd_llae,
        -- Icarus representation flag joined below
        CAST(NULL AS INT)                                           AS is_represented
    INTO #apollo
    FROM dbo.aim_loss_ulae AS a;

    -- Widen ISOCatNumber to accept existing values before the join update
    ALTER TABLE #apollo ALTER COLUMN ISOCatNumber VARCHAR(30);

    -- Add Icarus representation flag in a single pass
    UPDATE ap
    SET ap.is_represented =
        CASE WHEN ih.CLSId IN (2, 3, 13, 14) THEN 1 ELSE 0 END
    FROM #apollo AS ap
    LEFT JOIN [HSQ-DB01].[Icarus].[dbo].[Claim Hdr] AS ih
           ON ap.claimcontrol_id = ih.clmid
          AND ap.claim_number    = ih.[Claim No];

    -- Default any rows that had no Icarus match
    UPDATE #apollo SET is_represented = 0 WHERE is_represented IS NULL;

    -- -----------------------------------------------------------------------
    -- Stage Diamond loss data via dynamic SQL.
    -- A global temp table (##diamond_src) is used so the result is visible
    -- to this session after sp_executesql exits its own scope.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.##diamond_src') IS NOT NULL DROP TABLE ##diamond_src;

    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT * INTO ##diamond_src FROM ' + @tbl +
        N' WHERE reserving IN (''APL'',''ACL'',''ACH'');';
    EXEC sp_executesql @sql;

    IF OBJECT_ID('tempdb.dbo.#diamond') IS NOT NULL DROP TABLE #diamond;

    -- Normalise Diamond columns to the shared AIMLoss schema.
    -- NULL sentinel fixups (NULL → 999912 / '9999-12-31') handled inline.
    SELECT
        'Diamond'                                                   AS system,
        clm_ft_num,
        claim_number,
        claimcontrol_id,
        claimant_num,
        claimfeature_num,
        reserving,
        policy,
        policy_id,
        company,
        policyimage_num,
        vehicle_num                                                 AS aircraft_num,
        state_risk,
        yr_loss,
        qtr_loss,
        mth_loss,
        date_loss,
        date_occ_close_act                                         AS date_occ_close,
        date_ft_close_act                                          AS date_ft_close,
        mth_cal_earn,
        mth_val,
        qtr_val,
        yr_val,
        qtr_ind,
        yr_ind,
        rept_mth_occ,
        rept_qtr_occ,
        rept_yr_occ,
        occ_rept_date,
        ent_date                                                    AS occ_rept_date_act,
        rept_mth_ft,
        rept_qtr_ft,
        rept_yr_ft,
        ft_rept_date,
        covg,
        coveragecode,
        CAT_indicator,
        -- Treat literal string 'NULL' as true NULL
        NULLIF(NULLIF(ISOCatNumber, 'NULL'), '')                   AS ISOCatNumber,
        clm_ft_status1,
        clm_ft_status2,
        clm_ft_status3,
        -- Sentinel: closed rows with NULL close month default to far-future
        ISNULL(mth_ft_close_act, 999912)                          AS mth_ft_close_act,
        clm_occ_status1,
        clm_occ_status2,
        clm_occ_status3,
        ISNULL(mth_occ_close_act, 999912)                         AS mth_occ_close_act,
        ISNULL(date_occ_close_act, '9999-12-31')                  AS date_close_act,
        DATEPART(yy, date_occ_reopen_act) * 100
            + DATEPART(mm, date_occ_reopen_act)                   AS mth_occ_reopen_act,
        ISNULL(date_occ_reopen_act, '9999-12-31')                 AS date_reopen_act,
        mth_age,
        qtr_age,
        paid_l,
        incd_l,
        paid_nlgl,
        incd_nlgl,
        paid_a,
        incd_a,
        subro,
        salvage,
        recovery,
        paid_la,
        paid_llae,
        incd_la,
        incd_llae,
        net_paid_l,
        net_incd_l,
        net_paid_la,
        net_paid_llae,
        net_incd_la,
        net_incd_llae,
        is_represented
    INTO #diamond
    FROM ##diamond_src;

    DROP TABLE ##diamond_src;

    -- -----------------------------------------------------------------------
    -- Write combined Apollo + Diamond rows into test_AIMLoss.
    -- TRUNCATE preserves the table structure, identity seed, and metadata
    -- columns — avoids the DROP + SELECT INTO anti-pattern that would lose
    -- indexes and constraints.
    -- -----------------------------------------------------------------------
    TRUNCATE TABLE dbo.test_AIMLoss;

    INSERT INTO dbo.test_AIMLoss
    (
        system, clm_ft_num, claim_number, claimcontrol_id,
        claimant_num, claimfeature_num, reserving, policy, policy_id,
        company, policyimage_num, aircraft_num, state_risk,
        yr_loss, qtr_loss, mth_loss, date_loss,
        date_occ_close, date_ft_close, mth_cal_earn,
        mth_val, qtr_val, yr_val, qtr_ind, yr_ind,
        rept_mth_occ, rept_qtr_occ, rept_yr_occ,
        occ_rept_date, occ_rept_date_act,
        rept_mth_ft, rept_qtr_ft, rept_yr_ft, ft_rept_date,
        covg, coveragecode, CAT_indicator, ISOCatNumber,
        clm_ft_status1, clm_ft_status2, clm_ft_status3, mth_ft_close_act,
        clm_occ_status1, clm_occ_status2, clm_occ_status3, mth_occ_close_act,
        date_close_act, mth_occ_reopen_act, date_reopen_act,
        mth_age, qtr_age,
        paid_l, incd_l, paid_nlgl, incd_nlgl, paid_a, incd_a,
        subro, salvage, recovery,
        paid_la, paid_llae, incd_la, incd_llae,
        net_paid_l, net_incd_l, net_paid_la, net_paid_llae,
        net_incd_la, net_incd_llae,
        is_represented,
        row_hash, created_date, last_updated
    )
    SELECT
        system, clm_ft_num, claim_number, claimcontrol_id,
        claimant_num, claimfeature_num, reserving, policy, policy_id,
        company, policyimage_num, aircraft_num, state_risk,
        yr_loss, qtr_loss, mth_loss, date_loss,
        date_occ_close, date_ft_close, mth_cal_earn,
        mth_val, qtr_val, yr_val, qtr_ind, yr_ind,
        rept_mth_occ, rept_qtr_occ, rept_yr_occ,
        occ_rept_date, occ_rept_date_act,
        rept_mth_ft, rept_qtr_ft, rept_yr_ft, ft_rept_date,
        covg, coveragecode, CAT_indicator, ISOCatNumber,
        clm_ft_status1, clm_ft_status2, clm_ft_status3, mth_ft_close_act,
        clm_occ_status1, clm_occ_status2, clm_occ_status3, mth_occ_close_act,
        date_close_act, mth_occ_reopen_act, date_reopen_act,
        mth_age, qtr_age,
        paid_l, incd_l, paid_nlgl, incd_nlgl, paid_a, incd_a,
        subro, salvage, recovery,
        paid_la, paid_llae, incd_la, incd_llae,
        net_paid_l, net_incd_l, net_paid_la, net_paid_llae,
        net_incd_la, net_incd_llae,
        is_represented,
        CONVERT(BINARY(32), HASHBYTES('SHA2_256',
            ISNULL(CAST(paid_l    AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(incd_l    AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(paid_nlgl AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(incd_nlgl AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(paid_a    AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(incd_a    AS NVARCHAR(30)), '')
        ))                                                          AS row_hash,
        GETDATE()                                                   AS created_date,
        GETDATE()                                                   AS last_updated
    FROM #apollo
    UNION ALL
    SELECT
        system, clm_ft_num, claim_number, claimcontrol_id,
        claimant_num, claimfeature_num, reserving, policy, policy_id,
        company, policyimage_num, aircraft_num, state_risk,
        yr_loss, qtr_loss, mth_loss, date_loss,
        date_occ_close, date_ft_close, mth_cal_earn,
        mth_val, qtr_val, yr_val, qtr_ind, yr_ind,
        rept_mth_occ, rept_qtr_occ, rept_yr_occ,
        occ_rept_date, occ_rept_date_act,
        rept_mth_ft, rept_qtr_ft, rept_yr_ft, ft_rept_date,
        covg, coveragecode, CAT_indicator, ISOCatNumber,
        clm_ft_status1, clm_ft_status2, clm_ft_status3, mth_ft_close_act,
        clm_occ_status1, clm_occ_status2, clm_occ_status3, mth_occ_close_act,
        date_close_act, mth_occ_reopen_act, date_reopen_act,
        mth_age, qtr_age,
        paid_l, incd_l, paid_nlgl, incd_nlgl, paid_a, incd_a,
        subro, salvage, recovery,
        paid_la, paid_llae, incd_la, incd_llae,
        net_paid_l, net_incd_l, net_paid_la, net_paid_llae,
        net_incd_la, net_incd_llae,
        is_represented,
        CONVERT(BINARY(32), HASHBYTES('SHA2_256',
            ISNULL(CAST(paid_l    AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(incd_l    AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(paid_nlgl AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(incd_nlgl AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(paid_a    AS NVARCHAR(30)), '') + '|' +
            ISNULL(CAST(incd_a    AS NVARCHAR(30)), '')
        ))                                                          AS row_hash,
        GETDATE()                                                   AS created_date,
        GETDATE()                                                   AS last_updated
    FROM #diamond;

    DROP TABLE #apollo, #diamond;

    DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID);
    EXEC UPDATE_QUERY_TIMES @PROC_NAME, @startTime;

END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb.dbo.##diamond_src') IS NOT NULL DROP TABLE ##diamond_src;
    SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE;
END CATCH
GO
