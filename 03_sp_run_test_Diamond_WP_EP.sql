USE [Pricing_AIM]
GO

/*=============================================================================
  sp_run_test_Diamond_WP_EP.sql
  Purpose : Extract written/earned premium from Diamond for the prior month
            and MERGE it into test_DiamondEarnedPremium_Aviation_JChenVScopy.

  Improvements over original:
    - Uses a single CTE (cte_coverage_groups) to define coverage mappings
      instead of an inline CASE expression buried in the SELECT.
    - Staging temp table #staged collects results from Diamond before any
      write to Pricing_AIM, minimising cross-server latch time.
    - MERGE replaces INSERT so rows added for a month that was already loaded
      (e.g. a rerun) update in place rather than duplicating.
    - All ad-hoc check SELECTs removed; verification is handled separately
      by 05_validation.sql.
    - Row hash computed over financial columns to drive the MERGE update.
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[run_test_Diamond_WP_EP]
AS
BEGIN TRY
    SET NOCOUNT ON;
    DECLARE @startTime DATETIME = GETDATE();

    -- -----------------------------------------------------------------------
    -- Derive prior-month period variables
    -- -----------------------------------------------------------------------
    DECLARE @Year  INT = DATEPART(YEAR,  DATEADD(MONTH, -1, GETDATE()));
    DECLARE @Month INT = DATEPART(MONTH, DATEADD(MONTH, -1, GETDATE()));

    -- -----------------------------------------------------------------------
    -- Stage: pull data from Diamond into a local temp table.
    --        All cross-server I/O finishes before touching Pricing_AIM,
    --        which reduces network contention on the merge step.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#staged') IS NOT NULL DROP TABLE #staged;

    ;WITH cte_coverage_groups AS
    (
        -- Map Diamond coverage code IDs to the three business coverage groups.
        -- Maintaining this as a CTE makes the mapping easy to audit/extend.
        SELECT coveragecode_id,
               coverage_group = CASE
                   WHEN coveragecode_id IN (90006,90009,90048,90053,90056,90059,
                                            90060,90062,90069,90076,90077,90124,
                                            90151,90154,90157,90158,90038)
                       THEN 'Aircraft Hull'
                   WHEN coveragecode_id IN (90041,90045,90064,90065,90066,90103,
                                            90104,90156,90165,90166,90164,90020)
                       THEN 'Aircraft Liability'
                   WHEN coveragecode_id IN (90039,90161,90167,90168,90170,90171,
                                            90172,90173,90174,90175,90176,90177,
                                            90179,90180,90183,90184,90185,90186,
                                            90187,90188,90189,90190,90191,90192,
                                            90195,90196,21134)
                       THEN 'Airport Liability'
                   ELSE NULL
               END
        FROM (VALUES
            (90006),(90009),(90038),(90039),(90041),(90045),(90048),(90053),
            (90056),(90059),(90060),(90062),(90064),(90065),(90066),(90069),
            (90076),(90077),(90103),(90104),(90124),(90151),(90154),(90156),
            (90157),(90158),(90161),(90164),(90165),(90166),(90167),(90168),
            (90170),(90171),(90172),(90173),(90174),(90175),(90176),(90177),
            (90179),(90180),(90183),(90184),(90185),(90186),(90187),(90188),
            (90189),(90190),(90191),(90192),(90195),(90196),(90020),(21134)
        ) AS v(coveragecode_id)
    )
    SELECT
        'Diamond'                                               AS Platform,
        @Year                                                   AS [Year],
        @Month                                                  AS AcctPer,
        CASE
            WHEN @Month IN (1,2,3)   THEN 1
            WHEN @Month IN (4,5,6)   THEN 2
            WHEN @Month IN (7,8,9)   THEN 3
            WHEN @Month IN (10,11,12) THEN 4
        END                                                     AS AcctQtr,
        cg.coverage_group                                       AS CoverageCodeGrouped,
        cc.coveragecode,
        cc.dscr                                                 AS ccdscr,
        cc.coveragetype,
        s.[state]                                               AS [State],
        cn.display_name                                         AS Carrier,
        p.policy_id,
        EOPM.policy,
        EOPM.policyimage_num,
        EOPM.unit_num,
        CASE WHEN EOPM.renewal_ver = 1 THEN 'New' ELSE 'Renew' END AS NewRenew,
        lob.lobname                                             AS PolicyTypeGroupDesc,
        lob.lobname                                             AS CoverageGroupDetailDesc1,
        lob.lobname                                             AS PolicyType,
        ROUND(SUM(ISNULL(EOPM.premium_written_mtd, 0)), 2)     AS premium_written_mtd,
        ROUND(SUM(ISNULL(EOPM.premium_earned_mtd, 0)), 2)      AS premium_earned_mtd,
        ROUND(SUM(ISNULL(EOPM.premium_unearned, 0)), 2)        AS premium_unearned,
        ROUND(SUM(ISNULL(EOPM.premium_unearned_priormonth,0)),2) AS premium_unearned_priormonth,
        ROUND(SUM(ISNULL(EOPM.premium_written_ytd, 0)), 2)     AS premium_written,
        ROUND(SUM(ISNULL(EOPM.premium_unearned, 0)), 2)
            - ROUND(SUM(ISNULL(EOPM.premium_unearned_priormonth, 0)), 2)
                                                                AS UepPriorMinusCurent,
        EOPM.eff_date                                           AS EffectiveDate,
        EOPM.exp_date                                           AS ExpirationDate,
        maj.majorperil,
        pt.months,
        pi.ratingversion_id,
        -- Pre-compute the row hash over financial columns for MERGE comparison
        CONVERT(BINARY(32), HASHBYTES('SHA2_256',
            CONCAT_WS('|',
                CAST(ROUND(SUM(ISNULL(EOPM.premium_written_mtd,0)),2) AS NVARCHAR(30)),
                CAST(ROUND(SUM(ISNULL(EOPM.premium_earned_mtd,0)),2)  AS NVARCHAR(30)),
                CAST(ROUND(SUM(ISNULL(EOPM.premium_unearned,0)),2)    AS NVARCHAR(30)),
                CAST(ROUND(SUM(ISNULL(EOPM.premium_written_ytd,0)),2) AS NVARCHAR(30))
            )
        ))                                                      AS row_hash
    INTO #staged
    FROM [AHI-S06].Diamond.dbo.EOPMonthlyPremiums      EOPM WITH (NOLOCK)
    INNER JOIN [AHI-S06].Diamond.dbo.[Version]          V    WITH (NOLOCK)
           ON EOPM.version_id         = V.version_id
    INNER JOIN [AHI-S06].Diamond.dbo.Policy             p
           ON EOPM.policy_id          = p.policy_id
    LEFT  JOIN [AHI-S06].Diamond.dbo.policyimage        pi
           ON pi.policy_id            = p.policy_id
          AND pi.policyimage_num      = EOPM.policyimage_num
    INNER JOIN [AHI-S06].Diamond.dbo.CompanyStateLOB   CSL  WITH (NOLOCK)
           ON CSL.companystatelob_id  = V.companystatelob_id
    INNER JOIN [AHI-S06].Diamond.dbo.CompanyState       CS   WITH (NOLOCK)
           ON CS.companystate_id      = CSL.companystate_id
    INNER JOIN [AHI-S06].Diamond.dbo.[State]             S    WITH (NOLOCK)
           ON S.state_id              = CS.state_id
    INNER JOIN [AHI-S06].Diamond.dbo.CompanyLOB         CL   WITH (NOLOCK)
           ON CL.companylob_id        = CSL.companylob_id
    INNER JOIN [AHI-S06].Diamond.dbo.Lob                LOB  WITH (NOLOCK)
           ON CL.lob_id               = LOB.lob_id
    INNER JOIN [AHI-S06].Diamond.dbo.CompanyNameLink    CNL  WITH (NOLOCK)
           ON CNL.company_id          = CS.company_id
          AND CNL.company_id          = CL.company_id
    INNER JOIN [AHI-S06].Diamond.dbo.[Name]             CN   WITH (NOLOCK)
           ON CN.name_id              = CNL.name_id
    INNER JOIN [AHI-S06].Diamond.dbo.CoverageCode       cc
           ON EOPM.coveragecode_id    = cc.coveragecode_id
    INNER JOIN [AHI-S06].Diamond.dbo.ASL                asl
           ON EOPM.asl_id             = asl.asl_id
    INNER JOIN [AHI-S06].Diamond.dbo.MajorPeril         maj
           ON EOPM.majorperil_id      = maj.majorperil_id
    LEFT  JOIN [AHI-S06].Diamond.dbo.vBillingAccountData VBA
           ON EOPM.policy_id          = VBA.policy_id
    LEFT  JOIN [AHI-S06].Diamond.dbo.BillingAcctReceivable BAC
           ON EOPM.policy_id          = BAC.policy_id
          AND BAC.renewal_ver         = 2
    LEFT  JOIN [AHI-S06].Diamond.dbo.vAgencyCommission_Info vac
           ON vac.companystatelob_id  = CSL.companystatelob_id
          AND vac.agency_id           = VBA.agency_id
          AND pi.eff_date BETWEEN vac.start_date
              AND CASE WHEN vac.end_date = '1800-01-01' THEN '2100-12-31' ELSE vac.end_date END
          AND CASE WHEN EOPM.renewal_ver = 1 THEN 'New Business' ELSE 'Renewal' END = vac.description_detailtype
    LEFT  JOIN [AHI-S06].Diamond.dbo.PolicyTerm         pt
           ON pt.policyterm_id        = pi.policyterm_id
    -- Join to coverage-group CTE to avoid repeating CASE logic in GROUP BY
    LEFT  JOIN cte_coverage_groups cg
           ON cc.coveragecode_id      = cg.coveragecode_id
    WHERE  EOPM.month  = @Month
      AND  EOPM.year   = @Year
      AND  EOPM.lob_id IN (30, 31)   -- Aircraft (30) and Airport (31) only
    GROUP BY
        EOPM.policy, EOPM.majorperil_id, EOPM.asl_id,
        V.company_id, V.state_id, V.lob_id,
        s.[state], cn.display_name, p.policy_id, EOPM.policyimage_num,
        EOPM.unit_num, EOPM.renewal_ver, lob.lobname,
        cc.coveragecode_id, cc.coveragecode, cc.dscr, cc.coveragetype,
        asl.asl, vac.rate, EOPM.eff_date, EOPM.exp_date,
        maj.description, vba.billingpayplan_dscr, vba.billingpayplan_id,
        bac.totalcash, maj.majorperil, pt.months, pi.ratingversion_id,
        cg.coverage_group;

    -- -----------------------------------------------------------------------
    -- MERGE staged data into the test table.
    --   Natural key: policy_id + policyimage_num + unit_num + coveragecode + Year + AcctPer
    --   INSERT new rows; UPDATE rows whose financial hash has changed.
    -- -----------------------------------------------------------------------
    MERGE dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy AS tgt
    USING (
        SELECT
            Platform, [Year], AcctPer, AcctQtr, CoverageCodeGrouped,
            coveragecode, ccdscr, coveragetype, [State], Carrier,
            policy_id, policy, policyimage_num, unit_num, NewRenew,
            PolicyTypeGroupDesc, CoverageGroupDetailDesc1, PolicyType,
            premium_written_mtd, premium_earned_mtd, premium_unearned,
            premium_unearned_priormonth, premium_written, UepPriorMinusCurent,
            EffectiveDate, ExpirationDate, majorperil, months, ratingversion_id,
            row_hash
        FROM #staged
    ) AS src
    ON  tgt.policy_id       = src.policy_id
    AND tgt.policyimage_num = src.policyimage_num
    AND tgt.unit_num        = src.unit_num
    AND tgt.coveragecode    = src.coveragecode
    AND tgt.[Year]          = src.[Year]
    AND tgt.AcctPer         = src.AcctPer

    WHEN MATCHED AND tgt.row_hash <> src.row_hash THEN
        UPDATE SET
            tgt.premium_written_mtd         = src.premium_written_mtd,
            tgt.premium_earned_mtd          = src.premium_earned_mtd,
            tgt.premium_unearned            = src.premium_unearned,
            tgt.premium_unearned_priormonth = src.premium_unearned_priormonth,
            tgt.premium_written             = src.premium_written,
            tgt.UepPriorMinusCurent         = src.UepPriorMinusCurent,
            tgt.CoverageCodeGrouped         = src.CoverageCodeGrouped,
            tgt.AcctQtr                     = src.AcctQtr,
            tgt.row_hash                    = src.row_hash,
            tgt.last_updated                = GETDATE()

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Platform,[Year],AcctPer,AcctQtr,CoverageCodeGrouped,
                coveragecode,ccdscr,coveragetype,[State],Carrier,
                policy_id,policy,policyimage_num,unit_num,NewRenew,
                PolicyTypeGroupDesc,CoverageGroupDetailDesc1,PolicyType,
                premium_written_mtd,premium_earned_mtd,premium_unearned,
                premium_unearned_priormonth,premium_written,UepPriorMinusCurent,
                EffectiveDate,ExpirationDate,majorperil,months,ratingversion_id,
                row_hash,created_date,last_updated)
        VALUES (src.Platform,src.[Year],src.AcctPer,src.AcctQtr,
                src.CoverageCodeGrouped,src.coveragecode,src.ccdscr,
                src.coveragetype,src.[State],src.Carrier,src.policy_id,
                src.policy,src.policyimage_num,src.unit_num,src.NewRenew,
                src.PolicyTypeGroupDesc,src.CoverageGroupDetailDesc1,src.PolicyType,
                src.premium_written_mtd,src.premium_earned_mtd,src.premium_unearned,
                src.premium_unearned_priormonth,src.premium_written,
                src.UepPriorMinusCurent,src.EffectiveDate,src.ExpirationDate,
                src.majorperil,src.months,src.ratingversion_id,
                src.row_hash,GETDATE(),GETDATE());

    DROP TABLE #staged;

    DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID);
    EXEC UPDATE_QUERY_TIMES @PROC_NAME, @startTime;

END TRY
BEGIN CATCH
    SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE;
END CATCH
GO
