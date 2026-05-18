USE [Pricing_AIM]
GO

/****** Object:  StoredProcedure [dbo].[run_Diamond_WP_EP]    Script Date: 5/18/2026 2:24:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[run_Diamond_WP_EP]
AS
BEGIN TRY	

declare @startTime datetime = getdate()

if object_ID('tempDB.dbo.#one') is not null drop table #one

DECLARE @Year INT, 
        @Month INT;

SELECT 
    @Year = DATEPART(YEAR, DATEADD(MONTH, -1, GETDATE())), -- Year of the previous Month
    @Month = DATEPART(MONTH, DATEADD(MONTH, -1, GETDATE())); -- Previous Month

SELECT 

'Diamond' [Platform],
@year  [Year],
@month [AcctPer],
(case
when @Month in (1,2,3) then 1
when @month in (4,5,6) then 2
when @month in (7,8,9) then 3
when @month in (10,11,12) then 4
else '' end) AcctQtr,

case WHEN cc.coveragecode_id IN (90006,90009,90048,90053,90056,90059,90060,90062,90069,90076,90077,90124,90151,90154,90157,90158,90038) THEN 'Aircraft Hull'
                             WHEN cc.coveragecode_id IN (90041,90045,90064,90065,90066,90103,90104,90156,90165,90166,90164,90020) THEN 'Aircraft Liability'
                             WHEN cc.CoverageCode_id IN (90039,90161,90167,90168,90170,90171,90172,90173,90174,90175,90176,90177,90179,
                                                      90180,90183,90184,90185,90186,90187,90188,90189,90190,90191,90192,90195,90196,21134) THEN 'Airport Liability' end as CoverageCodeGrouped
,cc.coveragecode
,cc.dscr ccdscr,
cc.coveragetype,

s.[state] [State],
cn.display_name Carrier,
p.policy_id,
EOPM.policy,
EOPM.policyimage_num,
EOPM.unit_num,
case when EOPM.renewal_ver = 1 then 'New' else 'Renew' end NewRenew,
lob.lobname PolicyTypeGroupDesc,
lob.lobname CoverageGroupDetailDesc1,
lob.lobname PolicyType,


round(SUM(isnull(EOPM.premium_written_mtd,0)),2) AS premium_written_mtd,


Round(SUM(isnull(EOPM.premium_earned_mtd,0)),2) AS premium_earned_mtd,
Round(SUM(isnull(EOPM.premium_unearned,0)),2) AS premium_unearned,
Round(SUM(isnull(EOPM.premium_unearned_priormonth,0)),2) AS premium_unearned_priormonth,
Round(SUM(isnull(EOPM.premium_written_ytd,0)),2) AS premium_written,
Round(SUM(isnull(EOPM.premium_unearned,0)),2)  - Round(SUM(isnull(EOPM.premium_unearned_priormonth,0)),2) UepPriorMinusCurent,
eopM.eff_date EffectiveDate,
eopM.exp_date ExpirationDate,
majorperil,
pt.months,
pi.ratingversion_id


into #one

FROM [AHI-S06].Diamond.dbo.EOPMonthlyPremiums EOPM WITH(NOLOCK)
INNER JOIN [AHI-S06].Diamond.dbo.[Version] V WITH(NOLOCK) ON EOPM.version_id = V.version_id
inner join [AHI-S06].Diamond.dbo.Policy p on EOPM.policy_id = p.policy_id
left join [AHI-S06].Diamond.dbo.policyimage pi on pi.policy_id=p.policy_id and pi.policyimage_num= EOPM.policyimage_num 
INNER JOIN [AHI-S06].Diamond.dbo.CompanyStateLOB CSL WITH(NOLOCK)	ON CSL.companystatelob_id = V.companystatelob_id
INNER JOIN [AHI-S06].Diamond.dbo.CompanyState CS WITH(NOLOCK) ON CS.companystate_id = CSL.companystate_id
INNER JOIN [AHI-S06].Diamond.dbo.[State] S WITH(NOLOCK) ON S.state_id = CS.state_id
INNER JOIN [AHI-S06].Diamond.dbo.CompanyLOB CL WITH(NOLOCK) ON CL.companylob_id = CSL.companylob_id
INNER JOIN [AHI-S06].Diamond.dbo.Lob LOB WITH(NOLOCK) ON CL.lob_id = LOB.lob_id
INNER JOIN [AHI-S06].Diamond.dbo.CompanyNameLink CNL WITH (NOLOCK) ON CNL.company_id = CS.company_id AND CNL.company_id = CL.company_id
INNER JOIN [AHI-S06].Diamond.dbo.[Name] CN WITH(NOLOCK) ON CN.name_id = CNL.name_id
INNER join [AHI-S06].Diamond.dbo.CoverageCode cc on EOPM.coveragecode_id = cc.coveragecode_id
INNER JOIN [AHI-S06].Diamond.dbo.ASL asl on EOPM.asl_id = asl.asl_id
inner join [AHI-S06].Diamond.dbo.MajorPeril maj on eopm.majorperil_id = maj.majorperil_id
--left join [AHI-S06].Diamond.dbo.AgencyActivity AA on eopm.policy_id = AA.policy_id 
left join [AHI-S06].Diamond.dbo.vBillingAccountData VBA on eopm.policy_id = vba.policy_id
left join [AHI-S06].Diamond.dbo.BillingAcctReceivable BAC on eopm.policy_id = bac.policy_id and bac.renewal_ver = 2
left join [AHI-S06].Diamond.dbo.vAgencyCommission_Info vac on vac.companystatelob_id=csl.companystatelob_id and vac.agency_id=VBA.agency_id and pi.eff_date between vac.start_date and (case when vac.end_date='1800-01-01' then '2100-12-31' else vac.end_date end) and (case when eopm.renewal_ver=1 then 'New Business' else 'Renewal' end)=vac.description_detailtype
LEFT JOIN [AHI-S06].Diamond.dbo.PolicyTerm pt ON pt.policyterm_id = pi.policyterm_id
where eopm.month= @month and eopm.year= @Year and eopm.lob_id in (30,31)
		
GROUP BY 
	EOPM.policy,
	EOPM.majorperil_id,
	EOPM.asl_id,
	V.company_id,
	V.state_id,
	V.lob_id,
	s.state,
	display_name,
	p.policy_id,
	EOPM.policyimage_num,
	EOPM.unit_num,
	eopm.policy,
	EOPM.renewal_ver,
	lob.lobname,
	cc.coveragecode_id,
	cc.coveragecode,
	cc.dscr,
	cc.coveragetype,
	asl.asl,
	vac.rate,
	EOPM.eff_date,
	EOPM.exp_date,
	maj.description,
	--aa.rate,
	vba.billingpayplan_dscr,
	vba.billingpayplan_id,
	bac.totalcash,
	maj.majorperil,
	pt.months,
	pi.ratingversion_id


-- add in to the existing table
insert into Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy] select * from #one 

-- Delete from Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy] where year = 2023 and AcctPer =9

-- check the premium for aircraft
select sum(premium_written_mtd) from Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy]
where PolicyType = 'Aircraft'
select policy, sum(premium_written_mtd) from Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy]
where PolicyType = 'Aircraft'
group by policy order by policy

-- check the premium for airport
select sum(premium_written_mtd) from Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy]
where PolicyType = 'Airport'

--Delete from Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy]
--where AcctPer = 01 and Year = 2024

DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID)
exec UPDATE_QUERY_TIMES @PROC_NAME, @StartTime
 
END TRY 
BEGIN CATCH 
SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE 
END CATCH
GO


