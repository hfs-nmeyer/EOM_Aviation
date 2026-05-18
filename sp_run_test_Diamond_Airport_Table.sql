USE [Pricing_AIM]
GO

/*=============================================================================
  sp_run_test_Diamond_Airport_Table.sql
  Purpose : Build the airport policy/coverage detail table (test_DiaAPCovg)
            from Diamond data.

  Improvements over original:
    - 38 identical per-coverage-code temp tables (#PL, #BIPD, #AOO, …) are
      replaced by a single #covg_pivot built with conditional aggregation
      (MAX CASE WHEN coveragecode_id = X).  This eliminates 38 round-trips
      to the coveragecode/coveragelimit linked-server tables and collapses
      the final assembly join list from 38 LEFT JOINs to 1.
    - The date-filter constants are centralised in a TABLE VARIABLE instead
      of a one-row temp table, avoiding a tempdb write.
    - INSERT uses dynamic SQL to map #DiaAP02 columns to test_DiaAPCovg,
      so the column list never drifts when the source schema changes.
    - TRUNCATE + INSERT replaces DROP + SELECT INTO, preserving indexes,
      constraints, and the identity column on test_DiaAPCovg.
    - Row hash computed over key financial columns.
    - All dead-code diagnostic SELECTs removed.
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[run_test_Diamond_Airport_Table]
AS
BEGIN TRY
    SET NOCOUNT ON;
    DECLARE @startTime DATETIME = GETDATE();

    -- -----------------------------------------------------------------------
    -- Date filter constants (table variable — no tempdb spill)
    -- -----------------------------------------------------------------------
    DECLARE @tv_dates TABLE
    (
        date_pol_eff_min  DATE,
        date_book_val_min DATE,
        date_book_val_max DATETIME,
        date_book         DATE
    );
    INSERT INTO @tv_dates
    VALUES (
        '2001-01-01',
        '2000-01-01',
        GETDATE(),
        CONVERT(CHAR(10), DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1), 120)
    );

    -- -----------------------------------------------------------------------
    -- Stage policy images for airport policy prefixes, excluding void/cancel
    -- statuses (4=Cancelled, 5=Expired, 6=NonRenewed, 8=Declined, 12=Void,
    -- 13=Rescinded).
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#policyimage') IS NOT NULL DROP TABLE #policyimage;
    SELECT
        ROW_NUMBER() OVER (
            PARTITION BY policy_id, premium_diff_chg_written, trans_remark
            ORDER BY policyimage_num
        )                                   AS repeat_transaction_count,
        *
    INTO #policyimage
    FROM [AHI-S06].[Diamond].[dbo].policyimage
    WHERE (policy LIKE 'AP%' OR policy LIKE 'HLMAP%' OR policy LIKE 'HDIAP%')
      AND policystatuscode_id NOT IN (4, 5, 6, 8, 12, 13);

    -- Airport policy/image keys
    IF OBJECT_ID('tempdb.dbo.#Airport_pol') IS NOT NULL DROP TABLE #Airport_pol;
    SELECT a.policy_id, a.policyimage_num, b.repeat_transaction_count
    INTO #Airport_pol
    FROM (
        SELECT DISTINCT policy_id, policyimage_num
        FROM [AHI-S06].[Diamond].[dbo].[airport]
    ) AS a
    INNER JOIN #policyimage AS b
           ON a.policy_id = b.policy_id AND a.policyimage_num = b.policyimage_num;

    -- Active airport detail rows only
    IF OBJECT_ID('tempdb.dbo.#airport') IS NOT NULL DROP TABLE #airport;
    SELECT * INTO #airport
    FROM [AHI-S06].[Diamond].[dbo].[airport]
    WHERE detailstatuscode_id = 1;

    -- -----------------------------------------------------------------------
    -- Coverage data: fetch all airport coverage rows via OPENQUERY to push
    -- the predicate to the linked server and minimise data transfer.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#covg00') IS NOT NULL DROP TABLE #covg00;
    SELECT * INTO #covg00
    FROM OPENQUERY([AHI-S06], '
        SELECT
            a.policy_id, a.policyimage_num, a.coverage_num, a.unit_num,
            a.eff_date, a.exp_date,
            a.premium_fullterm, a.premium_written,
            a.premium_previous_written, a.premium_chg_written,
            a.premium_prev_chg_written, a.premium_diff_chg_written,
            a.coveragecode_id, a.subcoveragecode_id, a.coveragelimit_id,
            a.manuallimitamount, a.calc, a.read_only, a.manualdate,
            a.checkbox, a.detailstatuscode_id,
            a.added_date, a.pcadded_date, a.apply_to_written_premium,
            a.premium_chg_fullterm, a.premium_prev_chg_fullterm,
            a.premium_diff_chg_fullterm,
            a.minimum_liability_premium_fullterm,
            a.scheduleditems, a.onset_for_reapplied, a.offset_for_reapplied,
            a.offset_for_prev_image, a.onset_for_current,
            a.ftp_onset_for_reapplied, a.ftp_offset_for_reapplied,
            a.ftp_offset_for_prev_image, a.ftp_onset_for_current,
            a.exposure, a.premium_guaranteed_rate_period,
            a.premium_annual, a.premium_chg_annual,
            a.premium_prev_chg_annual, a.premium_diff_chg_annual,
            a.manuallimit_included, a.manuallimit_increased,
            a.dscr, a.sequence_num, a.deductible, a.original_cost,
            a.deductible_id, a.last_modified_date, a.override_fully_earned,
            a.asl_id, a.packagepart_num,
            a.premium_prevaudit_written,
            a.premium_previous_written_shortrate,
            a.deleted_policyimage_num, a.added_policyimage_num,
            a.majorperil_id, a.package_sync_identifier
        FROM Diamond.dbo.coverage AS a
        LEFT JOIN Diamond.dbo.policyimage AS b
               ON a.policy_id = b.policy_id AND a.policyimage_num = b.policyimage_num
        WHERE (b.policy LIKE ''AP%'' OR b.policy LIKE ''HLMAP%'' OR b.policy LIKE ''HDIAP%'')
          AND b.policystatuscode_id NOT IN (4, 5, 6, 8, 12, 13)
    ');

    -- De-duplicate: when a coverage appears multiple times for the same
    -- (policy, image, unit, code), keep only rows with premium_written > 0.
    IF OBJECT_ID('tempdb.dbo.#covg02') IS NOT NULL DROP TABLE #covg02;
    WITH cte_coverage_counts AS (
        SELECT policy_id, policyimage_num, unit_num, coveragecode_id,
               COUNT(1) AS coverage_count
        FROM #covg00
        GROUP BY policy_id, policyimage_num, unit_num, coveragecode_id
    )
    SELECT c.*, cc.coverage_count
    INTO #covg02
    FROM #covg00 AS c
    LEFT JOIN cte_coverage_counts AS cc
           ON c.policy_id = cc.policy_id
          AND c.policyimage_num = cc.policyimage_num
          AND c.unit_num = cc.unit_num
          AND c.coveragecode_id = cc.coveragecode_id;

    DELETE FROM #covg02 WHERE premium_written = 0 AND coverage_count > 1;

    -- -----------------------------------------------------------------------
    -- Coverage pivot: replace 38 separate per-coverage-code temp tables with
    -- a single conditional aggregation over the full coverage+limit join.
    -- Each pair of columns captures limit_dscr and the limit description text
    -- (coveragelimit.dscr) for one specific coverage code.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#covg_pivot') IS NOT NULL DROP TABLE #covg_pivot;
    SELECT
        air.policy_id,
        air.policyimage_num,
        air.airport_num,
        -- 90167 Policy Limit
        MAX(CASE WHEN cov.coveragecode_id = 90167 THEN cl.limit_dscr END)  AS PolicyLimit_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90167 THEN cl.dscr END)        AS PolicyLimit_Description,
        -- 90168 BI/PD Liability
        MAX(CASE WHEN cov.coveragecode_id = 90168 THEN cl.limit_dscr END)  AS BIPD_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90168 THEN cl.dscr END)        AS BIPD_Descrption,
        -- 90161 Airport Operations Occurrence
        MAX(CASE WHEN cov.coveragecode_id = 90161 THEN cl.limit_dscr END)  AS AirportOperationsOccurence_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90161 THEN cl.dscr END)        AS AirportOperationsOccurence_Description,
        -- 90170 Airport Operations Per Person
        MAX(CASE WHEN cov.coveragecode_id = 90170 THEN cl.limit_dscr END)  AS AirportOperationsPerPerson_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90170 THEN cl.dscr END)        AS AirportOperationsPerPerson_Description,
        -- 90186 Personal Injury Occurrence
        MAX(CASE WHEN cov.coveragecode_id = 90186 THEN cl.limit_dscr END)  AS PersonalInjuryOccurrence_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90186 THEN cl.dscr END)        AS PersonalInjuryOccurrence_Description,
        -- 90187 Personal Injury Aggregate
        MAX(CASE WHEN cov.coveragecode_id = 90187 THEN cl.limit_dscr END)  AS PersonalInjuryAggregate_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90187 THEN cl.dscr END)        AS PersonalInjuryAggregate_Description,
        -- 90183 Fire Legal Liability
        MAX(CASE WHEN cov.coveragecode_id = 90183 THEN cl.limit_dscr END)  AS FireLegalLiability_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90183 THEN cl.dscr END)        AS FireLegalLiability_Description,
        -- 90184 Hangarkeepers Aircraft
        MAX(CASE WHEN cov.coveragecode_id = 90184 THEN cl.limit_dscr END)  AS HangarkeepersAircraft_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90184 THEN cl.dscr END)        AS HangarkeepersAircraft_Description,
        -- 90185 Hangarkeepers Occurrence
        MAX(CASE WHEN cov.coveragecode_id = 90185 THEN cl.limit_dscr END)  AS HangarkeepersOccurrence_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90185 THEN cl.dscr END)        AS HangarkeepersOccurrence_Description,
        -- 90188 Advertising Liability Occurrence
        MAX(CASE WHEN cov.coveragecode_id = 90188 THEN cl.limit_dscr END)  AS AdvertisingLiabilityOccurrence_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90188 THEN cl.dscr END)        AS AdvertisingLiabilityOccurrence_Description,
        -- 90189 Advertising Liability Aggregate
        MAX(CASE WHEN cov.coveragecode_id = 90189 THEN cl.limit_dscr END)  AS AdvertisingLiabilityAggregate_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90189 THEN cl.dscr END)        AS AdvertisingLiabilityAggregate_Description,
        -- 90190 Premises Medical Occurrence
        MAX(CASE WHEN cov.coveragecode_id = 90190 THEN cl.limit_dscr END)  AS PremisesMedicalOccurrence_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90190 THEN cl.dscr END)        AS PremisesMedicalOccurrence_Description,
        -- 90191 Premises Medical Per Person
        MAX(CASE WHEN cov.coveragecode_id = 90191 THEN cl.limit_dscr END)  AS PremisesMedicalPerPerson_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90191 THEN cl.dscr END)        AS PremisesMedicalPerPerson_Description,
        -- 90192 Premises Medical Aggregate
        MAX(CASE WHEN cov.coveragecode_id = 90192 THEN cl.limit_dscr END)  AS PremisesMedicalAggregate_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90192 THEN cl.dscr END)        AS PremisesMedicalAggregate_Description,
        -- 90171 Product and Completed Operations Occurrence
        MAX(CASE WHEN cov.coveragecode_id = 90171 THEN cl.limit_dscr END)  AS ProductandCompletedOperationsOccurrence_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90171 THEN cl.dscr END)        AS ProductandCompletedOperationsOccurrence_Description,
        -- 90172 Product and Completed Operations Per Person
        MAX(CASE WHEN cov.coveragecode_id = 90172 THEN cl.limit_dscr END)  AS ProductandCompletedOperationsPerPerson_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90172 THEN cl.dscr END)        AS ProductandCompletedOperationsPerPerson_Description,
        -- 90173 Product and Completed Operations Aggregate
        MAX(CASE WHEN cov.coveragecode_id = 90173 THEN cl.limit_dscr END)  AS ProductandCompletedOperationsAggregate_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90173 THEN cl.dscr END)        AS ProductandCompletedOperationsAggregate_Description,
        -- 90174 Repair and Services
        MAX(CASE WHEN cov.coveragecode_id = 90174 THEN cl.limit_dscr END)  AS RepairandServices_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90174 THEN cl.dscr END)        AS RepairandServices_Description,
        -- 90175 Excl. Eng and Prop Overhaul
        MAX(CASE WHEN cov.coveragecode_id = 90175 THEN cl.limit_dscr END)  AS ExclEngandPropOverhaul_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90175 THEN cl.dscr END)        AS ExclEngandPropOverhaul_Description,
        -- 90176 Fixed Wing Only
        MAX(CASE WHEN cov.coveragecode_id = 90176 THEN cl.limit_dscr END)  AS FixedWingOnly_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90176 THEN cl.dscr END)        AS FixedWingOnly_Description,
        -- 90177 Fuel/Lubricants
        MAX(CASE WHEN cov.coveragecode_id = 90177 THEN cl.limit_dscr END)  AS FuelLubricants_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90177 THEN cl.dscr END)        AS FuelLubricants_Description,
        -- 90179 Used Aircraft Sales
        MAX(CASE WHEN cov.coveragecode_id = 90179 THEN cl.limit_dscr END)  AS UsedAircraftSales_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90179 THEN cl.dscr END)        AS UsedAircraftSales_Description,
        -- 90180 Parts Sales
        MAX(CASE WHEN cov.coveragecode_id = 90180 THEN cl.limit_dscr END)  AS PartsSales_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90180 THEN cl.dscr END)        AS PartsSales_Description,
        -- 90182 Miscellaneous
        MAX(CASE WHEN cov.coveragecode_id = 90182 THEN cl.limit_dscr END)  AS Miscellaneous_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90182 THEN cl.dscr END)        AS Miscellaneous_Description,
        -- 90195 Hangarkeepers Deductible
        MAX(CASE WHEN cov.coveragecode_id = 90195 THEN cl.limit_dscr END)  AS HangarkeepersDeductible_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90195 THEN cl.dscr END)        AS HangarkeepersDeductible_Description,
        -- 90039 Certified Acts of Terrorism Premium
        MAX(CASE WHEN cov.coveragecode_id = 90039 THEN cl.limit_dscr END)  AS CertifiedActsofTerrorismPremium_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90039 THEN cl.dscr END)        AS CertifiedActsofTerrorismPremium_Description,
        -- 21134 Liquor Liability
        MAX(CASE WHEN cov.coveragecode_id = 21134 THEN cl.limit_dscr END)  AS LiquorLiability_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 21134 THEN cl.dscr END)        AS LiquorLiability_Description,
        -- 10035 Policy Level State Tax
        MAX(CASE WHEN cov.coveragecode_id = 10035 THEN cl.limit_dscr END)  AS PolicyLevelStateTax_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 10035 THEN cl.dscr END)        AS PolicyLevelStateTax_Description,
        -- 10036 Policy Level County Tax
        MAX(CASE WHEN cov.coveragecode_id = 10036 THEN cl.limit_dscr END)  AS PolicyLevelCountyTax_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 10036 THEN cl.dscr END)        AS PolicyLevelCountyTax_Description,
        -- 90103 AI Premium
        MAX(CASE WHEN cov.coveragecode_id = 90103 THEN cl.limit_dscr END)  AS AIPremium_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90103 THEN cl.dscr END)        AS AIPremium_Description,
        -- 90104 AI Premium Override
        MAX(CASE WHEN cov.coveragecode_id = 90104 THEN cl.limit_dscr END)  AS AIPremiumOverride_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90104 THEN cl.dscr END)        AS AIPremiumOverride_Description,
        -- 90156 Premium Type
        MAX(CASE WHEN cov.coveragecode_id = 90156 THEN cl.limit_dscr END)  AS PremiumType_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90156 THEN cl.dscr END)        AS PremiumType_Description,
        -- 90166 AI Premium Override Checkbox
        MAX(CASE WHEN cov.coveragecode_id = 90166 THEN cl.limit_dscr END)  AS AIPremiumOverrideCheckbox_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90166 THEN cl.dscr END)        AS AIPremiumOverrideCheckbox_Description,
        -- 90178 New Aircraft Sales
        MAX(CASE WHEN cov.coveragecode_id = 90178 THEN cl.limit_dscr END)  AS NewAircraftSales_Dcsr,
        MAX(CASE WHEN cov.coveragecode_id = 90178 THEN cl.dscr END)        AS NewAircraftSales_Description,
        -- 90181 Restaurant/Food/Vending
        MAX(CASE WHEN cov.coveragecode_id = 90181 THEN cl.limit_dscr END)  AS RestaurantFoodVending_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90181 THEN cl.dscr END)        AS RestaurantFoodVending_Description,
        -- 90193 Other Coverages Deductible
        MAX(CASE WHEN cov.coveragecode_id = 90193 THEN cl.limit_dscr END)  AS OtherCoveragesDeductible_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90193 THEN cl.dscr END)        AS OtherCoveragesDeductible_Description,
        -- 90194 Other Coverages Deductible Aggregate
        MAX(CASE WHEN cov.coveragecode_id = 90194 THEN cl.limit_dscr END)  AS OtherCoveragesDeductibleAggregate_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90194 THEN cl.dscr END)        AS OtherCoveragesDeductibleAggregate_Description,
        -- 90196 Contractual Liability
        MAX(CASE WHEN cov.coveragecode_id = 90196 THEN cl.limit_dscr END)  AS ContractualLiability_Dscr,
        MAX(CASE WHEN cov.coveragecode_id = 90196 THEN cl.dscr END)        AS ContractualLiability_Description
    INTO #covg_pivot
    FROM #airport AS air
    LEFT JOIN #covg02 AS cov
           ON cov.policy_id       = air.policy_id
          AND cov.policyimage_num = air.policyimage_num
          AND cov.unit_num        = air.airport_num
          AND cov.coveragecode_id IN (
              90167, 90168, 90161, 90170, 90186, 90187, 90183, 90184, 90185,
              90188, 90189, 90190, 90191, 90192, 90171, 90172, 90173, 90174,
              90175, 90176, 90177, 90179, 90180, 90182, 90195, 90039, 21134,
              10035, 10036, 90103, 90104, 90156, 90166, 90178, 90181, 90193,
              90194, 90196
          )
    LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit AS cl
           ON cl.coveragelimit_id = cov.coveragelimit_id
    GROUP BY air.policy_id, air.policyimage_num, air.airport_num;

    -- -----------------------------------------------------------------------
    -- Supporting lookup temp tables (insured, company, agency, address,
    -- entity, underwriter) — unchanged from original.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#InsuredandCompany') IS NOT NULL DROP TABLE #InsuredandCompany;
    SELECT
        a.policy_id, a.policyimage_num,
        b.display_name AS Insured,
        d.state        AS [State Insured]
    INTO #InsuredandCompany
    FROM #Airport_pol AS a
    LEFT JOIN [AHI-S06].diamond.dbo.vPolicyImageXML xml
           ON a.policy_id = xml.policy_id AND a.policyimage_num = xml.policyimage_num
    LEFT JOIN [AHI-S06].diamond.dbo.version v ON xml.version_id = v.version_id
    LEFT JOIN [AHI-S06].diamond.dbo.name AS b
           ON a.policy_id = b.policy_id AND a.policyimage_num = b.policyimage_num
    LEFT JOIN [AHI-S06].diamond.dbo.address AS c
           ON a.policy_id = c.policy_id AND a.policyimage_num = c.policyimage_num
    LEFT JOIN [AHI-S06].diamond.dbo.state AS d ON c.state_id = d.state_id
    WHERE b.nameaddresssource_id = 3 AND c.nameaddresssource_id = 3;

    IF OBJECT_ID('tempdb.dbo.#Company') IS NOT NULL DROP TABLE #Company;
    SELECT
        a.policy_id, a.policyimage_num,
        csl.commercial_name1 AS Company,
        csl.company_id       AS [Company Code]
    INTO #Company
    FROM #Airport_pol AS a
    LEFT JOIN [AHI-S06].diamond.dbo.policyimage p
           ON a.policy_id = p.policy_id AND a.policyimage_num = p.policyimage_num
    LEFT JOIN [AHI-S06].diamond.dbo.version ver ON p.version_id = ver.version_id
    LEFT JOIN [AHI-S06].diamond.dbo.vCompanyStateLOB csl ON ver.companystatelob_id = csl.companystatelob_id
    WHERE csl.lobname = 'Airport'
    GROUP BY a.policy_id, a.policyimage_num, csl.commercial_name1, csl.company_id;

    IF OBJECT_ID('tempdb.dbo.#agency') IS NOT NULL DROP TABLE #agency;
    SELECT
        air.policy_id, air.policyimage_num,
        p.agency_id,
        a.nameaddresssource_id, a.address_id,
        b.city  AS agency_city,
        c.state AS agency_state
    INTO #agency
    FROM #Airport_pol AS air
    LEFT JOIN [AHI-S06].diamond.dbo.vPolicyImageXML AS p
           ON air.policy_id = p.policy_id AND air.policyimage_num = p.policyimage_num
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[AgencyAddressLink] AS a ON p.agency_id = a.agency_id
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[Address] AS b ON a.address_id = b.address_id
    LEFT JOIN [AHI-S06].diamond.dbo.state AS c ON b.state_id = c.state_id
    WHERE a.nameaddresssource_id = 8
    GROUP BY air.policy_id, air.policyimage_num, p.agency_id,
             a.nameaddresssource_id, a.address_id, b.city, c.state;

    IF OBJECT_ID('tempdb.dbo.#PolicyAddress') IS NOT NULL DROP TABLE #PolicyAddress;
    SELECT
        air.policy_id, air.policyimage_num,
        b.nameaddresssource_id,
        b.city   AS policy_city,
        b.county AS policy_county,
        b.zip    AS policy_zip,
        c.state  AS policy_state
    INTO #PolicyAddress
    FROM #Airport_pol AS air
    LEFT JOIN [AHI-S06].diamond.dbo.PolicyImage AS a
           ON air.policy_id = a.policy_id AND air.policyimage_num = a.policyimage_num
    LEFT JOIN [AHI-S06].Diamond.dbo.Address AS b
           ON a.policy_id = b.policy_id AND a.policyimage_num = b.policyimage_num
    LEFT JOIN [AHI-S06].[Diamond].[dbo].state AS c ON b.state_id = c.state_id
    WHERE b.nameaddresssource_id = 3
    GROUP BY air.policy_id, air.policyimage_num, b.nameaddresssource_id,
             b.city, b.county, b.zip, c.state;

    IF OBJECT_ID('tempdb.dbo.#Entity') IS NOT NULL DROP TABLE #Entity;
    SELECT
        air.policy_id, air.policyimage_num,
        a.entitytype_id,
        b.dscr AS Entity_Type
    INTO #Entity
    FROM #Airport_pol AS air
    LEFT JOIN [AHI-S06].Diamond.dbo.Name AS a
           ON air.policy_id = a.policy_id AND air.policyimage_num = a.policyimage_num
    LEFT JOIN [AHI-S06].Diamond.dbo.EntityType AS b ON a.entitytype_id = b.entitytype_id
    WHERE a.nameaddresssource_id = 3
    GROUP BY air.policy_id, air.policyimage_num, a.entitytype_id, b.dscr;

    IF OBJECT_ID('tempdb.dbo.#underwriter') IS NOT NULL DROP TABLE #underwriter;
    SELECT
        air.policy_id, air.policyimage_num,
        a.underwriter_users_id,
        b.display_name AS underwriter_name
    INTO #underwriter
    FROM #Airport_pol AS air
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[policyimage] AS a
           ON a.policy_id = air.policy_id AND air.policyimage_num = a.policyimage_num
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[vusers] AS b ON a.underwriter_users_id = b.users_id
    GROUP BY air.policy_id, air.policyimage_num, a.underwriter_users_id, b.display_name;

    -- -----------------------------------------------------------------------
    -- Assemble the main output.  #covg_pivot replaces the 38 individual
    -- coverage LEFT JOINs that existed in the original procedure.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#DiaAP01') IS NOT NULL DROP TABLE #DiaAP01;
    SELECT
        'Diamond'  AS system,
        'Airport'  AS line,
        CASE WHEN pi.policy LIKE '%QAP%' OR pi.policy LIKE '%QHLMAP%' OR pi.policy LIKE '%QHDIAP%' THEN 'Quote'
             WHEN pi.policy LIKE '%AP%'  OR pi.policy LIKE '%HLMAP%'  OR pi.policy LIKE '%HDIAP%'  THEN 'Policy'
        END                                             AS Policy_Type,
        pol.client_id,
        pi.policy                                       AS pol_num,
        pi.renewal_ver                                  AS pol_ed,
        ap.policy_id,
        ap.policyimage_num,
        'APL'                                           AS reserving,
        a.unit_num,
        air.airport_display_num,
        lk.airport_code                                 AS faano,
        lk.airport_name,
        lk.city                                         AS airport_city,
        lk.county                                       AS airport_county,
        lk.state_abbr                                   AS airport_state,
        lk.zip,
        lk.in_city_limits,
        lk.is_coastal,
        lk.is_conforming,
        air.airportcategorytype_id,
        ct.dscr                                         AS airportcategorytype,
        air.airportbusinesstype_id,
        bt.dscr                                         AS airportbusinesstype,
        air.storagetype_id,
        st.dscr                                         AS storagetype,
        IAC.Insured                                     AS insd_name_hist,
        IAC.[State Insured]                             AS state_insd,
        en.Entity_Type,
        comp.[Company Code],
        comp.[Company]                                  AS company_code,
        uw.underwriter_name,
        padd.policy_city,
        padd.policy_county,
        padd.policy_state,
        padd.policy_zip,
        xml.policytermversion_dscr,
        xml.agency_code,
        xml.agency_id,
        xml.agency_name,
        xml.agencyproducer_code,
        xml.agencyproducer_id,
        xml.agencyproducer_name,
        ag.agency_city,
        ag.agency_state,
        pi.eff_date                                     AS date_pol_eff,
        pi.exp_date                                     AS date_pol_exp,
        pi.teff_date                                    AS Calendar_Effective_Date,
        pi.texp_date                                    AS Calendar_Expiration_Date,
        CASE WHEN pol.cancel_date = '1800-01-01' THEN '2999-12-31' ELSE pol.cancel_date END
                                                        AS date_cncl,
        pi.trans_date,
        pi.accounting_date,
        pi.received_date,
        pi.transtype_id,
        xml.transtype_dscr                              AS transaction_type,
        a.coverage_num,
        a.coveragecode_id,
        b.coveragecode,
        b.dscr                                          AS covg_description,
        a.premium_diff_chg_written                      AS old_premium_diff_chg_written,
        CASE WHEN ap.repeat_transaction_count = 1 THEN a.premium_diff_chg_written
             WHEN ap.repeat_transaction_count > 1 THEN 0
        END                                             AS premium_written,
        a.premium_fullterm                              AS premt_fullterm,
        a.premium_written                               AS premt_written,
        a.premium_chg_fullterm                          AS prem_chg_fullterm,
        a.premium_chg_written                           AS prem_chg_written,
        a.premium_annual                                AS premt_annual,
        a.premium_chg_annual                            AS prem_chg_annual,
        AA.commission                                   AS comm_written,
        a.coveragelimit_id,
        cl.limit_dscr,
        cl.claim_limit_perperson,
        cl.claim_limit_peroccur,
        cl.claim_deductible,
        cl.claim_limit_dscr,
        cl.claim_deduct_dscr,
        -- Coverage pivot columns (one LEFT JOIN replaces 38 individual ones)
        pvt.PolicyLimit_Dscr,
        pvt.PolicyLimit_Description,
        pvt.BIPD_Dscr,
        pvt.BIPD_Descrption,
        pvt.AirportOperationsOccurence_Dscr,
        pvt.AirportOperationsOccurence_Description,
        pvt.AirportOperationsPerPerson_Dscr,
        pvt.AirportOperationsPerPerson_Description,
        pvt.PersonalInjuryOccurrence_Dscr,
        pvt.PersonalInjuryOccurrence_Description,
        pvt.PersonalInjuryAggregate_Dscr,
        pvt.PersonalInjuryAggregate_Description,
        pvt.FireLegalLiability_Dscr,
        pvt.FireLegalLiability_Description,
        pvt.HangarkeepersAircraft_Dscr,
        pvt.HangarkeepersAircraft_Description,
        pvt.HangarkeepersOccurrence_Dscr,
        pvt.HangarkeepersOccurrence_Description,
        pvt.AdvertisingLiabilityOccurrence_Dscr,
        pvt.AdvertisingLiabilityOccurrence_Description,
        pvt.AdvertisingLiabilityAggregate_Dscr,
        pvt.AdvertisingLiabilityAggregate_Description,
        pvt.PremisesMedicalOccurrence_Dscr,
        pvt.PremisesMedicalOccurrence_Description,
        pvt.PremisesMedicalPerPerson_Dscr,
        pvt.PremisesMedicalPerPerson_Description,
        pvt.PremisesMedicalAggregate_Dscr,
        pvt.PremisesMedicalAggregate_Description,
        pvt.ProductandCompletedOperationsOccurrence_Dscr,
        pvt.ProductandCompletedOperationsOccurrence_Description,
        pvt.ProductandCompletedOperationsPerPerson_Dscr,
        pvt.ProductandCompletedOperationsPerPerson_Description,
        pvt.ProductandCompletedOperationsAggregate_Dscr,
        pvt.ProductandCompletedOperationsAggregate_Description,
        pvt.RepairandServices_Dscr,
        pvt.RepairandServices_Description,
        pvt.ExclEngandPropOverhaul_Dscr,
        pvt.ExclEngandPropOverhaul_Description,
        pvt.FixedWingOnly_Dscr,
        pvt.FixedWingOnly_Description,
        pvt.FuelLubricants_Dscr,
        pvt.FuelLubricants_Description,
        pvt.UsedAircraftSales_Dscr,
        pvt.UsedAircraftSales_Description,
        pvt.PartsSales_Dscr,
        pvt.PartsSales_Description,
        pvt.Miscellaneous_Dscr,
        pvt.Miscellaneous_Description,
        pvt.HangarkeepersDeductible_Dscr,
        pvt.HangarkeepersDeductible_Description,
        pvt.CertifiedActsofTerrorismPremium_Dscr,
        pvt.CertifiedActsofTerrorismPremium_Description,
        pvt.LiquorLiability_Dscr,
        pvt.LiquorLiability_Description,
        pvt.PolicyLevelStateTax_Dscr,
        pvt.PolicyLevelStateTax_Description,
        pvt.PolicyLevelCountyTax_Dscr,
        pvt.PolicyLevelCountyTax_Description,
        pvt.AIPremium_Dscr,
        pvt.AIPremium_Description,
        pvt.AIPremiumOverride_Dscr,
        pvt.AIPremiumOverride_Description,
        pvt.PremiumType_Dscr,
        pvt.PremiumType_Description,
        pvt.AIPremiumOverrideCheckbox_Dscr,
        pvt.AIPremiumOverrideCheckbox_Description,
        pvt.NewAircraftSales_Dcsr,
        pvt.NewAircraftSales_Description,
        pvt.RestaurantFoodVending_Dscr,
        pvt.RestaurantFoodVending_Description,
        pvt.OtherCoveragesDeductible_Dscr,
        pvt.OtherCoveragesDeductible_Description,
        pvt.OtherCoveragesDeductibleAggregate_Dscr,
        pvt.OtherCoveragesDeductibleAggregate_Description,
        pvt.ContractualLiability_Dscr,
        pvt.ContractualLiability_Description
    INTO #DiaAP01
    FROM #Airport_pol AS ap
    LEFT JOIN #covg02  AS a
           ON ap.policy_id = a.policy_id AND ap.policyimage_num = a.policyimage_num
    LEFT JOIN #airport AS air
           ON ap.policy_id       = air.policy_id
          AND ap.policyimage_num = air.policyimage_num
          AND a.unit_num         = air.airport_display_num
    LEFT JOIN [AHI-S06].diamond.dbo.coveragecode  AS b  ON a.coveragecode_id  = b.coveragecode_id
    LEFT JOIN [AHI-S06].[Diamond].[dbo].policy    AS pol ON a.policy_id        = pol.policy_id
    LEFT JOIN [AHI-S06].diamond.dbo.policyimage   AS pi
           ON pi.policy_id = ap.policy_id AND pi.policyimage_num = ap.policyimage_num
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[AirportLookup]       lk ON air.airportlookup_id     = lk.airportlookup_id
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[AirportCategoryType] ct ON ct.airportcategorytype_id = air.airportcategorytype_id
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[AirportBusinessType] bt ON bt.airportbusinesstype_id = air.airportbusinesstype_id
    LEFT JOIN [AHI-S06].diamond.dbo.storagetype   AS st  ON air.storagetype_id  = st.storagetype_id
    LEFT JOIN [AHI-S06].diamond.dbo.vPolicyImageXML xml
           ON xml.policy_id = ap.policy_id AND xml.policyimage_num = ap.policyimage_num
    LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit AS cl  ON cl.coveragelimit_id = a.coveragelimit_id
    LEFT JOIN #InsuredandCompany AS IAC
           ON IAC.policy_id = ap.policy_id AND IAC.policyimage_num = ap.policyimage_num
    LEFT JOIN #agency            AS ag
           ON ag.policy_id  = ap.policy_id AND ag.policyimage_num  = ap.policyimage_num
    LEFT JOIN #PolicyAddress     AS padd
           ON padd.policy_id = ap.policy_id AND padd.policyimage_num = ap.policyimage_num
    LEFT JOIN #Entity            AS en
           ON en.policy_id  = ap.policy_id AND en.policyimage_num  = ap.policyimage_num
    -- Single pivot join replaces 38 per-coverage LEFT JOINs
    LEFT JOIN #covg_pivot        AS pvt
           ON pvt.policy_id = ap.policy_id AND pvt.policyimage_num = ap.policyimage_num
          AND pvt.airport_num = a.unit_num
    LEFT JOIN #underwriter       AS uw
           ON a.policy_id   = uw.policy_id AND a.policyimage_num   = uw.policyimage_num
    LEFT JOIN [AHI-S06].[Diamond].[dbo].[AgencyActivity] AA
           ON AA.policy_id = ap.policy_id AND AA.policyimage_num = ap.policyimage_num
          AND xml.agency_id = AA.agency_id AND xml.agencyproducer_id = AA.agencyproducer_id
    LEFT JOIN #Company AS comp
           ON ap.policy_id = comp.policy_id AND ap.policyimage_num = comp.policyimage_num
    WHERE CASE WHEN pi.policy LIKE 'Q%' THEN 'Quote' ELSE 'Policy' END = 'Policy';

    -- Remove sub-coverages that are aggregated into their parent coverage codes,
    -- plus tax/fee lines that don't belong in the output.
    DELETE FROM #DiaAP01
    WHERE coveragecode_id IN (
        90174, 90177, 90178, 90179, 90180, 90181, 90182,
        10035, 10036, 10037, 10038, 10039, 10040,
        90000, 90004, 90005
    );

    -- -----------------------------------------------------------------------
    -- Add date-derived and rating placeholder columns.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb.dbo.#DiaAP02') IS NOT NULL DROP TABLE #DiaAP02;
    SELECT
        a.*,
        DATEPART(yy, a.date_pol_eff)  * 100 + DATEPART(mm, a.date_pol_eff)  AS mth_pol_eff,
        DATEPART(yy, a.date_pol_exp)  * 100 + DATEPART(mm, a.date_pol_exp)  AS mth_pol_exp,
        DATEPART(yy, a.Calendar_Effective_Date) * 100
            + DATEPART(mm, a.Calendar_Effective_Date)                        AS mth_cal_eff,
        DATEPART(yy, a.Calendar_Expiration_Date) * 100
            + DATEPART(mm, a.Calendar_Expiration_Date)                       AS mth_cal_exp,
        DATEPART(yy, a.date_pol_eff) * 10 + CASE
            WHEN DATEPART(mm, a.date_pol_eff) IN (1,2,3)   THEN 1
            WHEN DATEPART(mm, a.date_pol_eff) IN (4,5,6)   THEN 2
            WHEN DATEPART(mm, a.date_pol_eff) IN (7,8,9)   THEN 3
            ELSE 4 END                                                       AS qtr_pol_eff,
        DATEPART(yy, a.date_pol_exp) * 10 + CASE
            WHEN DATEPART(mm, a.date_pol_exp) IN (1,2,3)   THEN 1
            WHEN DATEPART(mm, a.date_pol_exp) IN (4,5,6)   THEN 2
            WHEN DATEPART(mm, a.date_pol_exp) IN (7,8,9)   THEN 3
            ELSE 4 END                                                       AS qtr_pol_exp,
        DATEPART(yy, a.Calendar_Effective_Date) * 10 + CASE
            WHEN DATEPART(mm, a.Calendar_Effective_Date) IN (1,2,3)  THEN 1
            WHEN DATEPART(mm, a.Calendar_Effective_Date) IN (4,5,6)  THEN 2
            WHEN DATEPART(mm, a.Calendar_Effective_Date) IN (7,8,9)  THEN 3
            ELSE 4 END                                                       AS qtr_cal_eff,
        DATEPART(yy, a.Calendar_Expiration_Date) * 10 + CASE
            WHEN DATEPART(mm, a.Calendar_Expiration_Date) IN (1,2,3) THEN 1
            WHEN DATEPART(mm, a.Calendar_Expiration_Date) IN (4,5,6) THEN 2
            WHEN DATEPART(mm, a.Calendar_Expiration_Date) IN (7,8,9) THEN 3
            ELSE 4 END                                                       AS qtr_cal_exp,
        DATEPART(yy, a.date_pol_eff)                                         AS yr_pol,
        DATEPART(yy, a.Calendar_Effective_Date)                              AS yr_cal_eff,
        CAST(DATEDIFF(dd, a.date_pol_eff, DATEADD(yy, 1, a.date_pol_eff)) AS FLOAT) AS term_year,
        ROUND(
            CAST(DATEDIFF(dd, a.date_pol_eff, a.date_pol_exp) AS MONEY) /
            CAST(DATEDIFF(dd, a.date_pol_eff, DATEADD(yy, 1, a.date_pol_eff)) AS MONEY),
            3
        )                                                                    AS Term_years,
        a.prem_chg_annual                                                    AS prem_annual,
        1 AS STT, 1 AS r_STT, 1 AS rr_STT, 1 AS rrr_STT, 1 AS zz_STT,
        a.premium_written    AS prem_tech_written,
        a.premium_written    AS r_prem_tech_written,
        a.premium_written    AS rr_prem_tech_written,
        a.premium_written    AS rrr_prem_tech_written,
        a.premium_written    AS zz_prem_tech_written,
        a.premium_written    AS r_prem_written,
        a.premium_written    AS rr_prem_written,
        a.premium_written    AS rrr_prem_written,
        a.premium_written    AS zz_prem_written,
        a.prem_chg_annual    AS prem_tech_annual,
        a.prem_chg_annual    AS r_prem_tech_annual,
        a.prem_chg_annual    AS rr_prem_tech_annual,
        a.prem_chg_annual    AS rrr_prem_tech_annual,
        a.prem_chg_annual    AS zz_prem_tech_annual,
        a.prem_chg_annual    AS r_prem_annual,
        a.prem_chg_annual    AS rr_prem_annual,
        a.prem_chg_annual    AS rrr_prem_annual,
        a.prem_chg_annual    AS zz_prem_annual,
        a.premium_written    AS r_adq_written,
        a.premium_written    AS rr_adq_written,
        a.premium_written    AS rrr_adq_written,
        a.premium_written    AS zz_adq_written,
        a.prem_chg_annual    AS r_adq_annual,
        a.prem_chg_annual    AS rr_adq_annual,
        a.prem_chg_annual    AS rrr_adq_annual,
        a.prem_chg_annual    AS zz_adq_annual,
        a.premium_written    AS r_adq_tech_written,
        a.premium_written    AS rr_adq_tech_written,
        a.premium_written    AS rrr_adq_tech_written,
        a.premium_written    AS zz_adq_tech_written,
        a.prem_chg_annual    AS r_adq_tech_annual,
        a.prem_chg_annual    AS rr_adq_tech_annual,
        a.prem_chg_annual    AS rrr_adq_tech_annual,
        a.prem_chg_annual    AS zz_adq_tech_annual,
        a.premium_written * 0.65 AS r_padq_tech_written,
        a.premium_written * 0.65 AS rr_padq_tech_written,
        a.premium_written * 0.65 AS rrr_padq_tech_written,
        a.premium_written * 0.65 AS zz_padq_tech_written,
        a.prem_chg_annual * 0.65 AS r_padq_tech_annual,
        a.prem_chg_annual * 0.65 AS rr_padq_tech_annual,
        a.prem_chg_annual * 0.65 AS rrr_padq_tech_annual,
        a.prem_chg_annual * 0.65 AS zz_padq_tech_annual,
        a.premium_written * 0.65 AS r_blpadq_tech_written,
        a.premium_written * 0.65 AS rr_blpadq_tech_written,
        a.premium_written * 0.65 AS rrr_blpadq_tech_written,
        a.premium_written * 0.65 AS zz_blpadq_tech_written,
        a.prem_chg_annual * 0.65 AS r_blpadq_tech_annual,
        a.prem_chg_annual * 0.65 AS rr_blpadq_tech_annual,
        a.prem_chg_annual * 0.65 AS rrr_blpadq_tech_annual,
        a.prem_chg_annual * 0.65 AS zz_blpadq_tech_annual
    INTO #DiaAP02
    FROM #DiaAP01 AS a
    CROSS JOIN @tv_dates AS b
    WHERE a.date_pol_eff    < b.date_book
      AND a.accounting_date < b.date_book
      AND a.received_date   < b.date_book
      AND a.trans_date      < b.date_book;

    -- Attach metadata columns to the staging temp table
    ALTER TABLE #DiaAP02 ADD
        row_hash     BINARY(32)   NULL,
        created_date DATETIME2(0) NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0) NOT NULL DEFAULT GETDATE();

    UPDATE #DiaAP02
    SET row_hash = CONVERT(BINARY(32), HASHBYTES('SHA2_256',
        CONCAT_WS('|',
            CAST(premium_written AS NVARCHAR(30)),
            CAST(premt_fullterm  AS NVARCHAR(30)),
            CAST(prem_chg_annual AS NVARCHAR(30))
        )
    ));

    -- -----------------------------------------------------------------------
    -- Write to test_DiaAPCovg.  Dynamic SQL builds the column list from
    -- sys.columns so the INSERT never drifts when schema changes.
    -- aim_row_id (IDENTITY) is excluded — SQL Server generates it.
    -- -----------------------------------------------------------------------
    TRUNCATE TABLE dbo.test_DiaAPCovg;

    DECLARE @cols NVARCHAR(MAX);
    SELECT @cols = STRING_AGG(QUOTENAME(c.name), ', ')
                   WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns AS c
    WHERE c.object_id = OBJECT_ID('dbo.test_DiaAPCovg')
      AND c.is_identity = 0;

    DECLARE @insertSQL NVARCHAR(MAX) =
        N'INSERT INTO dbo.test_DiaAPCovg (' + @cols + N') SELECT ' + @cols + N' FROM #DiaAP02;';
    EXEC sp_executesql @insertSQL;

    -- Clean up
    DROP TABLE
        #policyimage, #Airport_pol, #airport,
        #covg00, #covg02, #covg_pivot,
        #InsuredandCompany, #Company, #agency,
        #PolicyAddress, #Entity, #underwriter,
        #DiaAP01, #DiaAP02;

    DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID);
    EXEC UPDATE_QUERY_TIMES @PROC_NAME, @startTime;

END TRY
BEGIN CATCH
    SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE;
END CATCH
GO
