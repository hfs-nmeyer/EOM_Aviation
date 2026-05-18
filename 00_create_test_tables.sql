USE [Pricing_AIM]
GO

/*=============================================================================
  00_create_test_tables.sql
  Purpose : Create test_ shadow tables for each EOM Aviation output table.
             These tables mirror the production schemas but add:
               - aim_row_id   : surrogate PK (IDENTITY)
               - row_hash     : SHA2-256 fingerprint of key financial columns
                                used by MERGE statements to detect changes
               - created_date : populated once on INSERT
               - last_updated : refreshed on every MERGE UPDATE

  Run once to set up the test environment.  Each test SP will MERGE into
  these tables rather than DROP/SELECT INTO production tables.
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 1. test_DiamondEarnedPremium_Aviation_JChenVScopy
--    Natural key  : policy_id + policyimage_num + unit_num + coveragecode_id
--                   + Year + AcctPer
--    Source proc  : run_test_Diamond_WP_EP
-- ============================================================================
IF OBJECT_ID('dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy') IS NOT NULL
    DROP TABLE dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy;
GO

CREATE TABLE dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy
(
    -- Surrogate key
    aim_row_id              BIGINT          IDENTITY(1,1) NOT NULL,

    -- Business columns (match production exactly)
    Platform                VARCHAR(7)      NOT NULL,
    [Year]                  INT             NULL,
    AcctPer                 INT             NULL,
    AcctQtr                 INT             NULL,
    CoverageCodeGrouped     VARCHAR(18)     NULL,
    coveragecode            VARCHAR(255)    NOT NULL,
    ccdscr                  VARCHAR(255)    NOT NULL,
    coveragetype            VARCHAR(255)    NOT NULL,
    [State]                 VARCHAR(6)      NOT NULL,
    Carrier                 VARCHAR(800)    NOT NULL,
    policy_id               INT             NOT NULL,
    policy                  VARCHAR(40)     NOT NULL,
    policyimage_num         INT             NOT NULL,
    unit_num                INT             NOT NULL,
    NewRenew                VARCHAR(5)      NOT NULL,
    PolicyTypeGroupDesc     VARCHAR(255)    NOT NULL,
    CoverageGroupDetailDesc1 VARCHAR(255)   NOT NULL,
    PolicyType              VARCHAR(255)    NOT NULL,
    premium_written_mtd     MONEY           NULL,
    premium_earned_mtd      MONEY           NULL,
    premium_unearned        MONEY           NULL,
    premium_unearned_priormonth MONEY       NULL,
    premium_written         MONEY           NULL,
    UepPriorMinusCurent     MONEY           NULL,
    EffectiveDate           DATE            NOT NULL,
    ExpirationDate          DATE            NOT NULL,
    majorperil              VARCHAR(255)    NOT NULL,
    months                  INT             NULL,
    ratingversion_id        INT             NULL,

    -- Audit / change-tracking columns
    row_hash                BINARY(32)      NULL,
    created_date            DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated            DATETIME2(0)    NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_test_DiamondEP PRIMARY KEY CLUSTERED (aim_row_id)
);

CREATE UNIQUE NONCLUSTERED INDEX UX_test_DiamondEP_NaturalKey
    ON dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy
    (policy_id, policyimage_num, unit_num, coveragecode, [Year], AcctPer);

CREATE NONCLUSTERED INDEX IX_test_DiamondEP_PolicyType
    ON dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy (PolicyType, [Year], AcctPer);
GO

-- ============================================================================
-- 2. test_aim_loss_ulae
--    Natural key  : Clmid + CLAIM_TYPE_DESC + mth_val
--    Source proc  : run_test_AIM_Apollo_Loss
-- ============================================================================
IF OBJECT_ID('dbo.test_aim_loss_ulae') IS NOT NULL
    DROP TABLE dbo.test_aim_loss_ulae;
GO

CREATE TABLE dbo.test_aim_loss_ulae
(
    aim_row_id              BIGINT          IDENTITY(1,1) NOT NULL,

    lookup_claims           NVARCHAR(65)    NULL,
    polid                   INT             NULL,
    [Claim No]              NVARCHAR(10)    NULL,
    Clmid                   INT             NOT NULL,
    CLAIM_TYPE              INT             NULL,
    CLAIM_TYPE_DESC         VARCHAR(3)      NULL,
    Reserving               VARCHAR(3)      NULL,
    [policy no]             NVARCHAR(15)    NULL,
    treaty_id               NVARCHAR(5)     NULL,
    Claim_state             NVARCHAR(5)     NULL,
    AircraftID              INT             NULL,
    FAANo                   NVARCHAR(50)    NULL,
    AircraftType            FLOAT           NULL,
    Gear                    NVARCHAR(6)     NULL,
    Wing                    NVARCHAR(50)    NULL,
    AircraftTypeNameDisplay NVARCHAR(288)   NULL,
    HullAge                 INT             NULL,
    HullValue_AgreedValue   FLOAT           NULL,
    HasClaim                INT             NOT NULL DEFAULT 0,
    ClmCat                  VARCHAR(1)      NOT NULL DEFAULT '',
    ClaimCauseGroup         VARCHAR(100)    NULL,
    ClaimCause              VARCHAR(100)    NULL,
    ClaimHullValue          FLOAT           NULL,
    WHAT_TABLE              VARCHAR(50)     NOT NULL DEFAULT '',
    DOL                     DATE            NULL,
    AY                      INT             NULL,
    mth_loss                INT             NULL,
    qtr_loss                INT             NULL,
    REPORTED_DATE           VARCHAR(12)     NULL,
    mth_rept                INT             NULL,
    qtr_rept                INT             NULL,
    [Close Date]            VARCHAR(12)     NULL,
    mth_close               INT             NULL,
    qtr_close               INT             NULL,
    mth_val                 INT             NULL,
    qtr_val                 INT             NULL,
    qtr_end                 INT             NOT NULL DEFAULT 0,
    mth_dev                 INT             NULL,
    qtr_dev                 INT             NULL,
    paid_loss               MONEY           NULL,
    paid_alae               MONEY           NULL,
    paid_ulae               MONEY           NULL,
    paid_lae                MONEY           NULL,
    incd_loss               MONEY           NULL,
    incd_alae               MONEY           NULL,
    incd_ulae               MONEY           NULL,
    incd_lae                MONEY           NULL,
    paid_la                 MONEY           NULL,
    incd_la                 MONEY           NULL,
    net_paid_loss           MONEY           NULL,
    net_paid_alae           MONEY           NULL,
    net_paid_ulae           MONEY           NULL,
    net_paid_lae            MONEY           NULL,
    net_incd_loss           MONEY           NULL,
    net_incd_alae           MONEY           NULL,
    net_incd_ulae           MONEY           NULL,
    net_incd_lae            MONEY           NULL,
    net_paid_la             MONEY           NULL,
    net_incd_la             MONEY           NULL,
    ClaimCauseGroup_detail  VARCHAR(100)    NULL,
    Weather_claim_ind       INT             NOT NULL DEFAULT 0,
    D55_CAT_CODE            NVARCHAR(255)   NULL,
    cat_description         VARCHAR(30)     NULL,
    date_close_act          VARCHAR(12)     NOT NULL DEFAULT '',
    date_reopen_act         VARCHAR(12)     NOT NULL DEFAULT '',
    qtr_close_act           INT             NULL,
    flg_close               INT             NOT NULL DEFAULT 0,
    flg_reopen              INT             NOT NULL DEFAULT 0,
    clm_status1             VARCHAR(2)      NOT NULL DEFAULT '',
    clm_status2             VARCHAR(17)     NOT NULL DEFAULT '',
    clm_status3             VARCHAR(17)     NOT NULL DEFAULT '',

    row_hash                BINARY(32)      NULL,
    created_date            DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated            DATETIME2(0)    NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_test_aim_loss_ulae PRIMARY KEY CLUSTERED (aim_row_id)
);

CREATE NONCLUSTERED INDEX IX_test_aim_loss_ulae_NatKey
    ON dbo.test_aim_loss_ulae (Clmid, CLAIM_TYPE_DESC, mth_val);

CREATE NONCLUSTERED INDEX IX_test_aim_loss_ulae_AY
    ON dbo.test_aim_loss_ulae (AY, CLAIM_TYPE_DESC, mth_val);
GO

-- ============================================================================
-- 3. test_AIMLoss
--    Natural key  : system + claimcontrol_id + mth_val + covg
--    Source proc  : run_test_AIMLoss
-- ============================================================================
IF OBJECT_ID('dbo.test_AIMLoss') IS NOT NULL
    DROP TABLE dbo.test_AIMLoss;
GO

CREATE TABLE dbo.test_AIMLoss
(
    aim_row_id          BIGINT          IDENTITY(1,1) NOT NULL,

    system              VARCHAR(7)      NOT NULL,
    clm_ft_num          NVARCHAR(261)   NULL,
    claim_number        NVARCHAR(255)   NULL,
    claimcontrol_id     INT             NULL,
    claimant_num        INT             NULL,
    claimfeature_num    INT             NULL,
    reserving           VARCHAR(11)     NULL,
    policy              NVARCHAR(40)    NULL,
    policy_id           INT             NULL,
    Company             VARCHAR(255)    NULL,
    policyimage_num     INT             NULL,
    aircraft_num        INT             NULL,
    state_risk          NVARCHAR(6)     NULL,
    yr_loss             INT             NULL,
    qtr_loss            INT             NULL,
    mth_loss            INT             NULL,
    date_loss           DATETIME        NULL,
    date_occ_close      DATE            NULL,
    date_ft_close       DATE            NULL,
    mth_cal_earn        INT             NULL,
    mth_val             INT             NULL,
    qtr_val             INT             NULL,
    yr_val              INT             NULL,
    qtr_ind             INT             NOT NULL DEFAULT 0,
    yr_ind              INT             NOT NULL DEFAULT 0,
    rept_mth_occ        INT             NULL,
    rept_qtr_occ        INT             NULL,
    rept_yr_occ         INT             NULL,
    occ_rept_date       DATETIME        NULL,
    occ_rept_date_act   DATE            NULL,
    rept_mth_ft         INT             NULL,
    rept_qtr_ft         INT             NULL,
    rept_yr_ft          INT             NULL,
    ft_rept_date        DATETIME        NULL,
    covg                VARCHAR(10)     NULL,
    coveragecode        VARCHAR(255)    NULL,
    CAT_indicator       INT             NULL,
    ISOCatNumber        VARCHAR(30)     NULL,
    clm_ft_status1      VARCHAR(255)    NULL,
    clm_ft_status2      VARCHAR(17)     NOT NULL DEFAULT '',
    clm_ft_status3      VARCHAR(17)     NOT NULL DEFAULT '',
    mth_ft_close_act    INT             NULL,
    clm_occ_status1     VARCHAR(255)    NULL,
    clm_occ_status2     VARCHAR(17)     NOT NULL DEFAULT '',
    clm_occ_status3     VARCHAR(17)     NOT NULL DEFAULT '',
    mth_occ_close_act   INT             NULL,
    date_close_act      DATE            NULL,
    mth_occ_reopen_act  INT             NULL,
    date_reopen_act     DATE            NULL,
    mth_age             INT             NULL,
    qtr_age             INT             NULL,
    paid_l              MONEY           NULL,
    incd_l              MONEY           NULL,
    paid_nlgl           MONEY           NULL,
    incd_nlgl           MONEY           NULL,
    paid_a              MONEY           NULL,
    incd_a              MONEY           NULL,
    subro               MONEY           NULL,
    salvage             MONEY           NULL,
    recovery            MONEY           NULL,
    paid_la             MONEY           NULL,
    paid_llae           MONEY           NULL,
    incd_la             MONEY           NULL,
    incd_llae           MONEY           NULL,
    net_paid_l          MONEY           NULL,
    net_incd_l          MONEY           NULL,
    net_paid_la         MONEY           NULL,
    net_paid_llae       MONEY           NULL,
    net_incd_la         MONEY           NULL,
    net_incd_llae       MONEY           NULL,
    is_represented      INT             NULL,

    row_hash            BINARY(32)      NULL,
    created_date        DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated        DATETIME2(0)    NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_test_AIMLoss PRIMARY KEY CLUSTERED (aim_row_id)
);

-- Composite index on the most-queried dimensions
CREATE NONCLUSTERED INDEX IX_test_AIMLoss_System_Claim_Val
    ON dbo.test_AIMLoss (system, claimcontrol_id, mth_val, covg);

CREATE NONCLUSTERED INDEX IX_test_AIMLoss_YrLoss_Covg
    ON dbo.test_AIMLoss (yr_loss, covg, system);
GO

-- ============================================================================
-- 4. test_DiaAPCovg
--    Natural key  : policy_id + policyimage_num + coverage_num + unit_num
--    Source proc  : run_test_Diamond_Airport_Table
--    NOTE: 219 columns — only key financial fields in the row_hash to keep
--          the hash computation tractable.
-- ============================================================================
IF OBJECT_ID('dbo.test_DiaAPCovg') IS NOT NULL
    DROP TABLE dbo.test_DiaAPCovg;
GO

CREATE TABLE dbo.test_DiaAPCovg
(
    aim_row_id                              BIGINT          IDENTITY(1,1) NOT NULL,

    -- Identity / policy
    system                                  VARCHAR(7)      NOT NULL,
    line                                    VARCHAR(7)      NOT NULL,
    Policy_Type                             VARCHAR(6)      NULL,
    client_id                               INT             NULL,
    pol_num                                 VARCHAR(40)     NULL,
    pol_ed                                  INT             NULL,
    policy_id                               INT             NOT NULL,
    policyimage_num                         INT             NOT NULL,
    reserving                               VARCHAR(3)      NOT NULL,
    unit_num                                INT             NULL,
    airport_display_num                     INT             NULL,
    faano                                   VARCHAR(32)     NULL,
    airport_name                            VARCHAR(255)    NULL,
    airport_city                            VARCHAR(255)    NULL,
    airport_county                          VARCHAR(255)    NULL,
    airport_state                           CHAR(2)         NULL,
    zip                                     VARCHAR(255)    NULL,
    in_city_limits                          BIT             NULL,
    is_coastal                              BIT             NULL,
    is_conforming                           BIT             NULL,
    airportcategorytype_id                  INT             NULL,
    airportcategorytype                     VARCHAR(255)    NULL,
    airportbusinesstype_id                  INT             NULL,
    airportbusinesstype                     VARCHAR(255)    NULL,
    storagetype_id                          INT             NULL,
    storagetype                             VARCHAR(255)    NULL,

    -- Insured / agent / company
    insd_name_hist                          VARCHAR(800)    NULL,
    state_insd                              VARCHAR(6)      NULL,
    Entity_Type                             VARCHAR(255)    NULL,
    [Company Code]                          INT             NULL,
    company_code                            VARCHAR(255)    NULL,
    underwriter_name                        VARCHAR(800)    NULL,
    policy_city                             VARCHAR(75)     NULL,
    policy_county                           VARCHAR(50)     NULL,
    policy_state                            VARCHAR(6)      NULL,
    policy_zip                              VARCHAR(50)     NULL,
    policytermversion_dscr                  VARCHAR(255)    NULL,
    agency_code                             VARCHAR(255)    NULL,
    agency_id                               INT             NULL,
    agency_name                             VARCHAR(255)    NULL,
    agencyproducer_code                     VARCHAR(255)    NULL,
    agencyproducer_id                       INT             NULL,
    agencyproducer_name                     VARCHAR(800)    NULL,
    agency_city                             VARCHAR(75)     NULL,
    agency_state                            VARCHAR(6)      NULL,

    -- Dates / transaction
    date_pol_eff                            DATE            NULL,
    date_pol_exp                            DATE            NULL,
    Calendar_Effective_Date                 DATE            NULL,
    Calendar_Expiration_Date                DATE            NULL,
    date_cncl                               DATETIME        NULL,
    trans_date                              DATETIME        NULL,
    accounting_date                         DATETIME        NULL,
    received_date                           DATETIME        NULL,
    transtype_id                            INT             NULL,
    transaction_type                        VARCHAR(255)    NULL,

    -- Coverage
    coverage_num                            INT             NULL,
    coveragecode_id                         INT             NULL,
    coveragecode                            VARCHAR(255)    NULL,
    covg_description                        VARCHAR(255)    NULL,
    old_premium_diff_chg_written            MONEY           NULL,
    premium_written                         MONEY           NULL,
    premt_fullterm                          MONEY           NULL,
    premt_written                           MONEY           NULL,
    prem_chg_fullterm                       MONEY           NULL,
    prem_chg_written                        MONEY           NULL,
    premt_annual                            MONEY           NULL,
    prem_chg_annual                         MONEY           NULL,
    comm_written                            MONEY           NULL,
    coveragelimit_id                        INT             NULL,
    limit_dscr                              VARCHAR(255)    NULL,
    claim_limit_perperson                   MONEY           NULL,
    claim_limit_peroccur                    MONEY           NULL,
    claim_deductible                        MONEY           NULL,
    claim_limit_dscr                        VARCHAR(255)    NULL,
    claim_deduct_dscr                       VARCHAR(255)    NULL,

    -- Coverage limit descriptions (one pair per coverage type)
    PolicyLimit_Dscr                        VARCHAR(255)    NULL,
    PolicyLimit_Description                 VARCHAR(255)    NULL,
    BIPD_Dscr                               VARCHAR(255)    NULL,
    BIPD_Descrption                         VARCHAR(255)    NULL,
    AirportOperationsOccurence_Dscr         VARCHAR(255)    NULL,
    AirportOperationsOccurence_Description  VARCHAR(255)    NULL,
    AirportOperationsPerPerson_Dscr         VARCHAR(255)    NULL,
    AirportOperationsPerPerson_Description  VARCHAR(255)    NULL,
    PersonalInjuryOccurrence_Dscr           VARCHAR(255)    NULL,
    PersonalInjuryOccurrence_Description    VARCHAR(255)    NULL,
    PersonalInjuryAggregate_Dscr            VARCHAR(255)    NULL,
    PersonalInjuryAggregate_Description     VARCHAR(255)    NULL,
    FireLegalLiability_Dscr                 VARCHAR(255)    NULL,
    FireLegalLiability_Description          VARCHAR(255)    NULL,
    HangarkeepersAircraft_Dscr              VARCHAR(255)    NULL,
    HangarkeepersAircraft_Description       VARCHAR(255)    NULL,
    HangarkeepersOccurrence_Dscr            VARCHAR(255)    NULL,
    HangarkeepersOccurrence_Description     VARCHAR(255)    NULL,
    AdvertisingLiabilityOccurrence_Dscr     VARCHAR(255)    NULL,
    AdvertisingLiabilityOccurrence_Description VARCHAR(255) NULL,
    AdvertisingLiabilityAggregate_Dscr      VARCHAR(255)    NULL,
    AdvertisingLiabilityAggregate_Description VARCHAR(255)  NULL,
    PremisesMedicalOccurrence_Dscr          VARCHAR(255)    NULL,
    PremisesMedicalOccurrence_Description   VARCHAR(255)    NULL,
    PremisesMedicalPerPerson_Dscr           VARCHAR(255)    NULL,
    PremisesMedicalPerPerson_Description    VARCHAR(255)    NULL,
    PremisesMedicalAggregate_Dscr           VARCHAR(255)    NULL,
    PremisesMedicalAggregate_Description    VARCHAR(255)    NULL,
    ProductandCompletedOperationsOccurrence_Dscr    VARCHAR(255) NULL,
    ProductandCompletedOperationsOccurrence_Description VARCHAR(255) NULL,
    ProductandCompletedOperationsPerPerson_Dscr     VARCHAR(255) NULL,
    ProductandCompletedOperationsPerPerson_Description VARCHAR(255) NULL,
    ProductandCompletedOperationsAggregate_Dscr     VARCHAR(255) NULL,
    ProductandCompletedOperationsAggregate_Description VARCHAR(255) NULL,
    RepairandServices_Dscr                  VARCHAR(255)    NULL,
    RepairandServices_Description           VARCHAR(255)    NULL,
    ExclEngandPropOverhaul_Dscr             VARCHAR(255)    NULL,
    ExclEngandPropOverhaul_Description      VARCHAR(255)    NULL,
    FixedWingOnly_Dscr                      VARCHAR(255)    NULL,
    FixedWingOnly_Description               VARCHAR(255)    NULL,
    FuelLubricants_Dscr                     VARCHAR(255)    NULL,
    FuelLubricants_Description              VARCHAR(255)    NULL,
    UsedAircraftSales_Dscr                  VARCHAR(255)    NULL,
    UsedAircraftSales_Description           VARCHAR(255)    NULL,
    PartsSales_Dscr                         VARCHAR(255)    NULL,
    PartsSales_Description                  VARCHAR(255)    NULL,
    Miscellaneous_Dscr                      VARCHAR(255)    NULL,
    Miscellaneous_Description               VARCHAR(255)    NULL,
    HangarkeepersDeductible_Dscr            VARCHAR(255)    NULL,
    HangarkeepersDeductible_Description     VARCHAR(255)    NULL,
    CertifiedActsofTerrorismPremium_Dscr    VARCHAR(255)    NULL,
    CertifiedActsofTerrorismPremium_Description VARCHAR(255) NULL,
    LiquorLiability_Dscr                    VARCHAR(255)    NULL,
    LiquorLiability_Description             VARCHAR(255)    NULL,
    PolicyLevelStateTax_Dscr                VARCHAR(255)    NULL,
    PolicyLevelStateTax_Description         VARCHAR(255)    NULL,
    PolicyLevelCountyTax_Dscr               VARCHAR(255)    NULL,
    PolicyLevelCountyTax_Description        VARCHAR(255)    NULL,
    AIPremium_Dscr                          VARCHAR(255)    NULL,
    AIPremium_Description                   VARCHAR(255)    NULL,
    AIPremiumOverride_Dscr                  VARCHAR(255)    NULL,
    AIPremiumOverride_Description           VARCHAR(255)    NULL,
    PremiumType_Dscr                        VARCHAR(255)    NULL,
    PremiumType_Description                 VARCHAR(255)    NULL,
    AIPremiumOverrideCheckbox_Dscr          VARCHAR(255)    NULL,
    AIPremiumOverrideCheckbox_Description   VARCHAR(255)    NULL,
    NewAircraftSales_Dcsr                   VARCHAR(255)    NULL,
    NewAircraftSales_Description            VARCHAR(255)    NULL,
    RestaurantFoodVending_Dscr              VARCHAR(255)    NULL,
    RestaurantFoodVending_Description       VARCHAR(255)    NULL,
    OtherCoveragesDeductible_Dscr           VARCHAR(255)    NULL,
    OtherCoveragesDeductible_Description    VARCHAR(255)    NULL,
    OtherCoveragesDeductibleAggregate_Dscr  VARCHAR(255)    NULL,
    OtherCoveragesDeductibleAggregate_Description VARCHAR(255) NULL,
    ContractualLiability_Dscr               VARCHAR(255)    NULL,
    ContractualLiability_Description        VARCHAR(255)    NULL,

    -- Computed date fields
    mth_pol_eff     INT     NULL,
    mth_pol_exp     INT     NULL,
    mth_cal_eff     INT     NULL,
    mth_cal_exp     INT     NULL,
    qtr_pol_eff     INT     NULL,
    qtr_pol_exp     INT     NULL,
    qtr_cal_eff     INT     NULL,
    qtr_cal_exp     INT     NULL,
    yr_pol          INT     NULL,
    yr_cal_eff      INT     NULL,
    term_year       FLOAT   NULL,
    Term_years      MONEY   NULL,
    prem_annual     MONEY   NULL,

    -- STT / adequacy columns
    STT             INT     NOT NULL DEFAULT 0,
    r_STT           INT     NOT NULL DEFAULT 0,
    rr_STT          INT     NOT NULL DEFAULT 0,
    rrr_STT         INT     NOT NULL DEFAULT 0,
    zz_STT          INT     NOT NULL DEFAULT 0,
    prem_tech_written       MONEY NULL,
    r_prem_tech_written     MONEY NULL,
    rr_prem_tech_written    MONEY NULL,
    rrr_prem_tech_written   MONEY NULL,
    zz_prem_tech_written    MONEY NULL,
    r_prem_written          MONEY NULL,
    rr_prem_written         MONEY NULL,
    rrr_prem_written        MONEY NULL,
    zz_prem_written         MONEY NULL,
    prem_tech_annual        MONEY NULL,
    r_prem_tech_annual      MONEY NULL,
    rr_prem_tech_annual     MONEY NULL,
    rrr_prem_tech_annual    MONEY NULL,
    zz_prem_tech_annual     MONEY NULL,
    r_prem_annual           MONEY NULL,
    rr_prem_annual          MONEY NULL,
    rrr_prem_annual         MONEY NULL,
    zz_prem_annual          MONEY NULL,
    r_adq_written           MONEY NULL,
    rr_adq_written          MONEY NULL,
    rrr_adq_written         MONEY NULL,
    zz_adq_written          MONEY NULL,
    r_adq_annual            MONEY NULL,
    rr_adq_annual           MONEY NULL,
    rrr_adq_annual          MONEY NULL,
    zz_adq_annual           MONEY NULL,
    r_adq_tech_written      MONEY NULL,
    rr_adq_tech_written     MONEY NULL,
    rrr_adq_tech_written    MONEY NULL,
    zz_adq_tech_written     MONEY NULL,
    r_adq_tech_annual       MONEY NULL,
    rr_adq_tech_annual      MONEY NULL,
    rrr_adq_tech_annual     MONEY NULL,
    zz_adq_tech_annual      MONEY NULL,
    r_padq_tech_written     NUMERIC(18,5) NULL,
    rr_padq_tech_written    NUMERIC(18,5) NULL,
    rrr_padq_tech_written   NUMERIC(18,5) NULL,
    zz_padq_tech_written    NUMERIC(18,5) NULL,
    r_padq_tech_annual      NUMERIC(18,5) NULL,
    rr_padq_tech_annual     NUMERIC(18,5) NULL,
    rrr_padq_tech_annual    NUMERIC(18,5) NULL,
    zz_padq_tech_annual     NUMERIC(18,5) NULL,
    r_blpadq_tech_written   NUMERIC(18,5) NULL,
    rr_blpadq_tech_written  NUMERIC(18,5) NULL,
    rrr_blpadq_tech_written NUMERIC(18,5) NULL,
    zz_blpadq_tech_written  NUMERIC(18,5) NULL,
    r_blpadq_tech_annual    NUMERIC(18,5) NULL,
    rr_blpadq_tech_annual   NUMERIC(18,5) NULL,
    rrr_blpadq_tech_annual  NUMERIC(18,5) NULL,
    zz_blpadq_tech_annual   NUMERIC(18,5) NULL,

    row_hash        BINARY(32)      NULL,
    created_date    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_test_DiaAPCovg PRIMARY KEY CLUSTERED (aim_row_id)
);

CREATE UNIQUE NONCLUSTERED INDEX UX_test_DiaAPCovg_NatKey
    ON dbo.test_DiaAPCovg (policy_id, policyimage_num, coverage_num, unit_num);

CREATE NONCLUSTERED INDEX IX_test_DiaAPCovg_PolicyDates
    ON dbo.test_DiaAPCovg (pol_num, date_pol_eff, date_pol_exp);
GO

-- ============================================================================
-- 5. test_diamond_data_aim
--    Natural key  : policy_id + policyimage_num + coverage_num + unit_num
--                   + coveragecode_id
--    Source proc  : run_test_Diamond_Apollo
--    NOTE: 166 columns — defined concisely; add any missing columns as needed.
-- ============================================================================
IF OBJECT_ID('dbo.test_diamond_data_aim') IS NOT NULL
    DROP TABLE dbo.test_diamond_data_aim;
GO

CREATE TABLE dbo.test_diamond_data_aim
(
    aim_row_id              BIGINT          IDENTITY(1,1) NOT NULL,

    PolicyType              VARCHAR(6)      NOT NULL,
    policy_id               INT             NOT NULL,
    policyimage_num         INT             NOT NULL,
    pol_num                 VARCHAR(40)     NULL,
    client_id               INT             NULL,
    pol_num_full_clean      BIGINT          NULL,
    date_pol_eff            DATE            NULL,
    date_pol_exp            DATE            NULL,
    Calendar_Effective_Date DATE            NULL,
    Calendar_Expiration_Date DATE           NULL,
    trans_date              DATETIME        NULL,
    accounting_date         DATETIME        NULL,
    received_date           DATETIME        NULL,
    pol_ed                  INT             NULL,
    insd_name_hist          VARCHAR(800)    NULL,
    state_insd              VARCHAR(6)      NULL,
    Entity_Type             VARCHAR(255)    NULL,
    [Company Code]          INT             NULL,
    company_code            VARCHAR(255)    NULL,
    policy_city             VARCHAR(75)     NULL,
    policy_county           VARCHAR(50)     NULL,
    state_risk              VARCHAR(6)      NULL,
    policy_state            VARCHAR(6)      NULL,
    policy_zip              VARCHAR(50)     NULL,
    coverage_num            INT             NULL,
    unit_num                INT             NULL,
    aircraft_num            INT             NULL,
    aircraft_display_num    INT             NULL,
    coveragecode_id         INT             NULL,
    coveragecode            VARCHAR(255)    NULL,
    covg_description        VARCHAR(255)    NULL,
    limit_dscr              VARCHAR(255)    NULL,
    limit_description       VARCHAR(255)    NULL,
    claim_limit_perperson   MONEY           NULL,
    claim_limit_peroccur    MONEY           NULL,
    claim_deductible        MONEY           NULL,
    claim_limit_dscr        VARCHAR(255)    NULL,
    claim_deduct_dscr       VARCHAR(255)    NULL,
    premium_diff_chg_written_calc   MONEY   NULL,
    premium_diff_chg_written        MONEY   NULL,
    premium_diff_chg_fullterm       MONEY   NULL,
    premium_fullterm        MONEY           NULL,
    premium_written         MONEY           NULL,
    prem_chg_fullterm       MONEY           NULL,
    prem_chg_written        MONEY           NULL,
    prem_annual             MONEY           NULL,
    premium_chg_annual      MONEY           NULL,
    comm_written            MONEY           NULL,
    transtype_id            INT             NULL,
    transtype               CHAR(2)         NULL,
    Transaction_type        VARCHAR(255)    NULL,
    [year]                  SMALLINT        NULL,
    tail_number             VARCHAR(255)    NULL,
    model                   VARCHAR(255)    NULL,
    hull_value              MONEY           NULL,
    hull_rate               NUMERIC(5,4)    NULL,
    model_year              SMALLINT        NULL,
    model_age               INT             NULL,
    make_dscr               VARCHAR(255)    NULL,
    seating_capacity_dscr   VARCHAR(255)    NULL,
    gear_type_dscr          VARCHAR(255)    NULL,
    wing_type_dscr          VARCHAR(255)    NULL,
    aircraftuse_dscr        VARCHAR(255)    NULL,
    SpecialUse_Code         INT             NULL,
    Min_Total_Hours         INT             NOT NULL DEFAULT 0,
    Min_ME_Total            INT             NOT NULL DEFAULT 0,
    Min_FW_TP               INT             NOT NULL DEFAULT 0,
    Min_FW_TJ               INT             NOT NULL DEFAULT 0,
    Min_RG                  INT             NOT NULL DEFAULT 0,
    Min_TW                  INT             NOT NULL DEFAULT 0,
    Min_RW_Total            INT             NOT NULL DEFAULT 0,
    Min_RW_Turb             INT             NOT NULL DEFAULT 0,
    Min_RW_Pist             INT             NOT NULL DEFAULT 0,
    Min_SEA_AMPH            INT             NOT NULL DEFAULT 0,
    Min_Glider              INT             NOT NULL DEFAULT 0,
    Min_Last_12             INT             NOT NULL DEFAULT 0,
    Min_Last_90             INT             NOT NULL DEFAULT 0,
    Min_MM_Hours            INT             NOT NULL DEFAULT 0,
    [Min_Last_MM_Training Date]     INT     NOT NULL DEFAULT 0,
    Min_12_Month_Hours      INT             NOT NULL DEFAULT 0,
    Min_Last_90_Day_Hours   INT             NOT NULL DEFAULT 0,
    max_Total_Hours         INT             NOT NULL DEFAULT 0,
    max_ME_Total            INT             NOT NULL DEFAULT 0,
    max_FW_TP               INT             NOT NULL DEFAULT 0,
    max_FW_TJ               INT             NOT NULL DEFAULT 0,
    max_RG                  INT             NOT NULL DEFAULT 0,
    max_TW                  INT             NOT NULL DEFAULT 0,
    max_RW_Total            INT             NOT NULL DEFAULT 0,
    max_RW_Turb             INT             NOT NULL DEFAULT 0,
    max_RW_Pist             INT             NOT NULL DEFAULT 0,
    max_SEA_AMPH            INT             NOT NULL DEFAULT 0,
    max_Glider              INT             NOT NULL DEFAULT 0,
    max_Last_12             INT             NOT NULL DEFAULT 0,
    max_Last_90             INT             NOT NULL DEFAULT 0,
    max_MM_Hours            INT             NOT NULL DEFAULT 0,
    [max_Last_MM_Training Date]     INT     NOT NULL DEFAULT 0,
    max_12_Month_Hours      INT             NOT NULL DEFAULT 0,
    max_Last_90_Day_Hours   INT             NOT NULL DEFAULT 0,
    max_birth_date          DATETIME        NULL,
    min_birth_date          DATETIME        NULL,
    min_age                 INT             NULL,
    max_age                 INT             NULL,
    pilot_count             INT             NULL,
    faano                   VARCHAR(255)    NULL,
    aircrafttype_id         INT             NULL,
    aircraft_type_description VARCHAR(255)  NULL,
    policytermversion_dscr  VARCHAR(255)    NULL,
    underwriter_name        VARCHAR(800)    NULL,
    agency_code             VARCHAR(255)    NULL,
    agencyproducer_code     VARCHAR(255)    NULL,
    agency_id               INT             NULL,
    agencyproducer_id       INT             NULL,
    agency_name             VARCHAR(255)    NULL,
    agencyproducer_name     VARCHAR(800)    NULL,
    agency_city             VARCHAR(75)     NULL,
    agency_state            VARCHAR(6)      NULL,
    policyterm_id           INT             NULL,
    premium_chg_fullterm    MONEY           NULL,
    premium_chg_written     MONEY           NULL,
    CSL_Occurance_Limit     VARCHAR(255)    NULL,
    CSL_Occurance_Limit_description     VARCHAR(255) NULL,
    CSL_Passenger_Limit     VARCHAR(255)    NULL,
    CSL_Passenger_Limit_description     VARCHAR(255) NULL,
    Med_Occurance_Limit     VARCHAR(255)    NULL,
    Med_Occurance_Limit_description     VARCHAR(255) NULL,
    Med_Passenger_Limit     VARCHAR(255)    NULL,
    Med_Passenger_Limit_description     VARCHAR(255) NULL,
    PD_Limit                VARCHAR(255)    NULL,
    PD_Limit_description    VARCHAR(255)    NULL,
    Coverage_group          VARCHAR(10)     NULL,
    adjustment_factor       NUMERIC(18,5)   NULL,
    adjustment_type         VARCHAR(6)      NOT NULL DEFAULT 'Dollar',
    premium_tech_annual     NUMERIC(18,5)   NULL,
    written_tech            NUMERIC(18,5)   NULL,
    airport_name            VARCHAR(255)    NULL,
    in_city_limits          BIT             NULL,
    is_coastal              BIT             NULL,
    state_abbr              CHAR(2)         NULL,
    storagetype_id          INT             NULL,
    zip                     VARCHAR(255)    NULL,
    model_code              VARCHAR(255)    NULL,
    [IFR-RW]                INT             NOT NULL DEFAULT 0,
    [RW-Heli]               INT             NOT NULL DEFAULT 0,
    AMEL                    INT             NOT NULL DEFAULT 0,
    [Airplane - SE]         INT             NOT NULL DEFAULT 0,
    Glider                  INT             NOT NULL DEFAULT 0,
    Rotorwing               INT             NOT NULL DEFAULT 0,
    [IFR-FW]                INT             NOT NULL DEFAULT 0,
    AMES                    INT             NOT NULL DEFAULT 0,
    ASES                    INT             NOT NULL DEFAULT 0,
    Instrument              INT             NOT NULL DEFAULT 0,
    Sport                   INT             NOT NULL DEFAULT 0,
    [Airplane - ME]         INT             NOT NULL DEFAULT 0,
    LTA                     INT             NOT NULL DEFAULT 0,
    [RW-Gyro]               INT             NOT NULL DEFAULT 0,
    ASEL                    INT             NOT NULL DEFAULT 0,
    in_motion_deductible    MONEY           NULL,
    not_in_motion_deductible MONEY          NULL,
    business_unit           VARCHAR(3)      NOT NULL DEFAULT 'AIM',
    reserving               VARCHAR(3)      NOT NULL,
    id_trans                VARCHAR(1)      NOT NULL DEFAULT '1',
    cncl_status             VARCHAR(2)      NOT NULL DEFAULT '',
    date_cncl               DATETIME        NULL,
    ind_pri_xs              VARCHAR(7)      NOT NULL DEFAULT 'Primary',
    date_book_val_max       DATETIME        NULL,
    cancelled_policyimage_num INT           NULL,

    row_hash        BINARY(32)      NULL,
    created_date    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated    DATETIME2(0)    NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_test_diamond_data_aim PRIMARY KEY CLUSTERED (aim_row_id)
);

CREATE UNIQUE NONCLUSTERED INDEX UX_test_diamond_data_aim_NatKey
    ON dbo.test_diamond_data_aim
    (policy_id, policyimage_num, coverage_num, unit_num, coveragecode_id);

CREATE NONCLUSTERED INDEX IX_test_diamond_data_aim_Pol
    ON dbo.test_diamond_data_aim (pol_num, date_pol_eff, reserving);
GO

-- ============================================================================
-- 6. test_aim_diamond_STT
--    Mirror of aim_diamond_STT — the rating adequacy view for Diamond aircraft.
--    This table is rebuilt from diamond_data_aim + rating tables each month;
--    TRUNCATE + INSERT strategy is used (full rebuild of rating output).
-- ============================================================================
IF OBJECT_ID('dbo.test_aim_diamond_STT') IS NOT NULL
    DROP TABLE dbo.test_aim_diamond_STT;
GO

-- Use SELECT INTO from live table to mirror schema exactly, then truncate.
SELECT TOP 0 * INTO dbo.test_aim_diamond_STT FROM dbo.aim_diamond_STT;

ALTER TABLE dbo.test_aim_diamond_STT
    ADD aim_row_id   BIGINT          IDENTITY(1,1) NOT NULL,
        row_hash     BINARY(32)      NULL,
        created_date DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0)    NOT NULL DEFAULT GETDATE();

ALTER TABLE dbo.test_aim_diamond_STT
    ADD CONSTRAINT PK_test_aim_diamond_STT PRIMARY KEY CLUSTERED (aim_row_id);

CREATE NONCLUSTERED INDEX IX_test_aim_diamond_STT_Pol
    ON dbo.test_aim_diamond_STT (policy_id, policyimage_num, unit_num);
GO

-- ============================================================================
-- 7. test_aim_STT
--    Mirror of aim_STT — the unified (Apollo + Diamond) STT table.
-- ============================================================================
IF OBJECT_ID('dbo.test_aim_STT') IS NOT NULL
    DROP TABLE dbo.test_aim_STT;
GO

SELECT TOP 0 * INTO dbo.test_aim_STT FROM dbo.aim_STT;

ALTER TABLE dbo.test_aim_STT
    ADD aim_row_id   BIGINT          IDENTITY(1,1) NOT NULL,
        row_hash     BINARY(32)      NULL,
        created_date DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0)    NOT NULL DEFAULT GETDATE();

ALTER TABLE dbo.test_aim_STT
    ADD CONSTRAINT PK_test_aim_STT PRIMARY KEY CLUSTERED (aim_row_id);

CREATE NONCLUSTERED INDEX IX_test_aim_STT_Pol
    ON dbo.test_aim_STT (policy_id, policyimage_num, covg);
GO

-- ============================================================================
-- 8. test_pnl_ep  /  test_pnl_wp
--    These are written by separate processes (not in the listed EOM SPs).
--    Included for completeness so validation can compare all backed-up tables.
-- ============================================================================
IF OBJECT_ID('dbo.test_pnl_ep') IS NOT NULL DROP TABLE dbo.test_pnl_ep;
GO
CREATE TABLE dbo.test_pnl_ep
(
    aim_row_id          BIGINT          IDENTITY(1,1) NOT NULL,
    polid               VARCHAR(70)     NULL,
    policyno            VARCHAR(70)     NULL,
    Treaty              VARCHAR(70)     NULL,
    poltype             VARCHAR(2)      NULL,
    aircrafttype        INT             NULL,
    begdate             DATE            NULL,
    effdate             DATE            NULL,
    exdate              DATE            NULL,
    billdate            DATE            NULL,
    Reserving           VARCHAR(4)      NOT NULL DEFAULT '',
    statid              VARCHAR(5)      NULL,
    faano               VARCHAR(70)     NULL,
    primaryuseid        INT             NULL,
    gear                VARCHAR(70)     NULL,
    wing                VARCHAR(70)     NULL,
    ppolid              INT             NULL,
    agreedvalue         INT             NULL,
    mth_earned          INT             NULL,
    primaryriskstate    VARCHAR(3)      NULL,
    ep                  FLOAT           NULL,
    row_hash            BINARY(32)      NULL,
    created_date        DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated        DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_test_pnl_ep PRIMARY KEY CLUSTERED (aim_row_id)
);

CREATE NONCLUSTERED INDEX IX_test_pnl_ep_NatKey
    ON dbo.test_pnl_ep (polid, mth_earned, Reserving);
GO

IF OBJECT_ID('dbo.test_pnl_wp') IS NOT NULL DROP TABLE dbo.test_pnl_wp;
GO
CREATE TABLE dbo.test_pnl_wp
(
    aim_row_id              BIGINT          IDENTITY(1,1) NOT NULL,
    polid                   INT             NOT NULL DEFAULT 0,
    [Policy No]             NVARCHAR(50)    NULL,
    primaryriskstate        NVARCHAR(4)     NULL,
    EfDate                  VARCHAR(12)     NULL,
    ExDate                  VARCHAR(12)     NULL,
    EfDateMonth             INT             NULL,
    EfDateYear              INT             NULL,
    BillDate                DATETIME        NULL,
    billmonth               INT             NULL,
    billyear                INT             NULL,
    StatID                  REAL            NULL,
    [Status]                NVARCHAR(50)    NULL,
    NEW_TO_MKT              INT             NULL,
    FAANo                   NVARCHAR(255)   NULL,
    TP_PRIMARYUSEID         INT             NULL,
    AircraftType            FLOAT           NULL,
    Gear                    NVARCHAR(6)     NULL,
    Wing                    NVARCHAR(50)    NULL,
    AircraftTypeName        NVARCHAR(255)   NULL,
    AircraftTypeNameDisplay NVARCHAR(289)   NULL,
    HullValue_AgreedValue   FLOAT           NULL,
    ACH_WP                  FLOAT           NULL,
    Liab_WP                 FLOAT           NULL,
    CommRate                FLOAT           NULL,
    ACH_Comm                FLOAT           NULL,
    Liab_Comm               FLOAT           NULL,
    TOT_WP                  FLOAT           NULL,
    PPolID                  INT             NULL,
    Treaty                  NVARCHAR(255)   NULL,
    ENTITY_TYPE             VARCHAR(11)     NOT NULL DEFAULT '',
    EntityName              NVARCHAR(25)    NULL,
    AGENCY                  NVARCHAR(250)   NULL,
    ProdId                  INT             NULL,
    agtCode                 NVARCHAR(10)    NULL,
    PRIORITY                VARCHAR(7)      NOT NULL DEFAULT '',
    SpecialUse_code         NVARCHAR(10)    NULL,
    row_hash                BINARY(32)      NULL,
    created_date            DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    last_updated            DATETIME2(0)    NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_test_pnl_wp PRIMARY KEY CLUSTERED (aim_row_id)
);

CREATE NONCLUSTERED INDEX IX_test_pnl_wp_NatKey
    ON dbo.test_pnl_wp (polid, billmonth, billyear);
GO

PRINT 'All test_ tables created successfully.';
GO
