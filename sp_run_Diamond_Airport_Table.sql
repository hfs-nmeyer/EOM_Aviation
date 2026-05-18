USE [Pricing_AIM]
GO

/****** Object:  StoredProcedure [dbo].[run_Diamond_Airport_Table]    Script Date: 5/18/2026 2:29:26 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[run_Diamond_Airport_Table]
AS
BEGIN TRY	

declare @startTime datetime = getdate()

if OBJECT_ID('tempdb.dbo.#date_chks') is not null drop table #date_chks
create table #date_chks	(	date_pol_eff_min date,				--	inclusive
							date_book_val_min date,				--	inclusive
							date_book_val_max datetime,         --	exclusive
							date_book date)				        --  exclusive
							

insert into #date_chks	(date_pol_eff_min, date_book_val_min,	date_book_val_max,   date_book)
				values	('2001-01-01',		'2000-01-01',		getdate(),	CONVERT(char(10), DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1), 120))
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#policyimage') is not null drop table #policyimage
select
	ROW_NUMBER() over(Partition by policy_id, premium_diff_chg_written, trans_remark order by policyimage_num) repeat_transaction_count
	,*
into #policyimage
from [AHI-S06].[Diamond].[dbo].policyimage
where (policy like 'AP%' or policy like 'HLMAP%'or policy like 'HDIAP%') and policystatuscode_id <> 12 and policystatuscode_id <> 4 and policystatuscode_id <> 13 and policystatuscode_id <> 8 and policystatuscode_id <> 5 and policystatuscode_id <> 6



if OBJECT_ID('tempdb.dbo.#Airport_pol00') is not null drop table #Airport_pol00
select distinct policy_id, policyimage_num into #Airport_pol00 FROM [AHI-S06].[Diamond].[dbo].[airport] 
 
if OBJECT_ID('tempdb.dbo.#Airport_pol') is not null drop table #Airport_pol
select a.policy_id, 
	a.policyimage_num 
	,b.repeat_transaction_count
into #Airport_pol 
FROM #Airport_pol00 as a
inner join #policyimage as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num

---------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#airport') is not null drop table #airport 
select * into #airport from [AHI-S06].[Diamond].[dbo].[airport] 
where detailstatuscode_id = 1

----------------------------------------------------------------------------------------
--Build coverage table

select * into #covg00 from openquery([AHI-S06] , 'select a.policy_id
,a.policyimage_num
,a.coverage_num
,a.unit_num
,a.eff_date
,a.exp_date
,a.premium_fullterm
,a.premium_written
,a.premium_previous_written
,a.premium_chg_written
,a.premium_prev_chg_written
,a.premium_diff_chg_written
,a.coveragecode_id
,a.subcoveragecode_id
,a.coveragelimit_id
,a.manuallimitamount
,a.calc
,a.read_only
,a.manualdate
,a.checkbox
,a.detailstatuscode_id
,a.added_date
,a.pcadded_date
,a.apply_to_written_premium
,a.premium_chg_fullterm
,a.premium_prev_chg_fullterm
,a.premium_diff_chg_fullterm
,a.minimum_liability_premium_fullterm
,a.scheduleditems
,a.onset_for_reapplied
,a.offset_for_reapplied
,a.offset_for_prev_image
,a.onset_for_current
,a.ftp_onset_for_reapplied
,a.ftp_offset_for_reapplied
,a.ftp_offset_for_prev_image
,a.ftp_onset_for_current
,a.exposure
,a.premium_guaranteed_rate_period
,a.premium_annual
,a.premium_chg_annual
,a.premium_prev_chg_annual
,a.premium_diff_chg_annual
,a.manuallimit_included
,a.manuallimit_increased
,a.dscr
,a.sequence_num
,a.deductible
,a.original_cost
,a.deductible_id
,a.last_modified_date
,a.override_fully_earned
,a.asl_id
,a.packagepart_num
,a.premium_prevaudit_written
,a.premium_previous_written_shortrate
,a.deleted_policyimage_num
,a.added_policyimage_num
,a.majorperil_id
,a.package_sync_identifier 
from diamond.dbo.coverage a

left join [Diamond].[dbo].policyimage as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num
where (b.policy like ''AP%'' or b.policy like ''HLMAP%'' or b.policy like ''HDIAP%'') and b.policystatuscode_id <> 12 and b.policystatuscode_id <> 4 and b.policystatuscode_id <> 13 and b.policystatuscode_id <> 8 and b.policystatuscode_id <> 5 and b.policystatuscode_id <> 6 
'
 ) 

if OBJECT_ID('tempdb.dbo.#covg01') is not null drop table #covg01
select
	policy_id
	,policyimage_num
	,unit_num
	,coveragecode_id
	,count(coveragecode_id) as coverage_count
into #covg01
from #covg00
group by 
	policy_id
	,policyimage_num
	,unit_num
	,coveragecode_id

if OBJECT_ID('tempdb.dbo.#covg02') is not null drop table #covg02
select
	a.*
	,b.coverage_count
into #covg02
from #covg00 as a
left join #covg01 as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num and a.unit_num = b.unit_num and a.coveragecode_id = b.coveragecode_id

Delete from #covg02 where premium_written = 0 and coverage_count > 1

----------------------------------------------------------------------------------------
--Policy Limit
if OBJECT_ID('tempdb.dbo.#PL') is not null drop table #PL
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PL
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90167

----------------------------------------------------------------------------------------
--BI and PD Liability
if OBJECT_ID('tempdb.dbo.#BIPD') is not null drop table #BIPD
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #BIPD
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90168

----------------------------------------------------------------------------------------
--Airport Operations Occurrence
if OBJECT_ID('tempdb.dbo.#AOO') is not null drop table #AOO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #AOO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90161

----------------------------------------------------------------------------------------
--Airport Operations Per Person
if OBJECT_ID('tempdb.dbo.#AOPP') is not null drop table #AOPP
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #AOPP
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90170 

----------------------------------------------------------------------------------------
--Personal Injury Occurrence
if OBJECT_ID('tempdb.dbo.#PIO') is not null drop table #PIO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PIO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90186 

----------------------------------------------------------------------------------------
--Personal Injury Aggregate
if OBJECT_ID('tempdb.dbo.#PIA') is not null drop table #PIA
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PIA
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90187

----------------------------------------------------------------------------------------
--Fire Legal Liability
if OBJECT_ID('tempdb.dbo.#FLL') is not null drop table #FLL
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #FLL
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90183

----------------------------------------------------------------------------------------
--Hangarkeeper's Aircraft
if OBJECT_ID('tempdb.dbo.#HKA') is not null drop table #HKA
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #HKA
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90184

----------------------------------------------------------------------------------------
--Hangarkeeper's Occurrence
if OBJECT_ID('tempdb.dbo.#HKO') is not null drop table #HKO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #HKO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90185

----------------------------------------------------------------------------------------
--Advertising Liability Occurrence
if OBJECT_ID('tempdb.dbo.#ALO') is not null drop table #ALO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #ALO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90188

----------------------------------------------------------------------------------------
--Advertising Liability Aggregate
if OBJECT_ID('tempdb.dbo.#ALA') is not null drop table #ALA
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #ALA
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90189

----------------------------------------------------------------------------------------
--Premises Medical Occurrence
if OBJECT_ID('tempdb.dbo.#PMO') is not null drop table #PMO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PMO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90190

----------------------------------------------------------------------------------------
--Premises Medical Per Person
if OBJECT_ID('tempdb.dbo.#PMPP') is not null drop table #PMPP
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PMPP
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90191

----------------------------------------------------------------------------------------
--Premises Medical Aggregate
if OBJECT_ID('tempdb.dbo.#PMA') is not null drop table #PMA
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PMA
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90192

----------------------------------------------------------------------------------------
--Product and Completed Operations Occurrence
if OBJECT_ID('tempdb.dbo.#PCOO') is not null drop table #PCOO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PCOO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90171

----------------------------------------------------------------------------------------
--Product and Completed Operations Per Person
if OBJECT_ID('tempdb.dbo.#PCOPP') is not null drop table #PCOPP
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PCOPP
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90172

----------------------------------------------------------------------------------------
--Product and Completed Operations Aggregate
if OBJECT_ID('tempdb.dbo.#PCOA') is not null drop table #PCOA
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PCOA
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90173 

----------------------------------------------------------------------------------------
--Repair and Services
if OBJECT_ID('tempdb.dbo.#RS') is not null drop table #RS
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #RS
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90174

----------------------------------------------------------------------------------------
--Excl. Eng and Prop Overhaul
if OBJECT_ID('tempdb.dbo.#EEPO') is not null drop table #EEPO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #EEPO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90175 

----------------------------------------------------------------------------------------
--Fixed Wing Only
if OBJECT_ID('tempdb.dbo.#FWO') is not null drop table #FWO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #FWO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90176

----------------------------------------------------------------------------------------
--Fuel/Lubricants
if OBJECT_ID('tempdb.dbo.#FL') is not null drop table #FL
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #FL
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90177

----------------------------------------------------------------------------------------
--Used Aircraft Sales
if OBJECT_ID('tempdb.dbo.#UAS') is not null drop table #UAS
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #UAS
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90179

----------------------------------------------------------------------------------------
--Parts Sales
if OBJECT_ID('tempdb.dbo.#PS') is not null drop table #PS
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PS
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90180

----------------------------------------------------------------------------------------
--Miscellaneous
if OBJECT_ID('tempdb.dbo.#MIS') is not null drop table #MIS
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #MIS
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90182

----------------------------------------------------------------------------------------
--Hangarkeeper's Deductible
if OBJECT_ID('tempdb.dbo.#HKD') is not null drop table #HKD
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #HKD
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90195

----------------------------------------------------------------------------------------
--Certified Acts of Terrorism Premium
if OBJECT_ID('tempdb.dbo.#CATP') is not null drop table #CATP
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #CATP
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90039

----------------------------------------------------------------------------------------
--Liquor Liability
if OBJECT_ID('tempdb.dbo.#LL') is not null drop table #LL
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #LL
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 21134

----------------------------------------------------------------------------------------
--Policy Level State Tax
if OBJECT_ID('tempdb.dbo.#PLST') is not null drop table #PLST
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PLST
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 10035

----------------------------------------------------------------------------------------
--Policy Level County Tax
if OBJECT_ID('tempdb.dbo.#PLCT') is not null drop table #PLCT
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PLCT
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 10036

----------------------------------------------------------------------------------------
--AI Premium
if OBJECT_ID('tempdb.dbo.#AP') is not null drop table #AP
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #AP
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90103

----------------------------------------------------------------------------------------
--AI Premium Override
if OBJECT_ID('tempdb.dbo.#APO') is not null drop table #APO
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #APO
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90104

----------------------------------------------------------------------------------------
--Premium Type
if OBJECT_ID('tempdb.dbo.#PT') is not null drop table #PT
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #PT
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90156

----------------------------------------------------------------------------------------
--AI Premium Override Checkbox
if OBJECT_ID('tempdb.dbo.#APOC') is not null drop table #APOC
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #APOC
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90166

----------------------------------------------------------------------------------------
--New Aircraft Sales
if OBJECT_ID('tempdb.dbo.#NAS') is not null drop table #NAS
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #NAS
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90178

----------------------------------------------------------------------------------------
--Restaurant/Food/Vending
if OBJECT_ID('tempdb.dbo.#RFV') is not null drop table #RFV
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #RFV
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90181 

----------------------------------------------------------------------------------------
--Other Coverages Deductible
if OBJECT_ID('tempdb.dbo.#OCD') is not null drop table #OCD
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #OCD
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90193

----------------------------------------------------------------------------------------
--Other Coverages Deductible: Aggregate
if OBJECT_ID('tempdb.dbo.#OCDA') is not null drop table #OCDA
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #OCDA
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90194

----------------------------------------------------------------------------------------
--Contractual Liability
if OBJECT_ID('tempdb.dbo.#CL') is not null drop table #CL
SELECT ap.policy_id
	,ap.policyimage_num
	,air.airport_num
	--,air.premium_fullterm
	--,air.premium_written
	--,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #CL
FROM #Airport_pol ap
left join #airport air on ap.policy_id = air.policy_id and ap.policyimage_num = air.policyimage_num
LEFT JOIN #covg02 a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].diamond.dbo.coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90196

--select * from #CL
--where policy_id = 36627377
--select * from [AHI-S06].[Diamond].[dbo].coverage
--where policy_id = 36627377 and coveragecode_id = 90196
 
----------------------------------------------------------------------------------------
 --Insured
 if OBJECT_ID('tempdb.dbo.#InsuredandCompany') is not null drop table #InsuredandCompany
 select 
	a.policy_id
	,a.policyimage_num
	,b.display_name as Insured
	,d.state as [State Insured]
	--,e.companylob_id
	--,e.lob_id
	--,e.lobname
	--,e.commercial_name1 as Company
	--,e.company_id as [Company Code]
into #InsuredandCompany
from #Airport_pol as a
left join [AHI-S06].diamond.dbo.vPolicyImageXML xml on a.policy_id = xml.policy_id and a.policyimage_num = xml.policyimage_num
left join [AHI-S06].diamond.dbo.version v on xml.version_id = v.version_id
left join [AHI-S06].diamond.dbo.name as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num
left join [AHI-S06].diamond.dbo.address as c on a.policy_id = c.policy_id and a.policyimage_num = c.policyimage_num
left join [AHI-S06].diamond.dbo.state as d on c.state_id = d.state_id
--left join [AHI-S06].Diamond.[dbo].[vCompanyStateLOB] e on v.companystatelob_id = e.companystatelob_id
where b.nameaddresssource_id = 3 and c.nameaddresssource_id = 3


if OBJECT_ID('tempdb.dbo.#Company') is not null drop table #Company
 select 
	a.policy_id
	,a.policyimage_num
	,csl.commercial_name1 as Company
	,csl.company_id as [Company Code]
into #Company
from #Airport_pol as a
left join [AHI-S06].diamond.dbo.policyimage p on a.policy_id = p.policy_id and a.policyimage_num = p.policyimage_num
left join [AHI-S06].diamond.dbo.version ver on p.version_id = ver.version_id
left join [AHI-S06].diamond.dbo.vCompanyStateLOB csl on ver.companystatelob_id = csl.companystatelob_id
where csl.lobname = 'Airport' 
group by 
	a.policy_id
	,a.policyimage_num
	,csl.commercial_name1
	,csl.company_id


--agency_city, agency_state
if OBJECT_ID('tempdb.dbo.#agency') is not null drop table #agency
select 
	air.policy_id
	,air.policyimage_num
	,p.agency_id
	,a.nameaddresssource_id
	,a.address_id
	,b.city as agency_city
	,c.state as agency_state
into #agency 
from #Airport_pol as air
left join [AHI-S06].diamond.dbo.vPolicyImageXML as p on air.policy_id = p.policy_id and air.policyimage_num = p.policyimage_num
left join [AHI-S06].[Diamond].[dbo].[AgencyAddressLink] as a on p.agency_id = a.agency_id
left join [AHI-S06].[Diamond].[dbo].[Address] as b on a.address_id = b.address_id
left join [AHI-S06].diamond.dbo.state as c on b.state_id = c.state_id
where a.nameaddresssource_id = 8
group by 
	air.policy_id
	,air.policyimage_num
	,p.agency_id
	,a.nameaddresssource_id
	,a.address_id
	,b.city
	,c.state


--policy city, policy county, policy state, policy zip
if OBJECT_ID('tempdb.dbo.#PolicyAddress') is not null drop table #PolicyAddress
select
	air.policy_id
	,air.policyimage_num
	,b.nameaddresssource_id
	,b.city as policy_city
	,b.county as policy_county
	,b.zip as policy_zip
	,c.state as policy_state
into #PolicyAddress
from #Airport_pol as air
left join [AHI-S06].diamond.dbo.PolicyImage as a on air.policy_id = a.policy_id and air.policyimage_num = a.policyimage_num
left join [AHI-S06].Diamond.dbo.Address as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num
left join [AHI-S06].[Diamond].[dbo].state as c on b.state_id = c.state_id
where b.nameaddresssource_id = 3
group by
	air.policy_id
	,air.policyimage_num
	,b.nameaddresssource_id
	,b.city
	,b.county
	,b.zip
	,c.state


--Entity_Type
if OBJECT_ID('tempdb.dbo.#Entity') is not null drop table #Entity
select
	air.policy_id
	,air.policyimage_num
	,a.entitytype_id
	,b.dscr as Entity_Type
into #Entity
from #Airport_pol as air
left join [AHI-S06].Diamond.dbo.Name as a on air.policy_id = a.policy_id and air.policyimage_num = a.policyimage_num
left join [AHI-S06].Diamond.dbo.EntityType as b on a.entitytype_id = b.entitytype_id
where a.nameaddresssource_id = 3
group by 
	air.policy_id
	,air.policyimage_num
	,a.entitytype_id
	,b.dscr


-- underwriter name
if OBJECT_ID('tempdb.dbo.#underwriter') is not null drop table #underwriter
select
	air.policy_id
	,air.policyimage_num
	,a.underwriter_users_id
	,b.display_name as underwriter_name
into #underwriter
from #Airport_pol as air
left join [AHI-S06].[Diamond].[dbo].[policyimage] as a on a.policy_id = air.policy_id and air.policyimage_num = a.policyimage_num
left join [AHI-S06].[Diamond].[dbo].[vusers] as b on a.underwriter_users_id = b.users_id
group by 
	air.policy_id
	,air.policyimage_num
	,a.underwriter_users_id
	,b.display_name
	 
----------------------------------------------------------------------------------------
--Put together

if OBJECT_ID('tempdb.dbo.#DiaAP01') is not null drop table #DiaAP01
select
	'Diamond' as system
	,'Airport' as line
	,case when pi.policy like '%QAP%' or pi.policy like '%QHLMAP%' or pi.policy like '%QHDIAP%' then 'Quote'
			when pi.policy like '%AP%' or pi.policy like '%HLMAP%' or pi.policy like '%HDIAP%'then 'Policy'
			end as Policy_Type
	,pol.client_id
	,pi.policy as pol_num
	,pi.renewal_ver as pol_ed
	,ap.policy_id
	,ap.policyimage_num
	,'APL' as reserving
	,a.unit_num
	,air.airport_display_num
	,lk.airport_code faano
	,lk.airport_name
	,lk.city as airport_city
	,lk.county as airport_county
	,lk.state_abbr as airport_state
	,lk.zip
	,lk.in_city_limits
	,lk.is_coastal
	,lk.is_conforming
	,air.airportcategorytype_id
	,ct.dscr as airportcategorytype
	,air.airportbusinesstype_id
	,bt.dscr as airportbusinesstype
	,air.storagetype_id
	,st.dscr as storagetype
	,IAC.Insured as insd_name_hist
	,IAC.[State Insured] as state_insd
	,en.Entity_Type
	,comp.[Company Code]
	,comp.[Company] as company_code
	,uw.underwriter_name
	,padd.policy_city
	,padd.policy_county
	,padd.policy_state
	,padd.policy_zip
	,xml.policytermversion_dscr
	,xml.agency_code
	,xml.agency_id
	,xml.agency_name
	,xml.agencyproducer_code
	,xml.agencyproducer_id
	,xml.agencyproducer_name
	,ag.agency_city
	,ag.agency_state
	,pi.eff_date as date_pol_eff
	,pi.exp_date as date_pol_exp
	,pi.teff_date as Calendar_Effective_Date
	,pi.texp_date as Calendar_Expiration_Date
	,case when pol.cancel_date = '1800-01-01' then '2999-12-31' else pol.cancel_date end date_cncl
	,pi.trans_date
	,pi.accounting_date
	,pi.received_date
	,pi.transtype_id
	,xml.transtype_dscr as transaction_type
	,a.coverage_num
	,a.coveragecode_id
	,b.coveragecode
	,b.dscr as covg_description
	,a.premium_diff_chg_written as old_premium_diff_chg_written
	,case when ap.repeat_transaction_count = 1 then a.premium_diff_chg_written
			when ap.repeat_transaction_count > 1 then 0
			end premium_written
	,a.premium_fullterm as premt_fullterm
	,a.premium_written as premt_written
	,a.premium_chg_fullterm as prem_chg_fullterm
	,a.premium_chg_written as prem_chg_written
	,a.premium_annual as premt_annual
	,a.premium_chg_annual as prem_chg_annual
	,AA.commission as comm_written
	,a.coveragelimit_id
	,cl.limit_dscr
	,cl.claim_limit_perperson
	,cl.claim_limit_peroccur
	,cl.claim_deductible
	,cl.claim_limit_dscr
	,cl.claim_deduct_dscr
	,PL.limit_dscr as PolicyLimit_Dscr
	,PL.limit_description as PolicyLimit_Description
	,BIPD.limit_dscr as BIPD_Dscr
	,BIPD.limit_description as BIPD_Descrption
	,AOO.limit_dscr as AirportOperationsOccurence_Dscr
	,AOO.limit_description as AirportOperationsOccurence_Description
	,AOPP.limit_dscr as AirportOperationsPerPerson_Dscr
	,AOPP.limit_description as AirportOperationsPerPerson_Description
	,PIO.limit_dscr as PersonalInjuryOccurrence_Dscr
	,PIO.limit_description as PersonalInjuryOccurrence_Description
	,PIA.limit_dscr as PersonalInjuryAggregate_Dscr
	,PIA.limit_description as PersonalInjuryAggregate_Description
	,FLL.limit_dscr as FireLegalLiability_Dscr
	,FLL.limit_description as FireLegalLiability_Description
	,HKA.limit_dscr as HangarkeepersAircraft_Dscr
	,HKA.limit_description as HangarkeepersAircraft_Description
	,HKO.limit_dscr as HangarkeepersOccurrence_Dscr
	,HKO.limit_description as HangarkeepersOccurrence_Description
	,ALO.limit_dscr as AdvertisingLiabilityOccurrence_Dscr
	,ALO.limit_description as AdvertisingLiabilityOccurrence_Description
	,ALA.limit_dscr as AdvertisingLiabilityAggregate_Dscr
	,ALA.limit_description as AdvertisingLiabilityAggregate_Description
	,PMO.limit_dscr as PremisesMedicalOccurrence_Dscr
	,PMO.limit_description as PremisesMedicalOccurrence_Description
	,PMPP.limit_dscr as PremisesMedicalPerPerson_Dscr
	,PMPP.limit_description as PremisesMedicalPerPerson_Description
	,PMA.limit_dscr as PremisesMedicalAggregate_Dscr
	,PMA.limit_description as PremisesMedicalAggregate_Description
	,PCOO.limit_dscr as ProductandCompletedOperationsOccurrence_Dscr
	,PCOO.limit_description as ProductandCompletedOperationsOccurrence_Description
	,PCOPP.limit_dscr as ProductandCompletedOperationsPerPerson_Dscr
	,PCOPP.limit_description as ProductandCompletedOperationsPerPerson_Description
	,PCOA.limit_dscr as ProductandCompletedOperationsAggregate_Dscr
	,PCOA.limit_description as ProductandCompletedOperationsAggregate_Description
	,RS.limit_dscr as RepairandServices_Dscr
	,RS.limit_description as RepairandServices_Description
	,EEPO.limit_dscr as ExclEngandPropOverhaul_Dscr
	,EEPO.limit_description as ExclEngandPropOverhaul_Description
	,FWO.limit_dscr as FixedWingOnly_Dscr
	,FWO.limit_description as FixedWingOnly_Description
	,FL.limit_dscr as FuelLubricants_Dscr
	,FL.limit_description as FuelLubricants_Description
	,UAS.limit_dscr as UsedAircraftSales_Dscr
	,UAS.limit_description as UsedAircraftSales_Description
	,PS.limit_dscr as PartsSales_Dscr
	,PS.limit_description as PartsSales_Description
	,MIS.limit_dscr as Miscellaneous_Dscr
	,MIS.limit_description as Miscellaneous_Description
	,HKD.limit_dscr as HangarkeepersDeductible_Dscr
	,HKD.limit_description as HangarkeepersDeductible_Description
	,CATP.limit_dscr as CertifiedActsofTerrorismPremium_Dscr
	,CATP.limit_description as CertifiedActsofTerrorismPremium_Description
	,LL.limit_dscr as LiquorLiability_Dscr
	,LL.limit_description as LiquorLiability_Description
	,PLST.limit_dscr as PolicyLevelStateTax_Dscr
	,PLST.limit_description as PolicyLevelStateTax_Description
	,PLCT.limit_dscr as PolicyLevelCountyTax_Dscr
	,PLCT.limit_description as PolicyLevelCountyTax_Description
	,APP.limit_dscr as AIPremium_Dscr
	,APP.limit_description as AIPremium_Description
	,APO.limit_dscr as AIPremiumOverride_Dscr
	,APO.limit_description as AIPremiumOverride_Description
	,PT.limit_dscr as PremiumType_Dscr
	,PT.limit_description as PremiumType_Description
	,APOC.limit_dscr as AIPremiumOverrideCheckbox_Dscr
	,APOC.limit_description as AIPremiumOverrideCheckbox_Description
	,NAS.limit_dscr as NewAircraftSales_Dcsr
	,NAS.limit_description as NewAircraftSales_Description
	,RFV.limit_dscr as RestaurantFoodVending_Dscr
	,RFV.limit_description as RestaurantFoodVending_Description
	,OCD.limit_dscr as OtherCoveragesDeductible_Dscr
	,OCD.limit_description as OtherCoveragesDeductible_Description
	,OCDA.limit_dscr as OtherCoveragesDeductibleAggregate_Dscr
	,OCDA.limit_description as OtherCoveragesDeductibleAggregate_Description
	,CLiab.limit_dscr as ContractualLiability_Dscr
	,CLiab.limit_description as ContractualLiability_Description
into #DiaAP01
from #Airport_pol as ap
left join #covg02 a on ap.policy_id = a.policy_id and ap.policyimage_num = a.policyimage_num --[AHI-S06].diamond.dbo.Coverage
left join #airport air on ap.policy_id = air.policy_id --[AHI-S06].diamond.dbo.Airport
	AND ap.policyimage_num = air.policyimage_num
	AND a.unit_num = air.airport_display_num
LEFT JOIN [AHI-S06].diamond.dbo.coveragecode b ON a.coveragecode_id = b.coveragecode_id
left join [AHI-S06].[Diamond].[dbo].policy pol on a.policy_id = pol.policy_id
left join [AHI-S06].diamond.dbo.policyimage pi on pi.policy_id = ap.policy_id
	AND pi.policyimage_num = ap.policyimage_num
left join [AHI-S06].[Diamond].[dbo].[AirportLookup] lk on air.airportlookup_id = lk.airportlookup_id
left join [AHI-S06].[Diamond].[dbo].[AirportCategoryType] ct on ct.airportcategorytype_id = air.airportcategorytype_id
left join [AHI-S06].[Diamond].[dbo].[AirportBusinessType] bt on bt.airportbusinesstype_id = air.airportbusinesstype_id
left join [AHI-S06].diamond.dbo.storagetype st on air.storagetype_id = st.storagetype_id
left join [AHI-S06].diamond.dbo.vPolicyImageXML xml on xml.policy_id = ap.policy_id
	AND xml.policyimage_num = ap.policyimage_num
left join [AHI-S06].diamond.dbo.coveragelimit cl on cl.coveragelimit_id = a.coveragelimit_id
left join #InsuredandCompany IAC on IAC.policy_id = ap.policy_id and IAC.policyimage_num = ap.policyimage_num
left join #agency ag on ag.policy_id = ap.policy_id and ag.policyimage_num = ap.policyimage_num
left join #PolicyAddress padd on padd.policy_id = ap.policy_id and padd.policyimage_num = ap.policyimage_num
left join #Entity en on en.policy_id = ap.policy_id and en.policyimage_num = ap.policyimage_num
left join #PL pl on pl.policy_id = ap.policy_id and pl.policyimage_num = ap.policyimage_num and pl.airport_num = a.unit_num
left join #BIPD BIPD on BIPD.policy_id = ap.policy_id and BIPD.policyimage_num = ap.policyimage_num and BIPD.airport_num = a.unit_num
left join #AOO AOO on AOO.policy_id = ap.policy_id and AOO.policyimage_num = ap.policyimage_num and AOO.airport_num = a.unit_num
left join #AOPP AOPP on AOPP.policy_id = ap.policy_id and AOPP.policyimage_num = ap.policyimage_num and AOPP.airport_num = a.unit_num
left join #PIO PIO on PIO.policy_id = ap.policy_id and PIO.policyimage_num = ap.policyimage_num and PIO.airport_num = a.unit_num
left join #PIA PIA on PIA.policy_id = ap.policy_id and PIA.policyimage_num = ap.policyimage_num and PIA.airport_num = a.unit_num
left join #FLL FLL on FLL.policy_id = ap.policy_id and FLL.policyimage_num = ap.policyimage_num and FLL.airport_num = a.unit_num
left join #HKA HKA on HKA.policy_id = ap.policy_id and HKA.policyimage_num = ap.policyimage_num and HKA.airport_num = a.unit_num
left join #HKO HKO on HKO.policy_id = ap.policy_id and HKO.policyimage_num = ap.policyimage_num and HKO.airport_num = a.unit_num
left join #ALO ALO on ALO.policy_id = ap.policy_id and ALO.policyimage_num = ap.policyimage_num and ALO.airport_num = a.unit_num
left join #ALA ALA on ALA.policy_id = ap.policy_id and ALA.policyimage_num = ap.policyimage_num and ALA.airport_num = a.unit_num
left join #PMO PMO on PMO.policy_id = ap.policy_id and PMO.policyimage_num = ap.policyimage_num and PMO.airport_num = a.unit_num
left join #PMPP PMPP on PMPP.policy_id = ap.policy_id and PMPP.policyimage_num = ap.policyimage_num and PMPP.airport_num = a.unit_num
left join #PMA PMA on PMA.policy_id = ap.policy_id and PMA.policyimage_num = ap.policyimage_num and PMA.airport_num = a.unit_num
left join #PCOO PCOO on PCOO.policy_id = ap.policy_id and PCOO.policyimage_num = ap.policyimage_num and PCOO.airport_num = a.unit_num
left join #PCOPP PCOPP on PCOPP.policy_id = ap.policy_id and PCOPP.policyimage_num = ap.policyimage_num and PCOPP.airport_num = a.unit_num
left join #PCOA PCOA on PCOA.policy_id = ap.policy_id and PCOA.policyimage_num = ap.policyimage_num and PCOA.airport_num = a.unit_num
left join #RS RS on RS.policy_id = ap.policy_id and RS.policyimage_num = ap.policyimage_num and RS.airport_num = a.unit_num
left join #EEPO EEPO on EEPO.policy_id = ap.policy_id and EEPO.policyimage_num = ap.policyimage_num and EEPO.airport_num = a.unit_num
left join #FWO FWO on FWO.policy_id = ap.policy_id and FWO.policyimage_num = ap.policyimage_num and FWO.airport_num = a.unit_num
left join #FL FL on FL.policy_id = ap.policy_id and FL.policyimage_num = ap.policyimage_num and FL.airport_num = a.unit_num
left join #UAS UAS on UAS.policy_id = ap.policy_id and UAS.policyimage_num = ap.policyimage_num and UAS.airport_num = a.unit_num
left join #PS PS on PS.policy_id = ap.policy_id and PS.policyimage_num = ap.policyimage_num and PS.airport_num = a.unit_num
left join #MIS MIS on MIS.policy_id = ap.policy_id and MIS.policyimage_num = ap.policyimage_num and MIS.airport_num = a.unit_num
left join #HKD HKD on HKD.policy_id = ap.policy_id and HKD.policyimage_num = ap.policyimage_num and HKD.airport_num = a.unit_num
left join #CATP CATP on CATP.policy_id = ap.policy_id and CATP.policyimage_num = ap.policyimage_num and CATP.airport_num = a.unit_num
left join #LL LL on LL.policy_id = ap.policy_id and LL.policyimage_num = ap.policyimage_num and LL.airport_num = a.unit_num
left join #PLST PLST on PLST.policy_id = ap.policy_id and PLST.policyimage_num = ap.policyimage_num and PLST.airport_num = a.unit_num
left join #PLCT PLCT on PLCT.policy_id = ap.policy_id and PLCT.policyimage_num = ap.policyimage_num and PLCT.airport_num = a.unit_num
left join #AP APP on APP.policy_id = ap.policy_id and APP.policyimage_num = ap.policyimage_num and APP.airport_num = a.unit_num
left join #APO APO on APO.policy_id = ap.policy_id and APO.policyimage_num = ap.policyimage_num and APO.airport_num = a.unit_num
left join #PT PT on PT.policy_id = ap.policy_id and PT.policyimage_num = ap.policyimage_num and PT.airport_num = a.unit_num
left join #APOC APOC on APOC.policy_id = ap.policy_id and APOC.policyimage_num = ap.policyimage_num and APOC.airport_num = a.unit_num
left join #NAS NAS on NAS.policy_id = ap.policy_id and NAS.policyimage_num = ap.policyimage_num and NAS.airport_num = a.unit_num
left join #RFV RFV on RFV.policy_id = ap.policy_id and RFV.policyimage_num = ap.policyimage_num and RFV.airport_num = a.unit_num
left join #OCD OCD on OCD.policy_id = ap.policy_id and OCD.policyimage_num = ap.policyimage_num and OCD.airport_num = a.unit_num
left join #OCDA OCDA on OCDA.policy_id = ap.policy_id and OCDA.policyimage_num = ap.policyimage_num and OCDA.airport_num = a.unit_num
left join #CL CLiab on CLiab.policy_id = ap.policy_id and CLiab.policyimage_num = ap.policyimage_num and CLiab.airport_num = a.unit_num
left join #underwriter uw on a.policy_id = uw.policy_id and a.policyimage_num = uw.policyimage_num
left join [AHI-S06].[Diamond].[dbo].[AgencyActivity] AA on AA.policy_id = ap.policy_id AND AA.policyimage_num = ap.policyimage_num and xml.agency_id = AA.agency_id and xml.agencyproducer_id = AA.agencyproducer_id
left join #Company comp on ap.policy_id = comp.policy_id and ap.policyimage_num = comp.policyimage_num
where case when pi.policy like 'Q%' then 'Quote'
			else 'Policy'
			end = 'Policy'


Delete from #DiaAP01 where coveragecode_id IN (90174,90177,90178,90179,90180,90181,90182,10035,10036,10037,10038,10039,10040,90000,90004,90005) --remove duplicates coverages that are combined into one coverage called product & completed operations occurrence (90171), tax, fee



if OBJECT_ID('tempdb.dbo.#DiaAP02') is not null drop table #DiaAP02
select
	a.*
	,datepart(yy,a.date_pol_eff)*100 + datepart(mm,a.date_pol_eff) mth_pol_eff
	,datepart(yy,a.date_pol_exp)*100 + datepart(mm,a.date_pol_exp) mth_pol_exp
	,datepart(yy,a.Calendar_Effective_Date)*100 + datepart(mm,a.Calendar_Effective_Date) mth_cal_eff
	,datepart(yy,a.Calendar_Expiration_Date)*100 + datepart(mm,a.Calendar_Expiration_Date) mth_cal_exp
	,datepart(yy,a.date_pol_eff)*10 + case when datepart(mm,a.date_pol_eff) in (1,2,3) then 1 when datepart(mm,a.date_pol_eff) in (4,5,6) then 2 when datepart(mm,a.date_pol_eff) in (7,8,9) then 3 else 4 end qtr_pol_eff
	,datepart(yy,a.date_pol_exp)*10 + case when datepart(mm,a.date_pol_exp) in (1,2,3) then 1 when datepart(mm,a.date_pol_exp) in (4,5,6) then 2 when datepart(mm,a.date_pol_exp) in (7,8,9) then 3 else 4 end qtr_pol_exp
	,datepart(yy,a.Calendar_Effective_Date)*10 + case when datepart(mm,a.Calendar_Effective_Date) in (1,2,3) then 1 when datepart(mm,a.Calendar_Effective_Date) in (4,5,6) then 2 when datepart(mm,a.Calendar_Effective_Date) in (7,8,9) then 3 else 4 end qtr_cal_eff
	,datepart(yy,a.Calendar_Expiration_Date)*10 + case when datepart(mm,a.Calendar_Expiration_Date) in (1,2,3) then 1 when datepart(mm,a.Calendar_Expiration_Date) in (4,5,6) then 2 when datepart(mm,a.Calendar_Expiration_Date) in (7,8,9) then 3 else 4 end qtr_cal_exp
	,datepart(yy,a.date_pol_eff) yr_pol
	,datepart(yy,a.Calendar_Effective_Date) yr_cal_eff
	,cast(datediff(dd, a.date_pol_eff, dateadd(yy, 1, a.date_pol_eff)) as float) term_year
	,round(cast(datediff(dd, a.date_pol_eff, a.date_pol_exp) AS MONEY) / cast(datediff(dd, a.date_pol_eff, dateadd(yy, 1, a.date_pol_eff)) AS MONEY), 3) Term_years
	,a.prem_chg_annual as prem_annual
	,1 STT
	,1 r_STT
	,1 rr_STT
	,1 rrr_STT
	,1 zz_STT
	,a.premium_written as prem_tech_written
	,a.premium_written as r_prem_tech_written
	,a.premium_written as rr_prem_tech_written
	,a.premium_written as rrr_prem_tech_written
	,a.premium_written as zz_prem_tech_written
	,a.premium_written as r_prem_written
	,a.premium_written as rr_prem_written
	,a.premium_written as rrr_prem_written
	,a.premium_written as zz_prem_written
	,a.prem_chg_annual as prem_tech_annual
	,a.prem_chg_annual as r_prem_tech_annual
	,a.prem_chg_annual as rr_prem_tech_annual
	,a.prem_chg_annual as rrr_prem_tech_annual
	,a.prem_chg_annual as zz_prem_tech_annual
	,a.prem_chg_annual as r_prem_annual
	,a.prem_chg_annual as rr_prem_annual
	,a.prem_chg_annual as rrr_prem_annual
	,a.prem_chg_annual as zz_prem_annual
	,a.premium_written as r_adq_written
	,a.premium_written as rr_adq_written
	,a.premium_written as rrr_adq_written
	,a.premium_written as zz_adq_written
	,a.prem_chg_annual as r_adq_annual
	,a.prem_chg_annual as rr_adq_annual
	,a.prem_chg_annual as rrr_adq_annual
	,a.prem_chg_annual as zz_adq_annual
	,a.premium_written as r_adq_tech_written
	,a.premium_written as rr_adq_tech_written
	,a.premium_written as rrr_adq_tech_written
	,a.premium_written as zz_adq_tech_written
	,a.prem_chg_annual as r_adq_tech_annual
	,a.prem_chg_annual as rr_adq_tech_annual
	,a.prem_chg_annual as rrr_adq_tech_annual
	,a.prem_chg_annual as zz_adq_tech_annual
	,a.premium_written * 0.65 as r_padq_tech_written
	,a.premium_written * 0.65 as rr_padq_tech_written
	,a.premium_written * 0.65 as rrr_padq_tech_written
	,a.premium_written * 0.65 as zz_padq_tech_written
	,a.prem_chg_annual * 0.65 as r_padq_tech_annual
	,a.prem_chg_annual * 0.65 as rr_padq_tech_annual
	,a.prem_chg_annual * 0.65 as rrr_padq_tech_annual
	,a.prem_chg_annual * 0.65 as zz_padq_tech_annual
	,a.premium_written * 0.65 as r_blpadq_tech_written
	,a.premium_written * 0.65 as rr_blpadq_tech_written
	,a.premium_written * 0.65 as rrr_blpadq_tech_written
	,a.premium_written * 0.65 as zz_blpadq_tech_written
	,a.prem_chg_annual * 0.65 as r_blpadq_tech_annual
	,a.prem_chg_annual * 0.65 as rr_blpadq_tech_annual
	,a.prem_chg_annual * 0.65 as rrr_blpadq_tech_annual
	,a.prem_chg_annual * 0.65 as zz_blpadq_tech_annual
into #DiaAP02
from #DiaAP01 a
left join #date_chks b on a.pol_num is not null
where a.date_pol_eff < b.date_book and a.accounting_date < b.date_book and a.received_date < b.date_book and a.trans_date < b.date_book


if OBJECT_ID('pricing_aim.dbo.DiaAPCovg') is not null drop table pricing_aim.dbo.DiaAPCovg

select * into pricing_aim.dbo.DiaAPCovg from #DiaAP02


-- check premium
--select sum(premium_written) from #DiaAP02
--select sum(premium_written_mtd) from Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy]
--where PolicyType = 'Airport'

--select pol_num, sum(premium_written) from #DiaAP02 group by pol_num order by pol_num
--select policy, sum(premium_written_mtd) from Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy] where policy like 'AP%' or policy like 'HLMAP%'
-- group by policy order by policy

-- difference of 1018 is acceptable
--AP100000037
--AP100000100



drop table
#date_chks
,#policyimage
,#Airport_pol00
,#Airport_pol
,#airport
,#covg00
,#covg01
,#covg02
,#PL
,#BIPD
,#AOO
,#AOPP
,#PIO
,#PIA
,#FLL
,#HKA
,#HKO
,#ALO
,#ALA
,#PMO
,#PMPP
,#PMA
,#PCOO
,#PCOPP
,#PCOA
,#RS
,#EEPO
,#FWO
,#FL
,#UAS
,#PS
,#MIS
,#HKD
,#CATP
,#LL
,#PLST
,#PLCT
,#AP
,#APO
,#PT
,#APOC
,#NAS
,#RFV
,#OCD
,#OCDA
,#CL
,#InsuredandCompany
,#Company
,#agency
,#PolicyAddress
,#Entity
,#underwriter
,#DiaAP01
,#DiaAP02

DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID)
exec UPDATE_QUERY_TIMES @PROC_NAME, @StartTime
 
END TRY 
BEGIN CATCH 
SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE 
END CATCH
GO


