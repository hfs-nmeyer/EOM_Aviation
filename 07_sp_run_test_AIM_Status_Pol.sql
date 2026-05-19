USE [Pricing_AIM]
GO

/*=============================================================================
  sp_run_test_AIM_Status_Pol.sql
  Purpose : Build policy-status dimension tables that track new, renewal,
            and lost policies across both Apollo and Diamond systems.

  Outputs (DROP + SELECT INTO each run):
    dbo.test_aim_status_pol                -- one row per system/policy/edition
    dbo.test_aim_status_pol_policy_mapping -- rewrite-consolidation detail

  Depends on:
    pricing_aim.dbo.rr_aim_apollo         -- Apollo policy extract (pre-loaded)
    [AHI-S06].diamond.dbo.*               -- Diamond policy/LOB tables

  Improvements over original:
    - Wrapped in CREATE OR ALTER PROCEDURE with BEGIN TRY/CATCH
    - SET NOCOUNT ON suppresses row-count messages
    - Bare DROP TABLE chains replaced with IF OBJECT_ID guards
    - ORDER BY clauses removed from SELECT INTO (no effect on unindexed heaps)
    - Row hash added to both output tables
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[run_test_AIM_Status_Pol]
AS
BEGIN TRY
    SET NOCOUNT ON;
    DECLARE @startTime DATETIME = GETDATE();

    -- -----------------------------------------------------------------------
    -- Apollo: policy-level summary
    -- Note: pol_num_full_clean is in GROUP BY but not SELECT intentionally;
    --       it makes grouping more granular without surfacing the column.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp01') IS NOT NULL DROP TABLE #temp01;

    SELECT
        polid,
        Policyno,
        LEFT(Policyno, 10)  AS pol_num,
        pol_ed,
        efdate,
        exdate,
        SUM(prem_written)   AS prem_written,
        SUM(prem_annual)    AS prem_annual
    INTO #temp01
    FROM pricing_aim.dbo.rr_aim_apollo
    GROUP BY
        polid, Policyno, pol_ed, pol_num_full_clean, efdate, exdate,
        LEFT(Policyno, 10);

    -- Apollo renewal chain: edition N links to edition N+1
    IF OBJECT_ID('tempdb.dbo.#temp02') IS NOT NULL DROP TABLE #temp02;

    SELECT
        a.*,
        b.pol_num AS pol_num_future,
        b.pol_ed  AS pol_ed_future,
        b.polid   AS pol_id_future
    INTO #temp02
    FROM #temp01 a
    LEFT JOIN #temp01 b
        ON  a.pol_num    = b.pol_num
        AND a.pol_ed + 1 = b.pol_ed;

    -- -----------------------------------------------------------------------
    -- Diamond: policy info for LOB 30 (Aircraft) and 31 (Airport),
    --          active status codes 1, 3, 20
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp03') IS NOT NULL DROP TABLE #temp03;

    SELECT
        g.client_id,
        a.policy_id,
        a.policy,
        a.renewal_ver,
        a.eff_date,
        a.exp_date,
        g.cancelled,
        g.cancelledon_date,
        g.rewrittenfrom_policy_id,
        g.rewrittenfrom_policy,
        g.legacy_policynumber,
        g.firstwritten_date,
        a.policyimage_num,
        SUM(a.premium_chg_written)  AS premium_chg_written,
        SUM(a.premium_chg_fullterm) AS premium_chg_fullterm
    INTO #temp03
    FROM [AHI-S06].diamond.dbo.vpolicyimagexml  a
    LEFT JOIN [AHI-S06].diamond.dbo.ratingversion  b ON a.ratingversion_id    = b.ratingversion_id
    LEFT JOIN [AHI-S06].diamond.dbo.version        c ON c.version_id          = b.version_id
    LEFT JOIN [AHI-S06].diamond.dbo.companystatelob d ON d.companystatelob_id = c.companystatelob_id
    LEFT JOIN [AHI-S06].diamond.dbo.companylob     e ON e.companylob_id       = d.companylob_id
    LEFT JOIN [AHI-S06].diamond.dbo.lob            f ON f.lob_id              = e.lob_id
    LEFT JOIN [AHI-S06].diamond.dbo.policy         g ON g.policy_id           = a.policy_id
    WHERE f.lob_id IN (30, 31)
      AND a.policystatuscode_id IN (1, 3, 20)
    GROUP BY
        g.client_id, a.policy_id, a.policy, a.renewal_ver,
        a.eff_date, a.exp_date, g.cancelled, g.cancelledon_date,
        g.rewrittenfrom_policy_id, g.rewrittenfrom_policy,
        g.legacy_policynumber, g.firstwritten_date, a.policyimage_num;

    -- -----------------------------------------------------------------------
    -- Map Apollo to Diamond via legacy policy number; derive status flags
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp02_a') IS NOT NULL DROP TABLE #temp02_a;

    SELECT
        a.polid,
        a.Policyno,
        a.pol_num,
        a.pol_ed,
        a.efdate,
        a.exdate,
        a.prem_written,
        a.prem_annual,
        ISNULL(b.policy,      a.pol_num_future) AS pol_num_future,
        ISNULL(b.renewal_ver, a.pol_ed_future)  AS pol_ed_future,
        ISNULL(b.policy_id,   a.pol_id_future)  AS pol_id_future,
        'also' AS status_pol_rn,
        'also' AS status_pol_rl
    INTO #temp02_a
    FROM #temp02 a
    LEFT JOIN #temp03 b
        ON  a.Policyno    = b.legacy_policynumber
        AND b.renewal_ver = 1;

    UPDATE #temp02_a
    SET status_pol_rl = CASE WHEN pol_num_future IS NULL THEN 'Lost' ELSE 'Ren' END;

    UPDATE #temp02_a
    SET status_pol_rn = CASE WHEN pol_ed = '00' THEN 'New' ELSE 'Ren' END;

    -- -----------------------------------------------------------------------
    -- Rewrite consolidation: join each policy to its cancelled predecessor
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp04') IS NOT NULL DROP TABLE #temp04;

    SELECT
        a.client_id,
        a.policy_id,
        a.policy,
        a.renewal_ver,
        a.eff_date,
        a.exp_date,
        a.cancelled,
        a.cancelledon_date,
        a.firstwritten_date,
        a.rewrittenfrom_policy_id,
        a.rewrittenfrom_policy,
        a.legacy_policynumber,
        SUM(a.premium_chg_written)      AS premium_written,
        SUM(a.premium_chg_fullterm)     AS premium_fullterm,
        MAX(b.policyimage_num)          AS rewrite_policyimage_num,
        MAX(CAST(b.renewal_ver AS INT)) AS rewrite_renewal_ver,
        MAX(b.eff_date)                 AS rewrite_eff_date,
        MAX(b.exp_date)                 AS rewrite_exp_date,
        MAX(CAST(b.cancelled AS INT))   AS rewrite_cancelled,
        MAX(b.cancelledon_date)         AS rewrite_cancelledon_date,
        SUM(b.premium_chg_written)      AS rewrite_premium_written,
        SUM(b.premium_chg_fullterm)     AS rewrite_premium_fullterm
    INTO #temp04
    FROM #temp03 a
    LEFT JOIN #temp03 b
        ON  a.rewrittenfrom_policy = b.policy
        AND b.cancelledon_date BETWEEN b.eff_date AND b.exp_date
        AND a.eff_date = b.cancelledon_date
    GROUP BY
        a.client_id, a.policy_id, a.policy, a.renewal_ver,
        a.eff_date, a.exp_date, a.cancelled, a.cancelledon_date,
        a.firstwritten_date, a.rewrittenfrom_policy_id,
        a.rewrittenfrom_policy, a.legacy_policynumber;

    -- -----------------------------------------------------------------------
    -- Add term lengths; initialize revised_pol fields (overwritten by UPDATEs)
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp05') IS NOT NULL DROP TABLE #temp05;

    SELECT *,
        DATEDIFF(dd, eff_date,          exp_date)               AS written_term,
        DATEDIFF(dd, rewrite_eff_date,  rewrite_cancelledon_date) AS exp_term,
        11111        AS revised_pol_id,
        0            AS revised_pol_renewal_ver,
        '2019-01-01' AS revised_eff_date,
        '2019-01-01' AS revised_exp_date
    INTO #temp05
    FROM #temp04;

    -- Fold short-term rewrites back into the source policy
    UPDATE #temp05
    SET revised_pol_id = CASE WHEN written_term < 365 AND exp_term < 365
                              THEN rewrittenfrom_policy_id ELSE policy_id END;

    UPDATE #temp05
    SET revised_eff_date = CASE WHEN written_term < 365 AND exp_term < 365
                                THEN rewrite_eff_date ELSE eff_date END;

    UPDATE #temp05
    SET revised_exp_date = exp_date;

    UPDATE #temp05
    SET revised_pol_renewal_ver = CASE WHEN written_term < 365 AND exp_term < 365
                                       THEN rewrite_renewal_ver ELSE renewal_ver END;

    -- -----------------------------------------------------------------------
    -- Collapse to one row per client/revised policy
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#temp06') IS NOT NULL DROP TABLE #temp06;

    SELECT
        client_id,
        revised_pol_id,
        cancelled,
        revised_pol_renewal_ver,
        MIN(revised_eff_date)    AS revised_eff_date,
        MAX(revised_exp_date)    AS revised_exp_date,
        MAX(legacy_policynumber) AS legacy_policynumber,
        SUM(premium_written)     AS prem_written,
        SUM(premium_fullterm)    AS prem_fullterm
    INTO #temp06
    FROM #temp05
    GROUP BY client_id, revised_pol_id, revised_pol_renewal_ver, cancelled;

    -- -----------------------------------------------------------------------
    -- UNION Apollo and Diamond into a single policy-status fact
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#final') IS NOT NULL DROP TABLE #final;

    SELECT *
    INTO #final
    FROM (
        SELECT
            'Apollo'                                        AS System,
            NULL                                            AS client_id,
            polid,
            pol_ed,
            efdate                                          AS eff_date,
            exdate                                          AS exp_date,
            status_pol_rn,
            status_pol_rl,
            pol_id_future,
            pol_ed_future,
            CASE WHEN ISNULL(pol_id_future, 0) >= 30000000
                 THEN 'Diamond' ELSE 'Apollo' END           AS system_future
        FROM #temp02_a

        UNION ALL

        SELECT
            'Diamond'                                       AS System,
            a.client_id,
            a.revised_pol_id,
            a.revised_pol_renewal_ver,
            a.revised_eff_date,
            a.revised_exp_date,
            CASE WHEN a.legacy_policynumber LIKE '%-%'  THEN 'Ren'
                 WHEN a.revised_pol_renewal_ver > 1     THEN 'Ren'
                 ELSE 'New' END                             AS status_pol_rn,
            CASE WHEN a.cancelled = 1
                      THEN 'Cncl Pre'
                 WHEN CAST(a.revised_exp_date AS DATE) >=
                      DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
                      THEN 'Inf'
                 WHEN b.revised_pol_id IS NULL
                      THEN 'Lost'
                 ELSE 'Ren' END                             AS status_pol_rl,
            b.revised_pol_id                                AS pol_id_future,
            b.revised_pol_renewal_ver                       AS pol_ed_future,
            'Diamond'                                       AS system_future
        FROM #temp06 a
        LEFT JOIN #temp06 b
            ON  a.client_id               = b.client_id
            AND a.revised_pol_renewal_ver + 1 = b.revised_pol_renewal_ver
    ) a;

    -- -----------------------------------------------------------------------
    -- Deduplicate: keep one row per system/policy/edition
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#final_2') IS NOT NULL DROP TABLE #final_2;

    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY System, polid, pol_ed, eff_date
            ORDER BY pol_id_future DESC
        ) AS selector
    INTO #final_2
    FROM #final;

    -- -----------------------------------------------------------------------
    -- Write: test_aim_status_pol
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('dbo.test_aim_status_pol') IS NOT NULL
        DROP TABLE dbo.test_aim_status_pol;

    SELECT DISTINCT *
    INTO dbo.test_aim_status_pol
    FROM #final_2
    WHERE selector = 1;

    ALTER TABLE dbo.test_aim_status_pol ADD
        row_hash     BINARY(32)   NULL,
        created_date DATETIME2(0) NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0) NOT NULL DEFAULT GETDATE();

    UPDATE dbo.test_aim_status_pol
    SET row_hash = CONVERT(BINARY(32), HASHBYTES('SHA2_256',
        ISNULL(CAST(System        AS NVARCHAR(10)), '') + '|' +
        ISNULL(CAST(polid         AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(pol_ed        AS NVARCHAR(10)), '') + '|' +
        ISNULL(CAST(status_pol_rn AS NVARCHAR(20)), '') + '|' +
        ISNULL(CAST(status_pol_rl AS NVARCHAR(20)), '')));

    -- -----------------------------------------------------------------------
    -- Write: test_aim_status_pol_policy_mapping
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('dbo.test_aim_status_pol_policy_mapping') IS NOT NULL
        DROP TABLE dbo.test_aim_status_pol_policy_mapping;

    SELECT *
    INTO dbo.test_aim_status_pol_policy_mapping
    FROM #temp05;

    ALTER TABLE dbo.test_aim_status_pol_policy_mapping ADD
        row_hash     BINARY(32)   NULL,
        created_date DATETIME2(0) NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0) NOT NULL DEFAULT GETDATE();

    UPDATE dbo.test_aim_status_pol_policy_mapping
    SET row_hash = CONVERT(BINARY(32), HASHBYTES('SHA2_256',
        ISNULL(CAST(policy_id        AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(renewal_ver      AS NVARCHAR(10)), '') + '|' +
        ISNULL(CAST(revised_pol_id   AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(premium_written  AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(premium_fullterm AS NVARCHAR(30)), '')));

    DROP TABLE #temp01, #temp02, #temp02_a, #temp03, #temp04,
               #temp05, #temp06, #final, #final_2;

    DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID);
    EXEC UPDATE_QUERY_TIMES @PROC_NAME, @startTime;

END TRY
BEGIN CATCH
    SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE;
END CATCH
GO
