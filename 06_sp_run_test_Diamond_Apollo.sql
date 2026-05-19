USE [Pricing_AIM]
GO

/****** Object:  StoredProcedure [dbo].[run_Diamond_Apollo]    Script Date: 5/18/2026 2:30:27 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[run_test_Diamond_Apollo]
AS
BEGIN TRY
	SET NOCOUNT ON;

declare @startTime datetime = getdate()



-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
--Diamond Part
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
--getting the diamond data
--Date
if OBJECT_ID('tempdb.dbo.#date_chks') is not null drop table #date_chks
create table #date_chks	(	date_pol_eff_min date,				--	inclusive
							date_book_val_min date,				--	inclusive
							date_book_val_max datetime,         --	exclusive
							date_book date)				        --  exclusive
							
							
insert into #date_chks	(date_pol_eff_min, date_book_val_min,	date_book_val_max,   date_book)
				values	('2001-01-01',		'2000-01-01',		getdate(),		DATEADD(DAY, 1, EOMONTH(getdate(), -1))) --Update here and search for the table creations (search prior month's valuation year)


--getting oldest and youngest birthdate and pilot count
if OBJECT_ID('tempdb.dbo.#pilot_count') is not null drop table #pilot_count
SELECT a.policy_id
	,a.policyimage_num
	,PAUA.detailstatuscode_id
	,air.aircraft_num
	,count(DISTINCT a.pilot_num) pilot_count
	,min(b.birth_date) min_birth_date
	,max(b.birth_date) max_birth_date
INTO #pilot_count
FROM [AHI-S06].[Diamond].[dbo].[PilotNameLink] a
LEFT JOIN [AHI-S06].[Diamond].[dbo].name b ON a.name_id = b.name_id
left join [AHI-S06].[Diamond].[dbo].[aircraft] air on a.policy_id = air.policy_id and a.policyimage_num = air.policyimage_num
left join [AHI-S06].[Diamond].[dbo].[PilotAircraftUseAssignment] PAUA on a.policy_id = PAUA.policy_id and a.policyimage_num = PAUA.policyimage_num and a.pilot_num = PAUA.pilot_num and PAUA.aircraft_num = air.aircraft_num
where display_name<>'OPC OPC' and b.detailstatuscode_id = 1 and PAUA.detailstatuscode_id = 1
GROUP BY a.policy_id
	,a.policyimage_num
	,PAUA.detailstatuscode_id
	,air.aircraft_num

--	select top 1000 * from #pilot_count where policy_id = 43107566
--	order by years_experience desc
--select top 100 * from [AHI-S06].[Diamond].[dbo].[PilotNameLink]
--select top 1000 * from [AHI-S06].[Diamond].[dbo].name
--select top 1000 * from [AHI-S06].[Diamond].[dbo].[PilotAircraftUseAssignment]

--Getting training information
if OBJECT_ID('tempdb.dbo.#temp_certifications') is not null drop table #temp_certifications
select policy_id
,policyimage_num
,unit_num
,cast(checkbox_selected as int)  checkbox_selected
,dscr
into #temp_certifications
FROM [AHI-S06].[Diamond].[dbo].Certification a
left join [AHI-S06].[Diamond].[dbo].certificationtype b on a.certificationtype_id=b.certificationtype_id

--pivoting to make more useful
if OBJECT_ID('tempdb.dbo.#temp_certifications_pivot') is not null drop table #temp_certifications_pivot
select [policy_id]
,[policyimage_num]
,sum([IFR-RW]) [IFR-RW]
,sum([RW-Heli]) [RW-Heli]
,sum([AMEL]) [AMEL]
,sum([Airplane - SE]) [Airplane - SE]
,sum([Glider]) [Glider]
,sum([Rotorwing]) [Rotorwing]
,sum([IFR-FW]) [IFR-FW]
,sum([AMES]) [AMES]
,sum([ASES]) [ASES]
,sum([Instrument]) [Instrument]
,sum([Sport]) [Sport]
,sum([Airplane - ME]) [Airplane - ME]
,sum([LTA]) [LTA]
,sum([RW-Gyro]) [RW-Gyro]
,sum([ASEL]) [ASEL]
into #temp_certifications_pivot
FROM #temp_certifications
pivot (sum(checkbox_selected) for dscr in ([IFR-RW],[RW-Heli],[AMEL],[Airplane - SE],[Glider],[Rotorwing],[IFR-FW],[AMES],[ASES],[Instrument],[Sport],[Airplane - ME],[LTA],[RW-Gyro],[ASEL]))a1
group by [policy_id]
,[policyimage_num]





--getting and organizing hours of flight information
if OBJECT_ID('tempdb.dbo.#temp_pilot_hours') is not null drop table #temp_pilot_hours
SELECT policy_id
	,policyimage_num
	,pilot_num
	,pilot_detailstatuscodeid
	,aircraftmakemodel_id
	--,aircraft_num
	--,hull_max_value
	,max(last_training_date) last_training_date
	,sum(isnull([Total Hours], 0)) [Total_Hours]
	,sum(isnull([ME Total], 0)) [ME_Total]
	,sum(isnull([FW TP], 0)) [FW_TP]
	,sum(isnull([FW TJ], 0)) [FW_TJ]
	,sum(isnull([RG], 0)) [RG]
	,sum(isnull([TW], 0)) [TW]
	,sum(isnull([RW Total], 0)) [RW_Total]
	,sum(isnull([RW Turb], 0)) [RW_Turb]
	,sum(isnull([RW Pist], 0)) [RW_Pist]
	,sum(isnull([SEA/AMPH], 0)) [SEA_AMPH]
	,sum(isnull([Glider], 0)) [Glider]
	,sum(isnull([Last 12], 0)) [Last_12]
	,sum(isnull([Last 90], 0)) [Last_90]
	,sum(isnull([M/M Hours], 0)) [MM_Hours]
	,sum(isnull([Last M/M Training Date], 0)) [Last_MM_Training Date]
	,sum(isnull([12 Month Hours], 0)) [12_Month_Hours]
	,sum(isnull([Last 90 Day Hours], 0)) [Last_90_Day_Hours]
INTO #temp_pilot_hours
FROM (
	SELECT k.policy_id
		,k.policyimage_num
		,k.pilot_num
		,PAUA.detailstatuscode_id as pilot_detailstatuscodeid
		,k.pilothistory_num
		,k.pilothistorytype_id
		,k.aircraftmakemodel_id
		,k.amount_of_hours
		,k.make_override
		,k.model_override
		,k.manufacturer_override
		,k.gear_type_dscr_override
		,k.wing_type_dscr_override
		,k.last_training_date
		,k.pcadded_date
		,k.last_modified_date
		,k.detailstatuscode_id
		,k.added_date
		,l.dscr
		,n.display_name
	FROM [AHI-S06].[Diamond].[dbo].PilotHistory k
	LEFT JOIN [AHI-S06].[Diamond].[dbo].[PilotHistoryType] l ON k.pilothistorytype_id = l.pilothistorytype_id
	left join [AHI-S06].[Diamond].[dbo].[PilotNameLink] pnl on k.policy_id = pnl.policy_id and k.policyimage_num = pnl.policyimage_num and k.pilot_num = pnl.pilot_num
	left join [AHI-S06].[Diamond].[dbo].name n on pnl.policy_id = n.policy_id and pnl.policyimage_num = n.policyimage_num and pnl.pilot_num = n.name_num
	left join [AHI-S06].[Diamond].[dbo].[aircraft] air on k.policy_id = air.policy_id and k.policyimage_num = air.policyimage_num and air.aircraftmakemodel_id = k.aircraftmakemodel_id
	left join [AHI-S06].[Diamond].[dbo].[PilotAircraftUseAssignment] PAUA on k.policy_id = PAUA.policy_id and k.policyimage_num = PAUA.policyimage_num and k.pilot_num = PAUA.pilot_num and air.aircraft_num = PAUA.aircraft_num
	where n.display_name <> 'OPC OPC' and n.nameaddresssource_id = 10062 and n.detailstatuscode_id = 1
	) a1
pivot(sum(amount_of_hours) FOR dscr IN ([Total Hours], [ME Total], [FW TP], [FW TJ], [RG], [TW], [RW Total], [RW Turb], [RW Pist], [SEA/AMPH], [Glider], [Last 12], [Last 90], [M/M Hours], [Last M/M Training Date], [12 Month Hours], [Last 90 Day Hours])) a2
GROUP BY policy_id
	,policyimage_num
	,pilot_num
	,pilot_detailstatuscodeid
	,aircraftmakemodel_id
	--aircraft_num
	--,hull_max_value
--select top 1000 * from [AHI-S06].[Diamond].[dbo].[aircraft]
--where policy_id = 43107566
if OBJECT_ID('tempdb.dbo.#temp_pilot_hours_a') is not null drop table #temp_pilot_hours_a
select 
	a.policy_id
	,a.policyimage_num
	,a.pilot_num
	,b.detailstatuscode_id
	,air.aircraftmakemodel_id
	,b.aircraft_num
	--,hull_max_value
	,a.last_training_date
	,a.Total_Hours
	,a.ME_Total
	,a.FW_TP
	,a.FW_TJ
	,a.RG
	,a.TW
	,a.RW_Total
	,a.RW_Turb
	,a.RW_Pist
	,a.SEA_AMPH
	,a.Glider
	,a.Last_12
	,a.Last_90
into #temp_pilot_hours_a
from #temp_pilot_hours as a
left join [AHI-S06].[Diamond].[dbo].[PilotAircraftUseAssignment] as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num and a.pilot_num = b.pilot_num
left join [AHI-S06].[Diamond].[dbo].[aircraft] as air on a.policy_id = air.policy_id and a.policyimage_num = air.policyimage_num and air.aircraft_num = b.aircraft_num
where b.detailstatuscode_id = 1 and a.aircraftmakemodel_id = 0


if OBJECT_ID('tempdb.dbo.#temp_pilot_hours_b') is not null drop table #temp_pilot_hours_b
select 
	a.policy_id
	,a.policyimage_num
	,a.pilot_num
	,a.pilot_detailstatuscodeid
	,a.aircraftmakemodel_id
	--,a.hull_max_value
	,a.last_training_date
	,a.MM_Hours
	,a.[Last_MM_Training Date]
	,a.[12_Month_Hours]
	,a.Last_90_Day_Hours
into #temp_pilot_hours_b
from #temp_pilot_hours as a
where a.aircraftmakemodel_id <> 0

delete from #temp_pilot_hours_b where pilot_detailstatuscodeid is null or pilot_detailstatuscodeid = 2

-----------------------------------------------------------------
--getting the min and max hours of flight information
if OBJECT_ID('tempdb.dbo.#temp_pilot_hours_min_max_a') is not null drop table #temp_pilot_hours_min_max_a
SELECT policy_id
	,policyimage_num
	,aircraftmakemodel_id
	--,detailstatuscode_id
	--,added_date
	,min([Total_Hours]) [Min_Total_Hours]
	,min([ME_Total]) [Min_ME_Total]
	,min([FW_TP]) [Min_FW_TP]
	,min([FW_TJ]) [Min_FW_TJ]
	,min([RG]) [Min_RG]
	,min([TW]) [Min_TW]
	,min([RW_Total]) [Min_RW_Total]
	,min([RW_Turb]) [Min_RW_Turb]
	,min([RW_Pist]) [Min_RW_Pist]
	,min([SEA_AMPH]) [Min_SEA_AMPH]
	,min([Glider]) [Min_Glider]
	,min([Last_12]) [Min_Last_12]
	,min([Last_90]) [Min_Last_90]
	,max([Total_Hours]) [max_Total_Hours]
	,max([ME_Total]) [max_ME_Total]
	,max([FW_TP]) [max_FW_TP]
	,max([FW_TJ]) [max_FW_TJ]
	,max([RG]) [max_RG]
	,max([TW]) [max_TW]
	,max([RW_Total]) [max_RW_Total]
	,max([RW_Turb]) [max_RW_Turb]
	,max([RW_Pist]) [max_RW_Pist]
	,max([SEA_AMPH]) [max_SEA_AMPH]
	,max([Glider]) [max_Glider]
	,max([Last_12]) [max_Last_12]
	,max([Last_90]) [max_Last_90]
INTO #temp_pilot_hours_min_max_a
FROM #temp_pilot_hours_a
--where detailstatuscode_id = 1
GROUP BY policy_id
	,policyimage_num
	,aircraftmakemodel_id
	--,detailstatuscode_id
	--,added_date

if OBJECT_ID('tempdb.dbo.#temp_pilot_hours_min_max_b') is not null drop table #temp_pilot_hours_min_max_b
SELECT policy_id
	,policyimage_num
	,aircraftmakemodel_id
	,min([MM_Hours]) [Min_MM_Hours]
	,min([Last_MM_Training Date]) [Min_Last_MM_Training Date]
	,min([12_Month_Hours]) [Min_12_Month_Hours]
	,min([Last_90_Day_Hours]) [Min_Last_90_Day_Hours]
	,max([MM_Hours]) [max_MM_Hours]
	,max([Last_MM_Training Date]) [max_Last_MM_Training Date]
	,max([12_Month_Hours]) [max_12_Month_Hours]
	,max([Last_90_Day_Hours]) [max_Last_90_Day_Hours]
INTO #temp_pilot_hours_min_max_b
FROM #temp_pilot_hours_b
GROUP BY policy_id
	,policyimage_num
	,aircraftmakemodel_id


--CSL Occurance Limit
if OBJECT_ID('tempdb.dbo.#occurance_limit_CSL') is not null drop table #occurance_limit_CSL
SELECT a.policy_id
	,air.policyimage_num
	,aircraft_num
	,aircraftmakemodel_id
	,air.premium_fullterm
	,air.premium_written
	,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #occurance_limit_CSL
FROM [AHI-S06].[Diamond].[dbo].[aircraft] air
LEFT JOIN [AHI-S06].[Diamond].[dbo].coverage a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90064

--CSL Passenger Limit
if OBJECT_ID('tempdb.dbo.#passenger_limit_CSL') is not null drop table #passenger_limit_CSL
SELECT a.policy_id
	,air.policyimage_num
	,aircraft_num
	,aircraftmakemodel_id
	,air.premium_fullterm
	,air.premium_written
	,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #passenger_limit_CSL
FROM [AHI-S06].[Diamond].[dbo].[aircraft] air
LEFT JOIN [AHI-S06].[Diamond].[dbo].coverage a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90065 


--Passenger Limit med
if OBJECT_ID('tempdb.dbo.#passenger_limit_med') is not null drop table #passenger_limit_med
SELECT a.policy_id
	,air.policyimage_num
	,aircraft_num
	,aircraftmakemodel_id
	,air.premium_fullterm
	,air.premium_written
	,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #passenger_limit_med
FROM [AHI-S06].[Diamond].[dbo].[aircraft] air
LEFT JOIN [AHI-S06].[Diamond].[dbo].coverage a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90066

--Occurance Limit Med
if OBJECT_ID('tempdb.dbo.#occurance_limit_med') is not null drop table #occurance_limit_med
SELECT a.policy_id
	,air.policyimage_num
	,aircraft_num
	,aircraftmakemodel_id
	,air.premium_fullterm
	,air.premium_written
	,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #occurance_limit_med
FROM [AHI-S06].[Diamond].[dbo].[aircraft] air
LEFT JOIN [AHI-S06].[Diamond].[dbo].coverage a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90067

--CSL Occurance Limit
if OBJECT_ID('tempdb.dbo.#pd_coverage') is not null drop table #pd_coverage
SELECT a.policy_id
	,air.policyimage_num
	,aircraft_num
	,aircraftmakemodel_id
	,air.premium_fullterm
	,air.premium_written
	,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,c.dscr limit_description
INTO #pd_coverage
FROM [AHI-S06].[Diamond].[dbo].[aircraft] air
LEFT JOIN [AHI-S06].[Diamond].[dbo].coverage a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90009

--pd not in motion deductible
if OBJECT_ID('tempdb.dbo.#pd_nim_ded') is not null drop table #pd_nim_ded
SELECT a.policy_id
	,air.policyimage_num
	,aircraft_num
	,aircraftmakemodel_id
	,air.premium_fullterm
	,air.premium_written
	,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,deductible_dscr
	,c.dscr limit_description
	,c.deductible as nim_deductible
INTO #pd_nim_ded
FROM [AHI-S06].[Diamond].[dbo].[aircraft] air
LEFT JOIN [AHI-S06].[Diamond].[dbo].coverage a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90053


--pd in motion deductible
if OBJECT_ID('tempdb.dbo.#pd_in_motion_ded') is not null drop table #pd_in_motion_ded
SELECT a.policy_id
	,air.policyimage_num
	,aircraft_num
	,aircraftmakemodel_id
	,air.premium_fullterm
	,air.premium_written
	,premium_chg_fullterm
	,limit_dscr
	,coveragecode
	,a.coveragecode_id
	,b.dscr coverage_dscr
	,deductible_dscr
	,c.dscr limit_description
	,case when c.dscr = 'Other' then a.deductible
			else c.deductible
			end im_deductible
INTO #pd_in_motion_ded
FROM [AHI-S06].[Diamond].[dbo].[aircraft] air
LEFT JOIN [AHI-S06].[Diamond].[dbo].coverage a ON a.policy_id = air.policy_id
	AND a.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
WHERE a.coveragecode_id = 90056

-------------------------------------------------------------
--Airport hangered information
if OBJECT_ID('tempdb.dbo.#airport') is not null drop table #airport
select policy_id
,policyimage_num
,a.airport_code
,airport_num
,dscr airport_name
,storagetype_id
,a.airportlookup_id
,b.zip
,b.state_abbr 
,b.is_coastal
,in_city_limits
into #airport
 FROM [AHI-S06].[Diamond].[dbo].[Airport] a
 left join [AHI-S06].[Diamond].[dbo].AirportLookup b on a.airportlookup_id=b.airportlookup_id
 where airport_num = 1

 --Insured
if OBJECT_ID('tempdb.dbo.#InsuredandCompany') is not null drop table #InsuredandCompany
 select 
	a.policy_id
	,a.policyimage_num
	--,a.aircraft_num
	,b.display_name as Insured
	,d.state as [State Insured]
into #InsuredandCompany
from [AHI-S06].[Diamond].[dbo].Aircraft as a
left join [AHI-S06].[Diamond].[dbo].name as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num
left join [AHI-S06].[Diamond].[dbo].address as c on a.policy_id = c.policy_id and a.policyimage_num = c.policyimage_num
left join [AHI-S06].[Diamond].[dbo].state as d on c.state_id = d.state_id
where b.nameaddresssource_id = 3 and c.nameaddresssource_id = 3 --and csl.lobname = 'Aircraft' 
group by 
	a.policy_id
	,a.policyimage_num
	,b.display_name
	,d.state


--Company
if OBJECT_ID('tempdb.dbo.#Company') is not null drop table #Company
 select 
	a.policy_id
	,a.policyimage_num
	,csl.commercial_name1 as Company
	,csl.company_id as [Company Code]
	,strisk.state state_risk
into #Company
from [AHI-S06].[Diamond].[dbo].Aircraft as a
left join [AHI-S06].diamond.dbo.policyimage p on a.policy_id = p.policy_id and a.policyimage_num = p.policyimage_num
left join [AHI-S06].diamond.dbo.version ver on p.version_id = ver.version_id
left join [AHI-S06].[Diamond].[dbo].state strisk on ver.state_id = strisk.state_id
left join [AHI-S06].diamond.dbo.vCompanyStateLOB csl on ver.companystatelob_id = csl.companystatelob_id
where csl.lobname = 'Aircraft' 
group by 
	a.policy_id
	,a.policyimage_num
	,csl.commercial_name1
	,csl.company_id
	,strisk.state 
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
from [AHI-S06].[Diamond].[dbo].[aircraft] as air
left join [AHI-S06].[Diamond].[dbo].vPolicyImageXML as p on air.policy_id = p.policy_id and air.policyimage_num = p.policyimage_num
left join [AHI-S06].[Diamond].[dbo].[AgencyAddressLink] as a on p.agency_id = a.agency_id
left join [AHI-S06].[Diamond].[dbo].[Address] as b on a.address_id = b.address_id
left join [AHI-S06].[Diamond].[dbo].state as c on b.state_id = c.state_id
where a.nameaddresssource_id = 8
group by 
	air.policy_id
	,air.policyimage_num
	,p.agency_id
	,a.nameaddresssource_id
	,a.address_id
	,b.city
	,c.state


--policy city, policy county
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
from [AHI-S06].[Diamond].[dbo].[aircraft] as air
left join [AHI-S06].[Diamond].[dbo].PolicyImage as a on air.policy_id = a.policy_id and air.policyimage_num = a.policyimage_num
left join [AHI-S06].[Diamond].[dbo].Address as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num
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
from [AHI-S06].[Diamond].[dbo].[aircraft] as air
left join [AHI-S06].[Diamond].[dbo].Name as a on air.policy_id = a.policy_id and air.policyimage_num = a.policyimage_num
left join [AHI-S06].[Diamond].[dbo].EntityType as b on a.entitytype_id = b.entitytype_id
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
from [AHI-S06].[Diamond].[dbo].[aircraft] as air
left join [AHI-S06].[Diamond].[dbo].[policyimage] as a on a.policy_id = air.policy_id and air.policyimage_num = a.policyimage_num
left join [AHI-S06].[Diamond].[dbo].[vusers] as b on a.underwriter_users_id = b.users_id
group by 
	air.policy_id
	,air.policyimage_num
	,a.underwriter_users_id
	,b.display_name

---------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#policyimage') is not null drop table #policyimage
select
	ROW_NUMBER() over(Partition by policy_id, premium_diff_chg_written, trans_remark order by policyimage_num) repeat_transaction_count
	,*
into #policyimage
from [AHI-S06].[Diamond].[dbo].policyimage
where (policy like 'GA%' or policy like 'HLMGA%' or policy like 'HDIGA%' ) and policystatuscode_id <> 4  and policystatuscode_id <> 8 and policystatuscode_id <> 5 and policystatuscode_id <> 6 and transreason_id <> 8 and transtype_id <> 13
--and eff_date < '2023-07-31' and exp_date >'2024-08-31' and cancel_date = '1800-01-01 00:00:00.000'
--select * from [AHI-S06].diamond.dbo.policystatuscode

--delete from #policyimage where repeat_transaction_count <> 1

if OBJECT_ID('tempdb.dbo.#pol_air00') is not null drop table #pol_air00
select distinct policy_id, policyimage_num into #pol_air00 FROM [AHI-S06].[Diamond].[dbo].[aircraft] 



if OBJECT_ID('tempdb.dbo.#pol_air') is not null drop table #pol_air
select a.policy_id, 
	a.policyimage_num 
	,b.repeat_transaction_count
into #pol_air 
FROM #pol_air00 as a
inner join #policyimage as b on a.policy_id = b.policy_id and a.policyimage_num = b.policyimage_num

---------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#aircraft') is not null drop table #aircraft
select * into #aircraft from [AHI-S06].[Diamond].[dbo].[aircraft] 
where detailstatuscode_id = 1

---------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#covg_prem') is not null drop table #covg_prem
select
	a.*
into #covg_prem
from #pol_air as pa
left join [AHI-S06].[Diamond].[dbo].coverage as a on a.policy_id = pa.policy_id and a.policyimage_num = pa.policyimage_num
left join [AHI-S06].[Diamond].[dbo].PolicyImage as pi on pi.policy_id = a.policy_id and pi.policyimage_num = a.policyimage_num
where pi.policy like 'GA%' or pi.policy like 'HLMGA%' or pi.policy like 'HDIGA%' and pi.policystatuscode_Id <> 13 --or pi.policy like 'QGA%' --and a.detailstatuscode_id = 1
--and a.eff_date > '2023-07-31' and a.exp_date <'2024-08-31' 

-------------------------------------------------------------------------
--master table for aircrafts 

if OBJECT_ID('tempdb.dbo.#temp00') is not null drop table #temp00
SELECT 
	case when pi.policy like 'Q%' then 'Quote'
			else 'Policy'
			end PolicyType
	,pa.policy_id
	,pa.policyimage_num
	--,a.policy_id
	--,a.policyimage_num
	,pi.policy as pol_num
	,pol.client_id
	,cast(CONCAT(case when left(pi.policy,5) ='GA100' then 10 when left(pi.policy,5) = 'HLMGA' then 20 when left(pi.policy,5) = 'HDIGA' then 30 else 40 end  ,right(pi.policy,9))as bigint)*100 +pi.renewal_ver  as pol_num_full_clean
	,pi.eff_date as date_pol_eff
	,pi.exp_date as date_pol_exp
	,pi.teff_date as Calendar_Effective_Date
	,pi.texp_date as Calendar_Expiration_Date
	,pi.trans_date
	,pi.accounting_date
	,pi.received_date
	,pi.renewal_ver as pol_ed
	,IAC.Insured as insd_name_hist
	,IAC.[State Insured] as state_insd
	,en.Entity_Type
	,comp.[Company Code]
	,comp.[Company] as company_code
	,padd.policy_city
	,padd.policy_county
	,comp.state_risk state_risk
	,padd.policy_state
	,padd.policy_zip
	,a.coverage_num
	,a.unit_num
	,air.aircraft_num as aircraft_num
	,air.aircraft_display_num
	,a.coveragecode_id
	,b.coveragecode
	,b.dscr covg_description
	,c.limit_dscr
	,c.dscr limit_description
	,claim_limit_perperson
	,claim_limit_peroccur
	,claim_deductible
	,claim_limit_dscr
	,claim_deduct_dscr
	,case when pa.repeat_transaction_count = 1 then a.premium_diff_chg_written
			when pa.repeat_transaction_count > 1 then 0
			end premium_diff_chg_written_calc
	,
	case when pi.transtype_id =8 and pi.transreason_id =41 then 0 else -- deals with un renewed non cancel premiums
	a.premium_diff_chg_written end premium_diff_chg_written--as old_premium_diff_chg_written
	,a.premium_diff_chg_fullterm
	,a.premium_fullterm
	,a.premium_written
	,a.premium_chg_fullterm as prem_chg_fullterm
	,a.premium_chg_written as prem_chg_written
	,a.premium_annual as prem_annual
	,a.premium_chg_annual as premium_chg_annual
	,sum(AA.commission) as comm_written
	,pi.transtype_id 
	,ts.transtype
	,ts.dscr as Transaction_type
	,air.[year]
	,air.tail_number
	,air.model
	,hull_value
	,hull_rate
	,d.[year] model_year
	,datepart(yy,pi.eff_date) - d.[year] model_age
	,e.dscr make_dscr
	,f.dscr seating_capacity_dscr
	,g.dscr gear_type_dscr
	,i.dscr wing_type_dscr
	,j.dscr aircraftuse_dscr
	,air.aircraftusetype_id as SpecialUse_Code
	,isnull(k.[Min_Total_Hours], 0) [Min_Total_Hours]
	,isnull(k.[Min_ME_Total], 0) [Min_ME_Total]
	,isnull(k.[Min_FW_TP], 0) [Min_FW_TP]
	,isnull(k.[Min_FW_TJ], 0) [Min_FW_TJ]
	,isnull(k.[Min_RG], 0) [Min_RG]
	,isnull(k.[Min_TW], 0) [Min_TW]
	,isnull(k.[Min_RW_Total], 0) [Min_RW_Total]
	,isnull(k.[Min_RW_Turb], 0) [Min_RW_Turb]
	,isnull(k.[Min_RW_Pist], 0) [Min_RW_Pist]
	,isnull(k.[Min_SEA_AMPH], 0) [Min_SEA_AMPH]
	,isnull(k.[Min_Glider], 0) [Min_Glider]
	,isnull(k.[Min_Last_12], 0) [Min_Last_12]
	,isnull(k.[Min_Last_90], 0) [Min_Last_90]
	,isnull(kb.[Min_MM_Hours], 0) [Min_MM_Hours]
	,isnull(kb.[Min_Last_MM_Training Date], 0) [Min_Last_MM_Training Date]
	,isnull(kb.[Min_12_Month_Hours], 0) [Min_12_Month_Hours]
	,isnull(kb.[Min_Last_90_Day_Hours], 0) [Min_Last_90_Day_Hours]
	,isnull(k.[max_Total_Hours], 0) [max_Total_Hours]
	,isnull(k.[max_ME_Total], 0) [max_ME_Total]
	,isnull(k.[max_FW_TP], 0) [max_FW_TP]
	,isnull(k.[max_FW_TJ], 0) [max_FW_TJ]
	,isnull(k.[max_RG], 0) [max_RG]
	,isnull(k.[max_TW], 0) [max_TW]
	,isnull(k.[max_RW_Total], 0) [max_RW_Total]
	,isnull(k.[max_RW_Turb], 0) [max_RW_Turb]
	,isnull(k.[max_RW_Pist], 0) [max_RW_Pist]
	,isnull(k.[max_SEA_AMPH], 0) [max_SEA_AMPH]
	,isnull(k.[max_Glider], 0) [max_Glider]
	,isnull(k.[max_Last_12], 0) [max_Last_12]
	,isnull(k.[max_Last_90], 0) [max_Last_90]
	,isnull(kb.[max_MM_Hours], 0) [max_MM_Hours]
	,isnull(kb.[max_Last_MM_Training Date], 0) [max_Last_MM_Training Date]
	,isnull(kb.[max_12_Month_Hours], 0) [max_12_Month_Hours]
	,isnull(kb.[max_Last_90_Day_Hours], 0) [max_Last_90_Day_Hours]
	,l.max_birth_date
	,l.min_birth_date
	,DATEDIFF(YY, max_birth_date, pi.eff_date) min_age --will constantly cause rating issue
	,DATEDIFF(YY, min_birth_date, pi.eff_date) max_age --will constantly cause rating issue
	,l.pilot_count
	,air.tail_number faano
	,m.aircrafttype_id
	,m.dscr aircraft_type_description
	,p.policytermversion_dscr
	,uw.underwriter_name
	,p.agency_code
	,p.agencyproducer_code
	,p.agency_id
	,p.agencyproducer_id
	,p.agency_name
	,p.agencyproducer_name
	,ag.agency_city
	,ag.agency_state
	,p.policyterm_id
	,p.premium_chg_fullterm
	,p.premium_chg_written
	,n.limit_dscr CSL_Occurance_Limit
	,n.limit_description CSL_Occurance_Limit_description
	,s.limit_dscr CSL_Passenger_Limit
	,s.limit_description CSL_Passenger_Limit_description
	,o.limit_dscr Med_Occurance_Limit
	,o.limit_description Med_Occurance_Limit_description
	,q.limit_dscr Med_Passenger_Limit
	,q.limit_description Med_Passenger_Limit_description
	,r.limit_dscr PD_Limit
	,r.limit_description PD_Limit_description
	,CASE 
		WHEN r.limit_dscr = 'Ground & Flight'
			THEN 'GRO-Flight'
		WHEN r.limit_dscr = 'Ground - Not in Motion'
			THEN 'GRO-NIM'
		WHEN r.limit_dscr = 'Ground & Taxi (excluding In Flight)'
			THEN 'GRO-Taxi'
		END Coverage_group
	,case when t.adjustment_factor = 0 and t.rate = 0 then 0 
			when isnull(t.adjustment_factor,0) <> 0 then t.adjustment_factor
			when isnull(t.rate,0) <> 0 then t.rate
			else null
			end adjustment_factor
	,case when isnull(t.adjustment_factor,0) <> 0 then 'Dollar' 
			when isnull(t.rate,0) <> 0 then 'Rate' 
			else 'Dollar' 
			end adjustment_type
	,case when t.adjustment_factor <> 0 then a.premium_fullterm - isnull(t.adjustment_factor,0) 
			when t.rate <> 0 then a.premium_fullterm / (1 + t.rate)
			when t.adjustment_factor = 0 and t.rate = 0 then a.premium_fullterm
			when t.adjustment_factor is null and t.rate is null then a.premium_fullterm
			when t.adjustment_factor is null and t.rate = 0 then a.premium_fullterm
			when t.adjustment_factor = 0 and t.rate is null then a.premium_fullterm
			end premium_tech_annual
	,case when isnull(t.adjustment_factor,0) <> 0 then a.premium_written - isnull(t.adjustment_factor,0) 
			when isnull(t.rate,0) <> 0 then a.premium_written/(1+isnull(t.rate,0)) 
			else a.premium_written 
			end written_tech
	,u.airport_name
	,u.in_city_limits
	,u.is_coastal
	,u.state_abbr
	,u.storagetype_id
	,u.zip
	,d.model_code
	,case when [IFR-RW]>0 then 1 else 0 end [IFR-RW]
	,case when [RW-Heli]>0 then 1 else 0 end  [RW-Heli]
	,case when [AMEL]>0 then 1 else 0 end [AMEL]
	,case when [Airplane - SE]>0 then 1 else 0 end [Airplane - SE]
	,case when [Glider]>0 then 1 else 0 end [Glider]
	,case when [Rotorwing]>0 then 1 else 0 end [Rotorwing]
	,case when [IFR-FW]>0 then 1 else 0 end [IFR-FW]
	,case when [AMES]>0 then 1 else 0 end [AMES]
	,case when [ASES]>0 then 1 else 0 end [ASES]
	,case when [Instrument]>0 then 1 else 0 end [Instrument]
	,case when [Sport]>0 then 1 else 0 end [Sport]
	,case when [Airplane - ME]>0 then 1 else 0 end [Airplane - ME]
	,case when [LTA]>0 then 1 else 0 end [LTA]
	,case when [RW-Gyro]>0 then 1 else 0 end [RW-Gyro]
	,case when [ASEL]>0 then 1 else 0 end [ASEL]
	,im.im_deductible as in_motion_deductible
	,nim.nim_deductible as not_in_motion_deductible
	,'AIM' as business_unit
	,case when a.coveragecode_id = 90064 or a.coveragecode_id = 90066 then 'ACL'
			else 'ACH'
			end as reserving
	,'1' as id_trans
	,case when pol.cancelled = 1 then 'CX' else '' end cncl_status
	,case when pol.cancel_date = '1800-01-01 00:00:00.000' then '2999-12-31' else pol.cancel_date end date_cncl
	,'Primary' as ind_pri_xs
	,da.date_book_val_max
	,pol.lastimage_num cancelled_policyimage_num
into #temp00
FROM #pol_air pa 
LEFT JOIN #covg_prem a ON a.policy_id = pa.policy_id AND a.policyimage_num = pa.policyimage_num --[AHI-S06].[Diamond].[dbo].coverage
left join #aircraft air ON pa.policy_id = air.policy_id --[AHI-S06].[Diamond].[dbo].[aircraft]
	AND pa.policyimage_num = air.policyimage_num
	AND a.unit_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragecode b ON a.coveragecode_id = b.coveragecode_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].coveragelimit c ON c.coveragelimit_id = a.coveragelimit_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].aircraftmakemodel d ON d.aircraftmakemodel_id = air.aircraftmakemodel_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].aircraftmake e ON e.aircraftmake_id = d.aircraftmake_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].seatingcapacitytype f ON f.seatingcapacitytype_id = air.seatingcapacitytype_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].geartype g ON g.geartype_id = d.geartype_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].wingtype i ON i.wingtype_id = d.wingtype_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].aircraftusetype j ON j.aircraftusetype_id = air.aircraftusetype_id
LEFT JOIN [AHI-S06].[Diamond].[dbo].PolicyImage pi ON pi.policy_id = a.policy_id
	AND pi.policyimage_num = a.policyimage_num
LEFT JOIN #temp_pilot_hours_min_max_a k ON k.policy_id = air.policy_id
	AND k.policyimage_num = air.policyimage_num
	and k.aircraftmakemodel_id = air.aircraftmakemodel_id
LEFT JOIN #temp_pilot_hours_min_max_b kb on kb.policy_id = air.policy_id
	AND kb.policyimage_num = air.policyimage_num
	AND kb.aircraftmakemodel_id = air.aircraftmakemodel_id
LEFT JOIN #pilot_count l ON l.policy_id = a.policy_id
	AND l.policyimage_num = a.policyimage_num
	and l.aircraft_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].vPolicyImageXML p ON p.policy_id = a.policy_id
	AND p.policyimage_num = a.policyimage_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].AircraftType m ON m.aircrafttype_id = d.aircrafttype_id
LEFT JOIN #occurance_limit_CSL n ON n.policy_id = a.policy_id
	AND n.policyimage_num = a.policyimage_num
	AND n.aircraft_num = air.aircraft_num
LEFT JOIN #occurance_limit_med o ON o.policy_id = a.policy_id
	AND o.policyimage_num = a.policyimage_num
	AND o.aircraft_num = air.aircraft_num
LEFT JOIN #passenger_limit_CSL s ON s.policy_id = a.policy_id
	AND s.policyimage_num = a.policyimage_num
	AND s.aircraft_num = air.aircraft_num
LEFT JOIN #passenger_limit_med q ON q.policy_id = a.policy_id
	AND q.policyimage_num = a.policyimage_num
	AND q.aircraft_num = air.aircraft_num
LEFT JOIN #pd_coverage r ON r.policy_id = a.policy_id
	AND r.policyimage_num = a.policyimage_num
	AND r.aircraft_num = air.aircraft_num
LEFT JOIN [AHI-S06].[Diamond].[dbo].[CoverageDetail] t on t.policy_id=a.policy_id and t.policyimage_num=a.policyimage_num and t.coverage_num = a.coverage_num
LEFT JOIN #airport u on u.policy_id=a.policy_id and u.policyimage_num=a.policyimage_num
left join #temp_certifications_pivot v on v.policy_id=a.policy_id and v.policyimage_num=a.policyimage_num
left join #pd_in_motion_ded im on a.policy_id = im.policy_id and a.policyimage_num = im.policyimage_num and air.aircraft_num = im.aircraft_num
left join #pd_nim_ded nim on a.policy_id = nim.policy_id and a.policyimage_num = nim.policyimage_num and air.aircraft_num = nim.aircraft_num
left join #InsuredandCompany IAC on pa.policy_id = IAC.policy_id and pa.policyimage_num = IAC.policyimage_num --and air.aircraft_num = IAC.aircraft_num
left join #date_chks da on a.policy_id is not null
left join #agency ag on pa.policy_id = ag.policy_id and pa.policyimage_num = ag.policyimage_num
left join #PolicyAddress padd on pa.policy_id = padd.policy_id and pa.policyimage_num = padd.policyimage_num
left join #Entity en on pa.policy_id = en.policy_id and pa.policyimage_num = en.policyimage_num
left join [AHI-S06].[Diamond].[dbo].transtype as ts on pi.transtype_id = ts.transtype_id
left join [AHI-S06].[Diamond].[dbo].[AgencyActivity] AA on AA.policy_id = pa.policy_id AND AA.policyimage_num = pa.policyimage_num and p.agency_id = AA.agency_id and p.agencyproducer_id = AA.agencyproducer_id
left join #underwriter uw on a.policy_id = uw.policy_id and a.policyimage_num = uw.policyimage_num
left join #Company comp on a.policy_id = comp.policy_id and a.policyimage_num = comp.policyimage_num
left join [AHI-S06].[Diamond].[dbo].policy pol on a.policy_id = pol.policy_id
where case when pi.policy like 'Q%' then 'Quote'
			else 'Policy'
			end = 'Policy'
	and pi.eff_date < da.date_book and pi.trans_date < da.date_book and pi.accounting_date < da.date_book and pi.received_date < da.date_book
	and pi.policystatuscode_id not in (12,13)
--	and pi.eff_date > '2023-05-31' and pi.exp_date <'2024-08-31' 

	--and air.detailstatuscode_id = 1

group by 
	pa.policy_id
	,pa.policyimage_num
	,pi.policy
	,pol.client_id
	,pi.eff_date 
	,pi.exp_date 
	,pi.teff_date 
	,pi.texp_date 
	,pi.trans_date
	,pi.accounting_date
	,pi.received_date
	,pi.renewal_ver 
	,IAC.Insured 
	,IAC.[State Insured] 
	,en.Entity_Type
	,comp.[Company Code]
	,comp.[Company] 
	,padd.policy_city
	,padd.policy_county
	,padd.policy_state
	,comp.state_risk
	,padd.policy_zip
	,a.policy_id
	,a.policyimage_num
	,a.coverage_num
	,a.unit_num
	,air.aircraft_num 
	,air.aircraft_display_num
	,a.coveragecode_id
	,b.coveragecode
	,b.dscr 
	,c.limit_dscr
	,c.dscr 
	,claim_limit_perperson
	,claim_limit_peroccur
	,claim_deductible
	,claim_limit_dscr
	,claim_deduct_dscr
	,pa.repeat_transaction_count 
	,case when pi.transtype_id =8 and pi.transreason_id =41 then 0 else
	a.premium_diff_chg_written end
	,a.premium_diff_chg_written
	,a.premium_diff_chg_fullterm
	,a.premium_fullterm
	,a.premium_written
	,a.premium_chg_fullterm 
	,a.premium_chg_written
	,a.premium_annual
	,a.premium_chg_annual
	,pi.transtype_id 
	,ts.transtype
	,ts.dscr 
	,air.[year]
	,air.tail_number
	,air.model
	,hull_value
	,hull_rate
	,d.[year] 
	,e.dscr 
	,f.dscr 
	,g.dscr 
	,i.dscr 
	,j.dscr 
	,air.aircraftusetype_id
	,k.[Min_Total_Hours]
	,k.[Min_ME_Total]
	,k.[Min_FW_TP]
	,k.[Min_FW_TJ]
	,k.[Min_RG]
	,k.[Min_TW]
	,k.[Min_RW_Total]
	,k.[Min_RW_Turb]
	,k.[Min_RW_Pist]
	,k.[Min_SEA_AMPH]
	,k.[Min_Glider]
	,k.[Min_Last_12]
	,k.[Min_Last_90]
	,kb.[Min_MM_Hours]
	,kb.[Min_Last_MM_Training Date]
	,kb.[Min_12_Month_Hours]
	,kb.[Min_Last_90_Day_Hours]
	,k.[max_Total_Hours]
	,k.[max_ME_Total]
	,k.[max_FW_TP]
	,k.[max_FW_TJ]
	,k.[max_RG]
	,k.[max_TW]
	,k.[max_RW_Total]
	,k.[max_RW_Turb]
	,k.[max_RW_Pist]
	,k.[max_SEA_AMPH]
	,k.[max_Glider]
	,k.[max_Last_12]
	,k.[max_Last_90]
	,kb.[max_MM_Hours]
	,kb.[max_Last_MM_Training Date]
	,kb.[max_12_Month_Hours]
	,kb.[max_Last_90_Day_Hours]
	,l.max_birth_date
	,l.min_birth_date
	--,air.eff_date
	--,air.eff_date
	,l.pilot_count
	,air.tail_number 
	,m.aircrafttype_id
	,m.dscr 
	,p.policytermversion_dscr
	,uw.underwriter_name
	,p.agency_code
	,p.agencyproducer_code
	,p.agency_id
	,p.agencyproducer_id
	,p.agency_name
	,p.agencyproducer_name
	,ag.agency_city
	,ag.agency_state
	,p.policyterm_id
	,p.premium_chg_fullterm
	,p.premium_chg_written
	,n.limit_dscr 
	,n.limit_description 
	,s.limit_dscr 
	,s.limit_description 
	,o.limit_dscr 
	,o.limit_description 
	,q.limit_dscr 
	,q.limit_description 
	,r.limit_dscr 
	,r.limit_description 
	,t.adjustment_factor
	,t.rate  
	,u.airport_name
	,u.in_city_limits
	,u.is_coastal
	,u.state_abbr
	,u.storagetype_id
	,u.zip
	,d.model_code
	,[IFR-RW]
	,[RW-Heli]
	,[AMEL]
	,[Airplane - SE]
	,[Glider]
	,[Rotorwing]
	,[IFR-FW]
	,[AMES]
	,[ASES]
	,[Instrument]
	,[Sport]
	,[Airplane - ME]
	,[LTA]
	,[RW-Gyro]
	,[ASEL]
	,im.im_deductible 
	,nim.nim_deductible
	,da.date_book_val_max
	,pol.cancelled
	,pol.cancel_date
	,pol.lastimage_num


delete from #temp00
where pol_num is null

delete from #temp00
where coveragecode_id in (90157,90158,10035,10036,10037,10038,10039,10040,90000,90004,90005) --remove tax, fee, and 90157&90158 sub coverages
--90164, 90048,90144

update #temp00
set pilot_count = isnull(pilot_count,0)

update #temp00
set min_age = case when pilot_count = 0 then 0
					else min_age
					end

update #temp00
set max_age = case when pilot_count = 0 then 0
					else max_age
					end


-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
if OBJECT_ID('dbo.test_diamond_data_aim') is not null drop table dbo.test_diamond_data_aim
--
select * into dbo.test_diamond_data_aim from #temp00


-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------

--getting the rating tables orginized


----Rating version----
if OBJECT_ID('tempdb..#version') is not null drop table #version

select * into #version
FROM [Pricing_AIM].[dbo].[r_version]

-------------------------------------------------------------------AIRCRAFT MODEL FOR HULL----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#AircraftModelModifierHull') is not null
		drop table #AircraftModelModifierHull

select * into #AircraftModelModifierHull FROM pricing_aim.dbo.[r_DiaAircraftModelModifierHull]

 create index indx_1 on #AircraftModelModifierHull (AircraftType, PrimaryUseId,  GearType,VersionId)

if OBJECT_ID('tempdb..#AircraftModelModifierHull_ex_gear') is not null
		drop table #AircraftModelModifierHull_ex_gear
		
select distinct AircraftType	
,PrimaryUseId	
,ModelCode	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #AircraftModelModifierHull_ex_gear 
FROM #AircraftModelModifierHull
where GearType is null

 create index indx_1 on #AircraftModelModifierHull_ex_gear (AircraftType, PrimaryUseId,  VersionId)

-------------------------------------------------------------------AIRCRAFT MODEL FOR LIAB----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#AircraftModelModifierLiab') is not null
		drop table #AircraftModelModifierLiab

select * into #AircraftModelModifierLiab FROM pricing_aim.dbo.r_DiaAircraftModelModifierLiab

 create index indx_1 on #AircraftModelModifierLiab (AircraftType, PrimaryUseId,  GearType,VersionId)

if OBJECT_ID('tempdb..#AircraftModelModifierLiab_ex_gear') is not null
		drop table #AircraftModelModifierLiab_ex_gear
		
select distinct AircraftType	
,PrimaryUseId	
,ModelCode	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #AircraftModelModifierLiab_ex_gear 
FROM #AircraftModelModifierLiab
where GearType is null

 create index indx_1 on #AircraftModelModifierLiab_ex_gear (AircraftType, PrimaryUseId,  VersionId)

-----------------------------------------------------------------SEAT INDEX----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#SeatIndex') is not null
		drop table #SeatIndex

select * into #SeatIndex FROM pricing_aim.dbo.r_SeatIndex

 create index indx_1 on #SeatIndex (AircraftType, PrimaryUseId,  GearType,VersionId)

if OBJECT_ID('tempdb..#SeatIndex_second') is not null
		drop table #SeatIndex_second

select distinct PrimaryUseId	
,NoOfSeatsMin	
,EntryOperator	
,NoOfSeatsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #SeatIndex_second
 FROM #SeatIndex

  create index indx_1 on #SeatIndex_second ( PrimaryUseId,  VersionId)
 
update #SeatIndex
set NoOfSeatsMax = case when NoOfSeatsMax = 'NULL' then null else NoOfSeatsMax end

update #SeatIndex_second
set NoOfSeatsMax = case when NoOfSeatsMax = 'NULL' then null else NoOfSeatsMax end

alter table #SeatIndex_second
alter column NoOfSeatsMin int

alter table #SeatIndex
alter column NoOfSeatsMax int
alter table #SeatIndex_second
alter column NoOfSeatsMax int
-----------------------------------------------------------------PrimaryPilotRating----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PrimaryPilotRating') is not null
		drop table #PrimaryPilotRating

select * into #PrimaryPilotRating FROM pricing_aim.dbo.r_PrimaryPilotDiamond

 create index indx_1 on #PrimaryPilotRating (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#PrimaryPilotRating_second') is not null
		drop table #PrimaryPilotRating_second

select AircraftType	
,PrimaryUseId		
,PilotMinTotalHrsMin	
,EntryOperator	
,PilotMinTotalHrsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PrimaryPilotRating_second
FROM #PrimaryPilotRating
where GearType is null

 create index indx_1 on #PrimaryPilotRating_second (AircraftType	,PrimaryUseId,VersionId	)

if OBJECT_ID('tempdb..#PrimaryPilotRating_third') is not null
		drop table #PrimaryPilotRating_third

select AircraftType	
,PilotMinTotalHrsMin	
,EntryOperator	
,PilotMinTotalHrsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PrimaryPilotRating_third
FROM #PrimaryPilotRating
where GearType is null and PrimaryUseId is null

 create index indx_1 on #PrimaryPilotRating_third (AircraftType	,VersionId	)

if OBJECT_ID('tempdb..#PrimaryPilotRating_fourth') is not null
		drop table #PrimaryPilotRating_fourth

select PilotMinTotalHrsMin	
,EntryOperator	
,PilotMinTotalHrsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PrimaryPilotRating_fourth
FROM #PrimaryPilotRating
where GearType is null and PrimaryUseId is null and AircraftType is null

 create index indx_1 on #PrimaryPilotRating_fourth (VersionId	)


-----------------------------------------------------------------LocAirportModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#LocAirportModifier') is not null
		drop table #LocAirportModifier

select * into #LocAirportModifier FROM pricing_aim.dbo.r_LocAirportModifier

 create index indx_1 on #LocAirportModifier (LocAirport,AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#LocAirportModifier_second') is not null
		drop table #LocAirportModifier_second

select distinct LocAirport	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #LocAirportModifier_second
 FROM #LocAirportModifier

  create index indx_1 on #LocAirportModifier_second (LocAirport	,VersionId	)
-----------------------------------------------------------------LocStateModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#LocStateModifier') is not null
		drop table #LocStateModifier


select * into #LocStateModifier FROM pricing_aim.dbo.r_LocStateModifier

 create index indx_1 on #LocStateModifier (LocState,AircraftType	,PrimaryUseId	,GearType,VersionId	)


if OBJECT_ID('tempdb..#LocStateModifier_second') is not null
		drop table #LocStateModifier_second

select distinct LocState	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #LocStateModifier_second
FROM #LocStateModifier

 create index indx_1 on #LocStateModifier_second (LocState,VersionId	)



-----------------------------------------------------------------CMIndexHull----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#CMIndexHull') is not null
		drop table #CMIndexHull

select * into #CMIndexHull FROM pricing_aim.dbo.r_CMIndexHull

 create index indx_1 on #CMIndexHull (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#CMIndexHull_second') is not null
		drop table #CMIndexHull_second

select distinct AircraftType	
,PrimaryUseId	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE 
into #CMIndexHull_second
FROM #CMIndexHull
where GearType is null

 create index indx_1 on #CMIndexHull_second (AircraftType	,PrimaryUseId	,VersionId	)


if OBJECT_ID('tempdb..#CMIndexHull_third') is not null
		drop table #CMIndexHull_third

select distinct TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE 
into  #CMIndexHull_third
FROM #CMIndexHull_second
where AircraftType is null and PrimaryUseId is null

 create index indx_1 on #CMIndexHull_third (VersionId	)

-----------------------------------------------------------------CMIndexLiability----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#CMIndexLiability') is not null
		drop table #CMIndexLiability

create table #CMIndexLiability (AircraftType	varchar(25)
,PrimaryUseId	varchar(25)
,GearType	varchar(25)
,TARGETCOLUMNNAME	varchar(100)
,VersionId	int
,RESULTVALUE money
,Fdate varchar(25)
,Xdate varchar(25))

insert into #CMIndexLiability
select *  FROM pricing_aim.dbo.r_CMIndexLiability


create index indx_1 on #CMIndexLiability (AircraftType	,PrimaryUseId	,GearType,VersionId	)


if OBJECT_ID('tempdb..#CMIndexLiability_second') is not null
		drop table #CMIndexLiability_second

select distinct AircraftType	
,PrimaryUseId		
,TARGETCOLUMNNAME	
,VersionId
,Fdate
,Xdate
,RESULTVALUE
into #CMIndexLiability_second
FROM #CMIndexLiability
where GearType is null


create index indx_1 on #CMIndexLiability_second (AircraftType	,PrimaryUseId	,VersionId	)


if OBJECT_ID('tempdb..#CMIndexLiability_third') is not null
		drop table #CMIndexLiability_third

select distinct 
TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #CMIndexLiability_third
FROM #CMIndexLiability_second
where AircraftType is null and PrimaryUseId is null

create index indx_1 on #CMIndexLiability_third (VersionId	)



-----------------------------------------------------------------CMIndexMedPay----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#CMIndexMedPay') is not null
		drop table #CMIndexMedPay

select * into #CMIndexMedPay FROM pricing_aim.dbo.r_CMIndexMedPay


create index indx_1 on #CMIndexMedPay (AircraftType	,PrimaryUseId	,GearType,VersionId	)

-----------------------------------------------------------------StdDiscountHull----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#StdDiscountHull') is not null
		drop table #StdDiscountHull

select * into #StdDiscountHull FROM pricing_aim.dbo.r_StdDiscountHull


create index indx_1 on #StdDiscountHull (AircraftType	,PrimaryUseId	,GearType,VersionId	)
-----------------------------------------------------------------StdDiscountLiab----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#StdDiscountLiab') is not null
		drop table #StdDiscountLiab

select * into #StdDiscountLiab FROM pricing_aim.dbo.r_StdDiscountLiab

create index indx_1 on #StdDiscountLiab (AircraftType	,PrimaryUseId	,GearType,VersionId	)

-----------------------------------------------------------------IsManual----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#IsManual') is not null
		drop table #IsManual

select * into #IsManual FROM pricing_aim.dbo.r_IsManual

create index indx_1 on #IsManual (AircraftType	,PrimaryUseId	,GearType,VersionId	)


if OBJECT_ID('tempdb..#IsManual_second') is not null
		drop table #IsManual_second

select AircraftType	
,PrimaryUseId		
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #IsManual_second
FROM #IsManual
where GearType is null

create index indx_1 on #IsManual_second (AircraftType	,PrimaryUseId	,VersionId	)



if OBJECT_ID('tempdb..#IsManual_third') is not null
		drop table #IsManual_third

select PrimaryUseId		
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #IsManual_third
FROM #IsManual
where GearType is null and AircraftType is null

create index indx_1 on #IsManual_third (PrimaryUseId	,VersionId	)


if OBJECT_ID('tempdb..#IsManual_fourth') is not null
		drop table #IsManual_fourth

select TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #IsManual_fourth
FROM #IsManual
where GearType is null and AircraftType is null and PrimaryUseId is null

create index indx_1 on #IsManual_fourth (VersionId	)



-----------------------------------------------------------------LiabilityOnlyModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#LiabilityOnlyModifier') is not null
		drop table #LiabilityOnlyModifier

select * into #LiabilityOnlyModifier FROM pricing_aim.dbo.r_LiabilityOnlyModifier

create index indx_1 on #LiabilityOnlyModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)
-----------------------------------------------------------------MinimumPremium----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#MinimumPremium') is not null
		drop table #MinimumPremium

select * into #MinimumPremium FROM pricing_aim.dbo.r_MinimumPremium

create index indx_1 on #MinimumPremium (AircraftType	,PrimaryUseId	,GearType,VersionId	)


if OBJECT_ID('tempdb..#minimumpremium_second') is not null
		drop table #minimumpremium_second

select distinct TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #minimumpremium_second
FROM #MinimumPremium
where AircraftType is null and GearType is null and PrimaryUseId is null

create index indx_1 on #minimumpremium_second (VersionId	)


-----------------------------------------------------------------PilotMinTotalHrsModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PilotMinTotalHrsModifier') is not null
		drop table #PilotMinTotalHrsModifier

select * into #PilotMinTotalHrsModifier FROM pricing_aim.[dbo].[r_totalhoursdiamond]

create index indx_1 on #PilotMinTotalHrsModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#PilotMinTotalHrsModifier_second') is not null
		drop table #PilotMinTotalHrsModifier_second


select distinct AircraftType	
,PrimaryUseId	
,PilotMinTotalHrsMin	
--,EntryOperator	
,PilotMinTotalHrsMax	
--,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotMinTotalHrsModifier_second
FROM #PilotMinTotalHrsModifier
where GearType is null
--where GearType=''

create index indx_1 on #PilotMinTotalHrsModifier_second (AircraftType	,PrimaryUseId	,VersionId	)

if OBJECT_ID('tempdb..#PilotMinTotalHrsModifier_third') is not null
		drop table #PilotMinTotalHrsModifier_third

-----------------------------------------------------------------PilotMMHrsModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PilotMMHrsModifier') is not null
		drop table #PilotMMHrsModifier

select * into #PilotMMHrsModifier FROM pricing_aim.dbo.r_PilotMMHrsModifier


create index indx_1 on #PilotMMHrsModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#PilotMMHrsModifier_second') is not null
		drop table #PilotMMHrsModifier_second

select distinct AircraftType	
,PrimaryUseId	
,PrimaryPilotRating	
,PilotMMHrsMin	
,EntryOperator	
,PilotMMHrsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotMMHrsModifier_second
FROM #PilotMMHrsModifier
where GearType is null

create index indx_1 on #PilotMMHrsModifier_second (AircraftType	,PrimaryUseId	,VersionId	)

if OBJECT_ID('tempdb..#PilotMMHrsModifier_third') is not null
		drop table #PilotMMHrsModifier_third

select distinct AircraftType		
,PrimaryPilotRating	
,PilotMMHrsMin	
,EntryOperator	
,PilotMMHrsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotMMHrsModifier_third
FROM #PilotMMHrsModifier
where GearType is null and PrimaryUseId is null

create index indx_1 on #PilotMMHrsModifier_third (AircraftType	,VersionId	)


-----------------------------------------------------------------PilotMEHrsModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PilotMEHrsModifier') is not null
		drop table #PilotMEHrsModifier

select * into #PilotMEHrsModifier FROM pricing_aim.[dbo].[r_PilotMEHrsModifierDiamond]
--pricing_aim.dbo.r_PilotMEHrsModifier$

create index indx_1 on #PilotMEHrsModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#PilotMEHrsModifier_second') is not null
		drop table #PilotMEHrsModifier_second

select distinct AircraftType	
,PrimaryUseId	
,PrimaryPilotRating	
,PilotMEHrsMin	
,EntryOperator	
,PilotMEHrsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotMEHrsModifier_second
FROM #PilotMEHrsModifier
where geartype is null

create index indx_1 on #PilotMEHrsModifier_second (AircraftType	,PrimaryUseId,VersionId	)

if OBJECT_ID('tempdb..#PilotMEHrsModifier_third') is not null
		drop table #PilotMEHrsModifier_third
		
select distinct AircraftType	
,PrimaryPilotRating	
,PilotMEHrsMin	
,EntryOperator	
,PilotMEHrsMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotMEHrsModifier_third
FROM #PilotMEHrsModifier
where geartype is null and PrimaryUseId is null

create index indx_1 on #PilotMEHrsModifier_third (AircraftType	,VersionId	)

-----------------------------------------------------------------PilotAgeMinModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PilotAgeMinModifier') is not null
		drop table #PilotAgeMinModifier

select * into #PilotAgeMinModifier FROM pricing_aim.dbo.r_PilotAgeMinModifier

create index indx_1 on #PilotAgeMinModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#PilotAgeMinModifier_second') is not null
		drop table #PilotAgeMinModifier_second

select distinct AircraftType	
,PrimaryUseId	
,PilotMinAgeMin	
,EntryOperator	
,PilotMinAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotAgeMinModifier_second
FROM #PilotAgeMinModifier where GearType is null

create index indx_1 on #PilotAgeMinModifier_second (AircraftType	,PrimaryUseId	,VersionId	)

if OBJECT_ID('tempdb..#PilotAgeMinModifier_third') is not null
		drop table #PilotAgeMinModifier_third

select distinct AircraftType	
,PilotMinAgeMin	
,EntryOperator	
,PilotMinAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotAgeMinModifier_third
FROM #PilotAgeMinModifier where GearType is null and PrimaryUseId is null

create index indx_1 on #PilotAgeMinModifier_third (AircraftType,	VersionId	)

if OBJECT_ID('tempdb..#PilotAgeMinModifier_fourth') is not null
		drop table #PilotAgeMinModifier_fourth

select distinct PilotMinAgeMin	
,EntryOperator	
,PilotMinAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotAgeMinModifier_fourth
FROM #PilotAgeMinModifier where GearType is null and PrimaryUseId is null and AircraftType is null

create index indx_1 on #PilotAgeMinModifier_fourth (VersionId	)
-----------------------------------------------------------------PilotAgeMaxModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PilotAgeMaxModifier') is not null
		drop table #PilotAgeMaxModifier

select * into #PilotAgeMaxModifier FROM pricing_aim.dbo.r_PilotAgeMaxModifier

create index indx_1 on #PilotAgeMaxModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#PilotAgeMaxModifier_second') is not null
		drop table #PilotAgeMaxModifier_second

select distinct AircraftType	
,PrimaryUseId	
,PilotMaxAgeMin	
,EntryOperator	
,PilotMaxAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotAgeMaxModifier_second
FROM #PilotAgeMaxModifier
where GearType is null

create index indx_1 on #PilotAgeMaxModifier_second (AircraftType	,PrimaryUseId	,VersionId	)

if OBJECT_ID('tempdb..#PilotAgeMaxModifier_third') is not null
		drop table #PilotAgeMaxModifier_third

select distinct AircraftType	
,PilotMaxAgeMin	
,EntryOperator	
,PilotMaxAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotAgeMaxModifier_third
FROM #PilotAgeMaxModifier
where GearType is null and PrimaryUseId is null

create index indx_1 on #PilotAgeMaxModifier_third (AircraftType	,VersionId	)


if OBJECT_ID('tempdb..#PilotAgeMaxModifier_fourth') is not null
		drop table #PilotAgeMaxModifier_fourth

select distinct PilotMaxAgeMin	
,EntryOperator	
,PilotMaxAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotAgeMaxModifier_fourth
FROM #PilotAgeMaxModifier
where GearType is null and AircraftType is null and PrimaryUseId is null

create index indx_1 on #PilotAgeMaxModifier_fourth (VersionId	)

--select * from #PilotAgeMaxModifier
--select * from #PilotAgeMaxModifier_second
--select * from #PilotAgeMaxModifier_third
--select * from #PilotAgeMaxModifier_fourth
-----------------------------------------------------------------PilotGearHrsModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PilotGearHrsModifier') is not null
		drop table #PilotGearHrsModifier

select * into #PilotGearHrsModifier FROM pricing_aim.dbo.r_PilotGearHrsModifier

create index indx_1 on #PilotGearHrsModifier (AircraftType	,PrimaryUseId	,GearType,PrimaryPilotRating,VersionId	)

if OBJECT_ID('tempdb..#PilotGearHrsModifier_second') is not null
		drop table #PilotGearHrsModifier_second

		select distinct AircraftType	
		,PrimaryUseId		
		,PrimaryPilotRating	
		,PilotGearHrsMin	
		,EntryOperator	
		,PilotGearHrsMax	
		,TARGETCOLUMNNAME	
		,VersionId	
		,Fdate
		,Xdate
		,RESULTVALUE
		into #PilotGearHrsModifier_second
FROM #PilotGearHrsModifier where GearType is null

create index indx_1 on #PilotGearHrsModifier_second (AircraftType	,PrimaryUseId	,PrimaryPilotRating,VersionId	)


if OBJECT_ID('tempdb..#PilotGearHrsModifier_third') is not null
		drop table #PilotGearHrsModifier_third

		select distinct AircraftType		
		,PrimaryPilotRating	
		,PilotGearHrsMin	
		,EntryOperator	
		,PilotGearHrsMax	
		,TARGETCOLUMNNAME	
		,VersionId	
		,Fdate
		,Xdate
		,RESULTVALUE
		into #PilotGearHrsModifier_third
FROM #PilotGearHrsModifier where GearType is null and PrimaryUseId is null

create index indx_1 on #PilotGearHrsModifier_third (AircraftType,PrimaryPilotRating,VersionId	)

-----------------------------------------------------------------HullModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#HullModifier') is not null
		drop table #HullModifier

select * into #HullModifier FROM pricing_aim.dbo.r_HullModifier

create index indx_1 on #HullModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#HullModifier_second') is not null
		drop table #HullModifier_second

select distinct AircraftType	
,PrimaryUseId		
,HullAgeMin	
,EntryOperator	
,HullAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #HullModifier_second
FROM #HullModifier where GearType='' or GearType is null

create index indx_1 on #HullModifier_second (AircraftType	,PrimaryUseId	,VersionId	)


if OBJECT_ID('tempdb..#HullModifier_third') is not null
		drop table #HullModifier_third

select distinct PrimaryUseId	
,HullAgeMin	
,EntryOperator	
,HullAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #HullModifier_third
FROM #HullModifier where (GearType='' or GearType is null) and (AircraftType='' or AircraftType is null)

create index indx_1 on #HullModifier_third (PrimaryUseId	,VersionId	)



if OBJECT_ID('tempdb..#HullModifier_fourth') is not null
		drop table #HullModifier_fourth

select distinct HullAgeMin	
,EntryOperator	
,HullAgeMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #HullModifier_fourth
FROM #HullModifier where (GearType='' or GearType is null) and (PrimaryUseId='' or PrimaryUseId is null) and (AircraftType='' or AircraftType is null)

create index indx_1 on #HullModifier_fourth (VersionId	)



-----------------------------------------------------------------GroundOnlyModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#GroundOnlyModifier') is not null
		drop table #GroundOnlyModifier

select * into #GroundOnlyModifier FROM pricing_aim.dbo.r_DiaGroundOnlyModifier

--create index indx_1 on #GroundOnlyModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)
-----------------------------------------------------------------PilotIFRModifier----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#PilotIFRModifier') is not null
		drop table #PilotIFRModifier

select * into #PilotIFRModifier FROM pricing_aim.dbo.r_DiaPilotIFRModifier

create index indx_1 on #PilotIFRModifier (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#PilotIFRModifier_second') is not null
		drop table #PilotIFRModifier_second

select distinct AircraftType	
,PrimaryUseId		
,PrimaryPilotRating	
,PilotMinIFR	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotIFRModifier_second
from #PilotIFRModifier
where GearType is null

create index indx_1 on #PilotIFRModifier_second (AircraftType	,PrimaryUseId	,VersionId	)

if OBJECT_ID('tempdb..#PilotIFRModifier_third') is not null
		drop table #PilotIFRModifier_third

select distinct AircraftType		
,PrimaryPilotRating	
,PilotMinIFR	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #PilotIFRModifier_third
from #PilotIFRModifier
where GearType is null and PrimaryUseId is null

create index indx_1 on #PilotIFRModifier_third (AircraftType	,VersionId	)
-----------------------------------------------------------------HullBaseRate----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#HullBaseRate') is not null
		drop table #HullBaseRate

select AircraftType	
,PrimaryUseId	
,GearType	
,HullValueMin	
,isnull(HullValueMax,999999999)	 HullValueMax
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,fdate_ren
,xdate_ren
,RESULTVALUE
into #HullBaseRate FROM pricing_aim.dbo.r_DiaHullBaseRate_NR


create index indx_1 on #HullBaseRate (AircraftType	,PrimaryUseId	,GearType,VersionId	)

if OBJECT_ID('tempdb..#HullBaseRate_second') is not null
		drop table #HullBaseRate_second


select distinct AircraftType	
,PrimaryUseId		
,HullValueMin	
,HullValueMax
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,fdate_ren
,xdate_ren
,RESULTVALUE
into #HullBaseRate_second FROM #HullBaseRate where GearType is null
 

create index indx_1 on #HullBaseRate_second (AircraftType	,PrimaryUseId	,VersionId	)

-----------------------------------------------------------------LiabBaseRate----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#LiabBaseRate') is not null
		drop table #LiabBaseRate

select AircraftType	
,PrimaryUseId	
,isnull(GearType,'') geartype
,SeatIndex	
,PassengerLimitText	
,LiabOccurLimitMin	
--,EntryOperator	
--,isnull(LiabOccurLimitMax,999999999) LiabOccurLimitMax
,TARGETCOLUMNNAME	
,34 VersionId	
,Fdate
,Xdate
,RESULTVALUE
 into #LiabBaseRate 
 FROM pricing_aim.dbo.r_DiaLiabBaseRate --pricing_aim.dbo.r_DiaLiabBaseRate$


  update #LiabBaseRate
 set PassengerLimitText = case when PassengerLimitText = 'Included' then 1 --included
								when PassengerLimitText = 'Excluded' then 2 --excluded
								else PassengerLimitText
								end

alter table #LiabBaseRate
alter column PassengerLimitText int

 create index indx_1 on #LiabBaseRate (AircraftType	,PrimaryUseId,SeatIndex,PassengerLimitText		,GearType,VersionId	)

 if OBJECT_ID('tempdb..#LiabBaseRate_second') is not null
		drop table #LiabBaseRate_second
		

select distinct AircraftType	
,PrimaryUseId		
,SeatIndex	
,PassengerLimitText	
,LiabOccurLimitMin	
--,EntryOperator	
--,LiabOccurLimitMax
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE 
into #LiabBaseRate_second
FROM #LiabBaseRate where GearType=''

 create index indx_1 on #LiabBaseRate_second (AircraftType	,PrimaryUseId	,SeatIndex,PassengerLimitText	,VersionId	)
-- select * from #LiabBaseRate where AircraftType = 8 and PrimaryUseId = 1 and geartype = 'R'
-----------------------------------------------------------------LiabBaseAddtlseat----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#LiabBaseAddtlSeat') is not null
		drop table #LiabBaseAddtlSeat

select AircraftType	
,PrimaryUseId	
,isnull(GearType,'') GearType
,PassengerLimitText	
,TARGETCOLUMNNAME	
,over_indexseat	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #LiabBaseAddtlSeat FROM pricing_aim.dbo.r_Liab_addtlseatprem$

update #LiabBaseAddtlSeat
set PassengerLimitText = case when PassengerLimitText = 100000 then 100000
								when PassengerLimitText = 200000 then 200000
								when PassengerLimitText = 250000 then 250000
								when PassengerLimitText is null then 1
								else PassengerLimitText 
								end

create index indx_1 on #LiabBaseAddtlSeat (AircraftType	,PrimaryUseId,PassengerLimitText		,GearType,VersionId	)


if OBJECT_ID('tempdb..#LiabBaseAddtlSeat_second') is not null
		drop table #LiabBaseAddtlSeat_second

select AircraftType	
,PrimaryUseId	
,PassengerLimitText	
,TARGETCOLUMNNAME	
,over_indexseat	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE 
into #LiabBaseAddtlSeat_second
FROM #LiabBaseAddtlSeat where GearType=''

 create index indx_1 on #LiabBaseAddtlSeat_second (AircraftType	,PrimaryUseId,PassengerLimitText,		VersionId	)


-----------------------------------------------------------------MedPayBaseRate----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#MedPayBaseRate') is not null
		drop table #MedPayBaseRate

select AircraftType	
,PrimaryUseId	
,isnull(GearType,'')  GearType	
,SeatIndex	
,MedPayLimitMin	
,isnull(MedPayLimitMax,999999999) MedPayLimitMax
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #MedPayBaseRate FROM pricing_aim.dbo.r_DiaMedPayBaseRate

 create index indx_1 on #MedPayBaseRate (AircraftType	,PrimaryUseId,GearType,VersionId	)


 if OBJECT_ID('tempdb..#MedPayBaseRate_second') is not null
		drop table #MedPayBaseRate_second

select AircraftType	
,PrimaryUseId	
,isnull(GearType,'')  GearType	
,MedPayLimitMin	
,isnull(MedPayLimitMax,999999999) MedPayLimitMax
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE
into #MedPayBaseRate_second FROM #MedPayBaseRate
where SeatIndex is null

 create index indx_1 on #MedPayBaseRate_second (AircraftType	,PrimaryUseId,GearType,VersionId	)


if OBJECT_ID('tempdb..#MedPayBaseRate_third') is not null
		drop table #MedPayBaseRate_third

select AircraftType	
,PrimaryUseId	
,SeatIndex
,MedPayLimitMin	
,MedPayLimitMax	
,TARGETCOLUMNNAME	
,VersionId	
,Fdate
,Xdate
,RESULTVALUE 
into #MedPayBaseRate_third
FROM #MedPayBaseRate where GearType=''

 create index indx_1 on #MedPayBaseRate_third (AircraftType	,PrimaryUseId,VersionId	)

 alter table #MedPayBaseRate
alter column MedPayLimitMin int

alter table #MedPayBaseRate
alter column MedPayLimitMax int

alter table #MedPayBaseRate_second
alter column MedPayLimitMin int

alter table #MedPayBaseRate_second
alter column MedPayLimitMax int

alter table #MedPayBaseRate_third
alter column MedPayLimitMin int

alter table #MedPayBaseRate_third
alter column MedPayLimitMax int

-----------------------------------------------------------------Coastal----------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#Coastal') is not null
		drop table #Coastal

		select * into #Coastal FROM pricing_aim.dbo.r_coastal$

		 create index indx_1 on #Coastal ([Airport_State],[Airport_Coastal_Flag],Versionid	)


--------------------------------------------------------------------Aircraft Type Modifier--------------------------------------------------------------------------------------
if OBJECT_ID('tempdb..#Aircraft_Type_Modifier') is not null
		drop table #Aircraft_Type_Modifier

		select * into #Aircraft_Type_Modifier FROM pricing_aim.dbo.r_TypeDiamond

		 create index indx_1 on #Aircraft_Type_Modifier (AircraftType,PrimaryUseId,GearType	)

if OBJECT_ID('tempdb..#Aircraft_Type_Modifier_second') is not null
		drop table #Aircraft_Type_Modifier_second

select AircraftType
, PrimaryUseId
,Fdate
,Xdate
, RESULTVALUE
into #Aircraft_Type_Modifier_second
from #Aircraft_Type_Modifier where GearType is null

		 create index indx_1 on #Aircraft_Type_Modifier_second (AircraftType,PrimaryUseId	)

 -----------------------------------------------------------------deductible offset factor----------------------------------------------------------------------------------------------------

 if OBJECT_ID('tempdb..#ded_base_model_1') is not null
	drop table #ded_base_model_1

 if OBJECT_ID('tempdb..#ded_base_model_2') is not null
	drop table #ded_base_model_2

 if OBJECT_ID('tempdb..#ded_base_model_3') is not null
	drop table #ded_base_model_3

 if OBJECT_ID('tempdb..#ded_base_age_1') is not null
	drop table #ded_base_age_1

 if OBJECT_ID('tempdb..#ded_base_type_1') is not null
	drop table #ded_base_type_1

 if OBJECT_ID('tempdb..#ded_base_type_2') is not null
	drop table #ded_base_type_2

 if OBJECT_ID('tempdb..#ded_base_type_3') is not null
	drop table #ded_base_type_3



select ModelID	
,ModelCode	
,Manufacturer	
,Model	
,[Use]	
,[Type]	
,Base_ded	
,eff_date as Fdate
,exp_date as Xdate
 into #ded_base_model_1
 FROM pricing_aim.[dbo].[r_base_ded_model$]

 select ModelID	
,ModelCode	
,Manufacturer	
,Model	
,[Use]	
,Base_ded	
,eff_date as Fdate	 
,exp_date as Xdate
 into #ded_base_model_2
 FROM pricing_aim.[dbo].[r_base_ded_model$]
 where type is null

 select ModelCode	
,Manufacturer	
,Model	
,[Use]	
,Base_ded	
,eff_date as Fdate		
,exp_date as Xdate
 into #ded_base_model_3
 FROM pricing_aim.[dbo].[r_base_ded_model$]
 where type is null and modelid is null

 select [Aircraft type]
 ,[Age Low]
 ,[Age High]	
 ,[Min Ded]	
 ,eff_date as Fdate	
 ,exp_date as Xdate
 into #ded_base_age_1
 FROM pricing_aim.[dbo].[r_base_ded_age$]

 select [AIRCRAFT DESCRIPTION]	
 ,[GEAR TYPE]	
 ,[Use]	
 ,[Type]	
 ,[Deductible Type]	
 ,eff_date as Fdate
 ,exp_date as Xdate
 ,[Deductible]
 into #ded_base_type_1
 FROM pricing_aim.[dbo].[r_base_ded_type$$]

 select [AIRCRAFT DESCRIPTION]		
 ,[Use]	
 ,[Type]	
 ,[Deductible Type]	
 ,eff_date as Fdate
 ,exp_date as Xdate
 ,[Deductible]
 into #ded_base_type_2
 FROM pricing_aim.[dbo].[r_base_ded_type$$]
 where [GEAR TYPE] is null

 select [AIRCRAFT DESCRIPTION]		
 ,[Use]		
 ,[Deductible Type]	
 ,eff_date as Fdate
 ,exp_date as Xdate
 ,[Deductible]
 into #ded_base_type_3
 FROM pricing_aim.[dbo].[r_base_ded_type$$]
 where [GEAR TYPE] is null and [Type] is null

-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
--Creating main dataset for rerating
if OBJECT_ID('tempdb.dbo.#temp01') is not null drop table #temp01
select *
,case when a.aircraft_type_description = 'MEL TP' or a.aircraft_type_description = 'MEL Jet' then a.Min_FW_TP
		when a.aircraft_type_description = 'MEL LT' then a.Min_ME_Total
		when a.aircraft_type_description = 'SELRG ne 200 hp' or a.aircraft_type_description = 'EXP RG' or a.aircraft_type_description = 'SEL TurboProp' or a.aircraft_type_description = 'SELRG xs 200 hp' then a.Min_RG
		when a.aircraft_type_description = 'EXP FG' and a.gear_type_dscr = 'Retractable' then a.Min_RG
		when a.aircraft_type_description = 'RW Piston' or a.aircraft_type_description = 'RW Turbine' or a.aircraft_type_description = 'GYRO' then a.Min_RW_Total
		when a.aircraft_type_description = 'SES ne 235 hp' or a.aircraft_type_description = 'SES xs 235 hp' then a.Min_SEA_AMPH
		when (a.aircraft_type_description = 'SELFG ne 200 hp' or a.aircraft_type_description = 'SELFG xs 200 hp' or a.aircraft_type_description = 'EXP FG' or a.aircraft_type_description = 'LSA') and a.gear_type_dscr = 'Tailwheel'  then a.Min_TW
		when a.aircraft_type_description = 'SELACRO' then a.Min_TW
		end gearhour
,case when gear_type_dscr = 'Tricycle' then 'T'
		when gear_type_dscr = 'Tailwheel' then 'C'
		when gear_type_dscr = 'Retractable' then 'R'
		when gear_type_dscr = 'Amphibious' Then 'A'
		when gear_type_dscr = 'Floats' Then 'F'
		when gear_type_dscr = 	'Skids-RW' then 'S'
		else 'Q' end gear_type_rating
,case when SpecialUse_Code = 0 then 3 else SpecialUse_Code end as Primary_use_rating
,aircrafttype_id-2 aircraft_type_rating
,case when a.Coverage_group = 'GRO-Flight' THEN a.in_motion_deductible
		when a.Coverage_group = 'GRO-Taxi' then a.in_motion_deductible
		when a.Coverage_group = 'GRO-NIM' then a.not_in_motion_deductible
		else null
		end selected_deductible
--,case when SpecialUse_Code = 0 then 3 else SpecialUse_Code end as Primary_use_rating_True
into #temp01
 FROM #temp00 a

create index indx_1 on #temp01 (gear_type_rating, aircraft_type_rating,  Primary_use_rating)

update #temp01
set selected_deductible = case when selected_deductible < 1 then selected_deductible * hull_value
								else selected_deductible
								end
update #temp01
set CSL_Occurance_Limit = REPLACE(isnull(CSL_Occurance_Limit,0),',','')

update #temp01
set Med_Passenger_Limit_description = case when Med_Passenger_Limit_description = 'No Coverage' or Med_Passenger_Limit_description is null then 0 else REPLACE(Med_Passenger_Limit_description,',','') end

update #temp01
set CSL_Passenger_Limit_description = case when CSL_Passenger_Limit_description = 'Excluded' then 2  
											when CSL_Passenger_Limit_description = 'Included' then 1
											when CSL_Passenger_Limit_description is null or CSL_Passenger_Limit_description = '' then 2
											else replace(CSL_Passenger_Limit_description,',','')
											end

update #temp01
set max_age = case when max_age < 0 then 0
								else max_age
								end

update #temp01
set min_age = case when min_age < 0 then 0
								else min_age
								end


alter table #temp01
alter column CSL_Occurance_Limit int

alter table #temp01
alter column Med_Passenger_Limit_description int

alter table #temp01
alter column CSL_Passenger_Limit_description int

--------------------------------------------------------------------------------------------------
 --rerating factors at date of writing
if OBJECT_ID('tempdb.dbo.#temp02') is not null drop table #temp02
 select a.*
 ,v.versionid r_versionid
 ,v.eff_date r_version_eff_date
 ,isnull(b.RESULTVALUE,isnull(c.RESULTVALUE,0)) r_AircraftModelModifierHull 
 ,isnull(b1.RESULTVALUE,isnull(c1.RESULTVALUE,0)) r_AircraftModelModifierLiab
 ,isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) r_SeatIndex
 ,isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE))) r_PrimaryPilotRating 
 ,0 r_airport_modifier 
 ,isnull(b4.RESULTVALUE,isnull(c4.RESULTVALUE,d4.RESULTVALUE)) r_CMIndexHull 
 ,isnull(b5.RESULTVALUE,isnull(c5.RESULTVALUE,d5.RESULTVALUE)) r_CMIndexLiability 
 ,b6.RESULTVALUE r_CMIndexMedPay 
 ,b7.RESULTVALUE r_StdDiscountHull 
 ,b8.RESULTVALUE r_StdDiscountLiab
 ,isnull(b9.RESULTVALUE,isnull(c9.RESULTVALUE,isnull(d9.RESULTVALUE,e9.RESULTVALUE))) r_IsManual 
 ,b10.RESULTVALUE r_LiabilityOnlyModifier 
 ,isnull(b11.RESULTVALUE,c11.RESULTVALUE) r_MinimumPremium 
 ,isnull(b12.RESULTVALUE,c12.RESULTVALUE) r_PilotMinTotalHrsModifier
 ,isnull(b13.RESULTVALUE,isnull(c13.RESULTVALUE,d13.RESULTVALUE)) r_PilotMMHrsModifier
 ,isnull(b14.RESULTVALUE,isnull(c14.RESULTVALUE,d14.RESULTVALUE)) r_PilotMEHrsModifier
 ,isnull(b15.RESULTVALUE,isnull(c15.RESULTVALUE,isnull(d15.RESULTVALUE,e15.RESULTVALUE))) r_PilotAgeMinModifier
 ,isnull(b16.RESULTVALUE,isnull(c16.RESULTVALUE,isnull(d16.RESULTVALUE,e16.RESULTVALUE))) r_PilotAgeMaxModifier
 ,isnull(b17.RESULTVALUE,isnull(c17.RESULTVALUE,isnull(d17.RESULTVALUE,e17.RESULTVALUE))) r_HullModifier
 ,b18.RESULTVALUE r_Ground_Modifier
 ,isnull(b19.RESULTVALUE,c19.RESULTVALUE) r_HullBaseRate
 ,isnull(b20.RESULTVALUE,c20.RESULTVALUE) r_LiabBaseRate
 ,isnull(b21.RESULTVALUE,c21.RESULTVALUE) r_LiabBaseAddtlSeat  
 ,isnull(b22.RESULTVALUE,isnull(c22.RESULTVALUE,d22.RESULTVALUE)) r_MedPayBaseRate  
 ,isnull(b23.RESULTVALUE,isnull(c23.RESULTVALUE,d23.RESULTVALUE)) r_PilotIFRModifier
 ,round(isnull(b24.RESULTVALUE,isnull(c24.RESULTVALUE,d24.RESULTVALUE)),4) r_PilotMinGearHrsModifier
 ,b25.rate r_coastal_factor
 ,isnull(c28.RESULTVALUE,d28.RESULTVALUE) r_AircraftTypeModifier
 ,isnull(c25.[Base_ded],isnull(d25.[Base_ded],e25.[Base_ded])) r_BaseModelDeductible
 ,c26.[Min Ded] r_BaseAgeDeductible
 ,isnull(c27.[Deductible],isnull(d27.[Deductible],e27.[Deductible])) r_BaseTypeDeductible
 into #temp02
FROM #temp01 a
 left join #version v on a.date_pol_eff between v.eff_date and v.exp_date
 left join #AircraftModelModifierHull b on b.AircraftType=a.aircraft_type_rating and b.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b.GearType and a.Model_Code=b.ModelCode and a.date_pol_eff between b.Fdate and b.Xdate--b.VersionId=v.versionid
 left join #AircraftModelModifierHull_ex_gear c on c.AircraftType=a.aircraft_type_rating and c.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c.ModelCode and a.date_pol_eff between c.Fdate and c.Xdate--and c.VersionId=v.versionid
 left join #AircraftModelModifierLiab b1 on b1.AircraftType=a.aircraft_type_rating and b1.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b1.GearType and a.Model_Code=b1.ModelCode and a.date_pol_eff between b1.Fdate and b1.Xdate--b1.VersionId=v.versionid
 left join #AircraftModelModifierLiab_ex_gear c1 on c1.AircraftType=a.aircraft_type_rating and c1.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c1.ModelCode  and a.date_pol_eff between c1.Fdate and c1.Xdate--c1.VersionId=v.versionid
 left join #SeatIndex b2 on b2.AircraftType=a.aircraft_type_rating and b2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between b2.NoOfSeatsMin and case when b2.NoOfSeatsMax is null then 999999999 else b2.NoOfSeatsMax end and a.date_pol_eff between b2.Fdate and b2.Xdate--b2.VersionId=v.versionid
 left join #SeatIndex_second c2 on  c2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between c2.NoOfSeatsMin and case when c2.NoOfSeatsMax is null then 999999999 else c2.NoOfSeatsMax end and a.date_pol_eff between c2.Fdate and c2.Xdate --c2.VersionId=v.versionid
 left join #PrimaryPilotRating b3 on b3.AircraftType=a.aircraft_type_rating and b3.PrimaryUseId=a.Primary_use_rating and b3.GearType=a.gear_type_rating and cast(a.Min_Total_Hours as int) between b3.PilotMinTotalHrsMin and case when b3.PilotMinTotalHrsMax is null then 999999999 else b3.PilotMinTotalHrsMax end and a.date_pol_eff between b3.Fdate and b3.Xdate --b3.VersionId=v.versionid
 left join #PrimaryPilotRating_second c3 on  c3.AircraftType=a.aircraft_type_rating and c3.PrimaryUseId=a.Primary_use_rating and cast(a.Min_Total_Hours as int) between c3.PilotMinTotalHrsMin and case when c3.PilotMinTotalHrsMax is null then 999999999 else c3.PilotMinTotalHrsMax end and a.date_pol_eff between c3.Fdate and c3.Xdate--c3.VersionId=v.versionid
 left join #PrimaryPilotRating_third d3 on  d3.AircraftType=a.aircraft_type_rating and cast(a.Min_Total_Hours as int) between d3.PilotMinTotalHrsMin and case when d3.PilotMinTotalHrsMax is null then 999999999 else d3.PilotMinTotalHrsMax end and a.date_pol_eff between d3.Fdate and d3.Xdate--d3.VersionId=v.versionid
 left join #PrimaryPilotRating_fourth e3 on  cast(a.Min_Total_Hours as int) between e3.PilotMinTotalHrsMin and case when e3.PilotMinTotalHrsMax is null then 999999999 else e3.PilotMinTotalHrsMax end and a.date_pol_eff between e3.Fdate and e3.Xdate--e3.VersionId=v.versionid
 left join #CMIndexHull b4 on b4.AircraftType=a.aircraft_type_rating and b4.PrimaryUseId=a.Primary_use_rating and b4.GearType=a.gear_type_rating and a.date_pol_eff between b4.Fdate and b4.Xdate--b4.VersionId=v.versionid
 left join #CMIndexHull_second c4 on  c4.AircraftType=a.aircraft_type_rating and c4.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c4.Fdate and c4.Xdate--c4.VersionId=v.versionid
 left join #CMIndexHull_third d4 on a.date_pol_eff between d4.Fdate and d4.Xdate-- d4.VersionId=v.versionid
 left join #CMIndexLiability b5 on b5.AircraftType=a.aircraft_type_rating and b5.PrimaryUseId=a.Primary_use_rating and b5.GearType=a.gear_type_rating and a.date_pol_eff between b5.Fdate and b5.Xdate--b5.VersionId=v.versionid
 left join #CMIndexLiability_second c5 on  c5.AircraftType=a.aircraft_type_rating and c5.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c5.Fdate and c5.Xdate-- c5.VersionId=v.versionid
 left join #CMIndexLiability_third d5 on a.date_pol_eff between d5.Fdate and d5.Xdate-- d5.VersionId=v.versionid
 left join #CMIndexMedPay b6 on a.date_pol_eff between b6.Fdate and b6.Xdate --b6.VersionId=v.versionid
 left join #StdDiscountHull b7 on a.date_pol_eff between b7.Fdate and b7.Xdate --b7.VersionId=v.versionid
 left join #StdDiscountLiab b8 on a.date_pol_eff between b8.Fdate and b8.Xdate  --b8.VersionId=v.versionid
 left join #IsManual b9 on b9.AircraftType=a.aircraft_type_rating and b9.PrimaryUseId=a.Primary_use_rating and b9.GearType=a.gear_type_rating and a.date_pol_eff between b9.Fdate and b9.Xdate--b9.VersionId=v.versionid
 left join #IsManual_second c9 on c9.AircraftType=a.aircraft_type_rating and c9.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c9.Fdate and c9.Xdate--c9.VersionId=v.versionid
 left join #IsManual_third d9 on d9.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between d9.Fdate and d9.Xdate--d9.VersionId=v.versionid
 left join #IsManual_fourth e9 on a.date_pol_eff between e9.Fdate and e9.Xdate--e9.VersionId=v.versionid
 left join #LiabilityOnlyModifier b10 on b10.HullValue = a.hull_value and a.date_pol_eff between b10.Fdate and b10.Xdate--b10.VersionId=v.versionid
 left join #MinimumPremium b11 on b11.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between b11.Fdate and b11.Xdate--b11.VersionId=v.versionid
 left join #MinimumPremium_second c11 on a.date_pol_eff between c11.Fdate and c11.Xdate--c11.VersionId=v.versionid
 left join #PilotMinTotalHrsModifier b12 on b12.AircraftType=a.aircraft_type_rating and b12.PrimaryUseId=a.Primary_use_rating and b12.GearType=a.gear_type_rating and a.date_pol_eff between b12.Fdate and b12.Xdate --b12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between b12.PilotMinTotalHrsMin and case when isnull(b12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else b12.PilotMinTotalHrsMax end
 left join #PilotMinTotalHrsModifier_second c12 on c12.AircraftType=a.aircraft_type_rating and c12.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c12.Fdate and c12.Xdate --c12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between c12.PilotMinTotalHrsMin and case when isnull(c12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else c12.PilotMinTotalHrsMax end
 left join #PilotMMHrsModifier b13 on b13.AircraftType=a.aircraft_type_rating and b13.PrimaryUseId=a.Primary_use_rating and b13.GearType=a.gear_type_rating and a.date_pol_eff between b13.Fdate and b13.Xdate --b13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between b13.PilotMMHrsMin and case when b13.PilotMMHrsMax = 'NULL' then 999999999 else b13.PilotMMHrsMax end and b13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_second c13 on c13.AircraftType=a.aircraft_type_rating and c13.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c13.Fdate and c13.Xdate--c13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between c13.PilotMMHrsMin and case when c13.PilotMMHrsMax = 'NULL' then 999999999 else c13.PilotMMHrsMax end  and c13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_third d13 on d13.AircraftType=a.aircraft_type_rating and a.date_pol_eff between d13.Fdate and d13.Xdate--d13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between d13.PilotMMHrsMin and case when d13.PilotMMHrsMax = 'NULL' then 999999999 else d13.PilotMMHrsMax end  and d13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier b14 on b14.AircraftType=a.aircraft_type_rating and b14.PrimaryUseId=a.Primary_use_rating and b14.GearType=a.gear_type_rating and a.date_pol_eff between b14.Fdate and b14.Xdate--b14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between b14.PilotMEHrsMin and case when b14.PilotMEHrsMax = 'NULL' or b14.PilotMEHrsMax is null then 999999999 else b14.PilotMEHrsMax end and b14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_second c14 on c14.AircraftType=a.aircraft_type_rating and c14.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c14.Fdate and c14.Xdate--c14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between c14.PilotMEHrsMin and case when c14.PilotMEHrsMax = 'NULL' or c14.PilotMEHrsMax is null then 999999999 else c14.PilotMEHrsMax end  and c14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_third d14 on d14.AircraftType=a.aircraft_type_rating and a.date_pol_eff between d14.Fdate and d14.Xdate--d14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between d14.PilotMEHrsMin and case when d14.PilotMEHrsMax = 'NULL' or d14.PilotMEHrsMax is null then 999999999 else d14.PilotMEHrsMax end  and d14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotAgeMinModifier b15 on b15.AircraftType=a.aircraft_type_rating and b15.PrimaryUseId=a.Primary_use_rating and b15.GearType=a.gear_type_rating and a.date_pol_eff between b15.Fdate and b15.Xdate--b15.VersionId=v.versionid
			and cast(a.min_age as int) between b15.PilotMinAgeMin and case when b15.PilotMinAgeMax = 'NULL' then 999999999 else b15.PilotMinAgeMax end 
 left join #PilotAgeMinModifier_second c15 on c15.AircraftType=a.aircraft_type_rating and c15.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c15.Fdate and c15.Xdate--c15.VersionId=v.versionid
			and cast(a.min_age as int) between c15.PilotMinAgeMin and case when c15.PilotMinAgeMax = 'NULL' then 999999999 else c15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_third d15 on d15.AircraftType=a.aircraft_type_rating and a.date_pol_eff between d15.Fdate and d15.Xdate--d15.VersionId=v.versionid
			and cast(a.min_age as int) between d15.PilotMinAgeMin and case when d15.PilotMinAgeMax = 'NULL' then 999999999 else d15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_fourth e15 on a.date_pol_eff between e15.Fdate and e15.Xdate--e15.VersionId=v.versionid 
			and cast(a.min_age as int) between e15.PilotMinAgeMin and case when e15.PilotMinAgeMax = 'NULL' then 999999999 else e15.PilotMinAgeMax end  
 left join #PilotAgeMaxModifier b16 on b16.AircraftType=a.aircraft_type_rating and b16.PrimaryUseId=a.Primary_use_rating and b16.GearType=a.gear_type_rating and a.date_pol_eff between b16.Fdate and b16.Xdate--b16.VersionId=v.versionid
			and cast(a.max_age as int) between b16.PilotMaxAgeMin and case when b16.PilotMaxAgeMax = 'NULL' then 999999999 else b16.PilotMaxAgeMax end 
 left join #PilotAgeMaxModifier_second c16 on c16.AircraftType=a.aircraft_type_rating and c16.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c16.Fdate and c16.Xdate--c16.VersionId=v.versionid
			and cast(a.max_age as int) between c16.PilotMaxAgeMin and case when c16.PilotMaxAgeMax = 'NULL' then 999999999 else c16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_third d16 on d16.AircraftType=a.aircraft_type_rating and a.date_pol_eff between d16.Fdate and d16.Xdate--d16.VersionId=v.versionid
			and cast(a.max_age as int) between d16.PilotMaxAgeMin and case when d16.PilotMaxAgeMax = 'NULL' then 999999999 else d16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_fourth e16 on a.date_pol_eff between e16.Fdate and e16.Xdate --e16.VersionId=v.versionid 
			and cast(a.max_age as int) between e16.PilotMaxAgeMin and case when e16.PilotMaxAgeMax = 'NULL' then 999999999 else e16.PilotMaxAgeMax end  
 left join #HullModifier b17 on b17.AircraftType=a.aircraft_type_rating and b17.PrimaryUseId=a.Primary_use_rating and b17.GearType=a.gear_type_rating and a.date_pol_eff between b17.Fdate and b17.Xdate--b17.VersionId=v.versionid
			and a.model_age between b17.HullAgeMin and case when isnull(b17.HullAgeMax,'Null') = 'NULL' then 999999999 else b17.HullAgeMax end 
 left join #HullModifier_second c17 on c17.AircraftType=a.aircraft_type_rating and c17.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c17.Fdate and c17.Xdate--c17.VersionId=v.versionid
			and a.model_age between c17.HullAgeMin and case when isnull(c17.HullAgeMax,'Null') = 'NULL' then 999999999 else c17.HullAgeMax end 
 left join #HullModifier_third d17 on d17.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between d17.Fdate and d17.Xdate --d17.VersionId=v.versionid
			and a.model_age between d17.HullAgeMin and case when isnull(d17.HullAgeMax,'Null') = 'NULL' then 999999999 else d17.HullAgeMax end 
 left join #HullModifier_fourth e17 on a.date_pol_eff between e17.Fdate and e17.Xdate --e17.VersionId=v.versionid
			and a.model_age between e17.HullAgeMin and case when isnull(e17.HullAgeMax,'Null') = 'NULL' then 999999999 else e17.HullAgeMax end 
 left join #GroundOnlyModifier b18 on b18.coverage=a.limit_dscr and a.date_pol_eff between b18.Fdate and b18.Xdate --b18.VersionId=v.versionid
 left join #HullBaseRate b19 on b19.AircraftType=a.aircraft_type_description and b19.PrimaryUseId=a.Primary_use_rating and b19.GearType=a.gear_type_dscr and 
			a.date_pol_eff between (case when a.pol_ed > 1 then b19.fdate_ren else b19.Fdate end)
									and 
								(case when a.pol_ed > 1 then b19.xdate_ren else b19.Xdate end) --b19.VersionId=v.versionid
			and a.hull_value between b19.HullValueMin and b19.HullValueMax
 left join #HullBaseRate_second c19 on c19.AircraftType=a.aircraft_type_description and c19.PrimaryUseId=a.Primary_use_rating and 
			a.date_pol_eff between (case when a.pol_ed > 1 then c19.fdate_ren else c19.Fdate end)
									and 
								(case when a.pol_ed > 1 then c19.xdate_ren else c19.Xdate end)--c19.VersionId=v.versionid
			and a.hull_value between c19.HullValueMin and c19.HullValueMax
  left join #LiabBaseRate b20 on b20.AircraftType=a.aircraft_type_rating and b20.geartype=a.gear_type_rating and b20.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between b20.Fdate and b20.Xdate --b20.VersionId=v.versionid
			and b20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description= b20.PassengerLimitText and a.CSL_Occurance_Limit = b20.LiabOccurLimitMin
 left join #LiabBaseRate_second c20 on c20.AircraftType=a.aircraft_type_rating and c20.PrimaryUseId=a.Primary_use_rating and a.date_pol_eff between c20.Fdate and c20.Xdate --c20.VersionId=v.versionid
			and c20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description = c20.PassengerLimitText and a.CSL_Occurance_Limit = c20.LiabOccurLimitMin
 left join #LiabBaseAddtlSeat b21 on a.aircraft_type_rating=b21.AircraftType and a.Primary_use_rating=b21.PrimaryUseId and a.gear_type_rating=b21.GearType and b21.VersionId=v.versionid --a.date_pol_eff between b21.Fdate and b21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=b21.PassengerLimitText
 left join #LiabBaseAddtlSeat_second c21 on a.aircraft_type_rating=c21.AircraftType and a.Primary_use_rating=c21.PrimaryUseId and c21.VersionId=v.versionid --a.date_pol_eff between c21.Fdate and c21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=c21.PassengerLimitText
left join #MedPayBaseRate b22 on a.aircraft_type_description=b22.AircraftType and a.Primary_use_rating=b22.PrimaryUseId and a.gear_type_dscr=b22.GearType and a.date_pol_eff between b22.Fdate and b22.Xdate --b22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=b22.SeatIndex and a.Med_Passenger_Limit_description between b22.MedPayLimitMin and b22.MedPayLimitMax
left join #MedPayBaseRate_second c22 on a.aircraft_type_description=c22.AircraftType and a.Primary_use_rating=c22.PrimaryUseId and a.date_pol_eff between c22.Fdate and c22.Xdate --c22.VersionId=v.versionid
		and a.gear_type_dscr=c22.GearType and a.Med_Passenger_Limit_description between c22.MedPayLimitMin and c22.MedPayLimitMax
left join #MedPayBaseRate_third d22 on a.aircraft_type_description=d22.AircraftType and a.Primary_use_rating=d22.PrimaryUseId and a.date_pol_eff between d22.Fdate and d22.Xdate --d22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=d22.SeatIndex and a.Med_Passenger_Limit_description between d22.MedPayLimitMin and d22.MedPayLimitMax
left join #PilotIFRModifier b23 on a.aircraft_type_description=b23.AircraftType and a.Primary_use_rating=b23.PrimaryUseId and a.gear_type_dscr=b23.GearType and a.date_pol_eff between b23.Fdate and b23.Xdate --b23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=b23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =b23.PilotMinIFR
left join #PilotIFRModifier_second c23 on a.aircraft_type_description=c23.AircraftType and a.Primary_use_rating=c23.PrimaryUseId and a.date_pol_eff between c23.Fdate and c23.Xdate --c23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=c23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =c23.PilotMinIFR
left join #PilotIFRModifier_third d23 on a.aircraft_type_description=d23.AircraftType and a.date_pol_eff between d23.Fdate and d23.Xdate --d23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=d23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =d23.PilotMinIFR
left join #PilotGearHrsModifier b24 on  b24.AircraftType= a.aircraft_type_rating and b24.PrimaryUseId=a.Primary_use_rating and 	b24.GearType=a.gear_type_rating and b24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	b24.PilotGearHrsMin and case when b24.PilotGearHrsMax='NULL' or b24.PilotGearHrsMax is null then 999999999 else b24.PilotGearHrsMax end  and a.date_pol_eff between b24.Fdate and b24.Xdate --b24.VersionId=v.versionid
left join #PilotGearHrsModifier_second c24 on  c24.AircraftType= a.aircraft_type_rating and c24.PrimaryUseId=a.Primary_use_rating and c24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	c24.PilotGearHrsMin and case when c24.PilotGearHrsMax='NULL' or c24.PilotGearHrsMax is null then 999999999 else c24.PilotGearHrsMax end and a.date_pol_eff between c24.Fdate and c24.Xdate --c24.VersionId=v.versionid
left join #PilotGearHrsModifier_third d24 on  d24.AircraftType= a.aircraft_type_rating and d24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	d24.PilotGearHrsMin and case when d24.PilotGearHrsMax='NULL' or d24.PilotGearHrsMax is null then 999999999 else d24.PilotGearHrsMax end and a.date_pol_eff between d24.Fdate and d24.Xdate --d24.VersionId=v.versionid
left join #Coastal b25 on b25.[Airport_State]=case when state_risk <>'FL' then 'All Other States' else 'FL' end and [Airport_Coastal_Flag]=a.is_coastal and a.date_pol_eff between b25.Fdate and b25.Xdate --b25.VersionId=v.versionid
left join #Aircraft_Type_Modifier c28 on a.aircraft_type_description = c28.AircraftType and a.Primary_use_rating = c28.PrimaryUseId and a.gear_type_dscr = c28.GearType and a.date_pol_eff between c28.Fdate and c28.Xdate
left join #Aircraft_Type_Modifier_second d28 on a.aircraft_type_description = d28.AircraftType and a.Primary_use_rating = d28.PrimaryUseId and a.date_pol_eff between d28.Fdate and d28.Xdate
left join #ded_base_model_1 c25 on a.model_code = c25.ModelCode and a.model = c25.model  and a.make_dscr = c25.Manufacturer and a.aircraftuse_dscr = c25.[Use] and a.Coverage_group = c25.[Type] and a.date_pol_eff between c25.Fdate and c25.Xdate
left join #ded_base_model_2 d25 on a.model_code = d25.ModelCode and a.model = d25.model  and a.make_dscr = d25.Manufacturer and a.aircraftuse_dscr = d25.[Use] and a.date_pol_eff between d25.Fdate and d25.Xdate
left join #ded_base_model_3 e25 on a.model_code = e25.ModelCode and a.model = e25.model  and a.make_dscr = e25.Manufacturer and a.aircraftuse_dscr = e25.[Use] and a.date_pol_eff between e25.Fdate and e25.Xdate
left join #ded_base_age_1 c26 on a.aircraft_type_description = c26.[Aircraft type] and a.max_age between c26.[Age Low] and c26.[Age High] and a.date_pol_eff between c26.Fdate and c26.Xdate 
left join #ded_base_type_1 c27 on a.aircraft_type_description = c27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when c27.[Type] = 'GRO-NIM' then 'GRO-NIM' when c27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when c27.[Type] is null then 'GRO-Flight' else null end) and a.gear_type_rating = c27.[GEAR TYPE] and a.Primary_use_rating = c27.[Use] and a.date_pol_eff between c27.Fdate and c27.Xdate 
left join #ded_base_type_2 d27 on a.aircraft_type_description = d27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when d27.[Type] = 'GRO-NIM' then 'GRO-NIM' when d27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when d27.[Type] is null then 'GRO-Flight' else null end) and a.Primary_use_rating = d27.[Use] and a.date_pol_eff between d27.Fdate and d27.Xdate 
left join #ded_base_type_3 e27 on a.aircraft_type_description = e27.[AIRCRAFT DESCRIPTION] and a.Primary_use_rating = e27.[Use] and a.date_pol_eff between e27.Fdate and e27.Xdate 


ALTER TABLE #temp02
ADD r_max_base_deductible INT 

update #temp02
set r_BaseModelDeductible = case when r_BaseModelDeductible < 1 then isnull(r_BaseModelDeductible * hull_value,0)
								else isnull(r_BaseModelDeductible,0)
								end,
	r_BaseAgeDeductible = case when r_BaseAgeDeductible < 1 then isnull(r_BaseAgeDeductible * hull_value,0)
								else isnull(r_BaseAgeDeductible,0)
								end,
	r_BaseTypeDeductible = case when r_BaseTypeDeductible < 1 then isnull(r_BaseTypeDeductible * hull_value,0)
								else isnull(r_BaseTypeDeductible,0)
								end

update #temp02
set	r_max_base_deductible = CASE
							WHEN r_BaseModelDeductible >= r_BaseAgeDeductible AND r_BaseModelDeductible >= r_BaseTypeDeductible THEN r_BaseModelDeductible
							WHEN r_BaseAgeDeductible >= r_BaseModelDeductible AND r_BaseAgeDeductible >= r_BaseTypeDeductible THEN r_BaseAgeDeductible
							WHEN r_BaseTypeDeductible >= r_BaseModelDeductible AND r_BaseTypeDeductible >= r_BaseAgeDeductible THEN r_BaseTypeDeductible
							ELSE r_BaseModelDeductible
							END



 --rerating factors at today
if OBJECT_ID('tempdb.dbo.#temp03') is not null drop table #temp03
 select a.*
 ,v.versionid rr_versionid
 ,v.eff_date rr_version_eff_date
 ,isnull(b.RESULTVALUE,isnull(c.RESULTVALUE,0)) rr_AircraftModelModifierHull 
 ,isnull(b1.RESULTVALUE,isnull(c1.RESULTVALUE,0)) rr_AircraftModelModifierLiab
 ,isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) rr_SeatIndex
 ,isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE))) rr_PrimaryPilotRating 
 ,0 rr_airport_modifier 
 ,isnull(b4.RESULTVALUE,isnull(c4.RESULTVALUE,d4.RESULTVALUE)) rr_CMIndexHull 
 ,isnull(b5.RESULTVALUE,isnull(c5.RESULTVALUE,d5.RESULTVALUE)) rr_CMIndexLiability 
 ,b6.RESULTVALUE rr_CMIndexMedPay 
 ,b7.RESULTVALUE rr_StdDiscountHull 
 ,b8.RESULTVALUE rr_StdDiscountLiab
 ,isnull(b9.RESULTVALUE,isnull(c9.RESULTVALUE,isnull(d9.RESULTVALUE,e9.RESULTVALUE))) rr_IsManual 
 ,b10.RESULTVALUE rr_LiabilityOnlyModifier 
 ,isnull(b11.RESULTVALUE,c11.RESULTVALUE) rr_MinimumPremium 
 ,isnull(b12.RESULTVALUE,c12.RESULTVALUE) rr_PilotMinTotalHrsModifier
 ,isnull(b13.RESULTVALUE,isnull(c13.RESULTVALUE,d13.RESULTVALUE)) rr_PilotMMHrsModifier
 ,isnull(b14.RESULTVALUE,isnull(c14.RESULTVALUE,d14.RESULTVALUE)) rr_PilotMEHrsModifier
 ,isnull(b15.RESULTVALUE,isnull(c15.RESULTVALUE,isnull(d15.RESULTVALUE,e15.RESULTVALUE))) rr_PilotAgeMinModifier
 ,isnull(b16.RESULTVALUE,isnull(c16.RESULTVALUE,isnull(d16.RESULTVALUE,e16.RESULTVALUE))) rr_PilotAgeMaxModifier
 ,isnull(b17.RESULTVALUE,isnull(c17.RESULTVALUE,isnull(d17.RESULTVALUE,e17.RESULTVALUE))) rr_HullModifier
 ,b18.RESULTVALUE rr_Ground_Modifier
 ,isnull(b19.RESULTVALUE,c19.RESULTVALUE) rr_HullBaseRate
 ,isnull(b20.RESULTVALUE,c20.RESULTVALUE) rr_LiabBaseRate
 ,isnull(b21.RESULTVALUE,c21.RESULTVALUE) rr_LiabBaseAddtlSeat  
 ,isnull(b22.RESULTVALUE,isnull(c22.RESULTVALUE,d22.RESULTVALUE)) rr_MedPayBaseRate  
 ,isnull(b23.RESULTVALUE,isnull(c23.RESULTVALUE,d23.RESULTVALUE)) rr_PilotIFRModifier
 ,round(isnull(b24.RESULTVALUE,isnull(c24.RESULTVALUE,d24.RESULTVALUE)),4) rr_PilotMinGearHrsModifier
 ,b25.rate rr_coastal_factor
 ,isnull(c28.RESULTVALUE,d28.RESULTVALUE) rr_AircraftTypeModifier
 ,isnull(c25.[Base_ded],isnull(d25.[Base_ded],e25.[Base_ded])) rr_BaseModelDeductible
 ,c26.[Min Ded] rr_BaseAgeDeductible
 ,isnull(c27.[Deductible],isnull(d27.[Deductible],e27.[Deductible])) rr_BaseTypeDeductible
 into #temp03
FROM #temp02 a
 left join #version v on getdate() between v.eff_date and v.exp_date
 left join #AircraftModelModifierHull b on b.AircraftType=a.aircraft_type_rating and b.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b.GearType and a.Model_Code=b.ModelCode and getdate() between b.Fdate and b.Xdate--b.VersionId=v.versionid
 left join #AircraftModelModifierHull_ex_gear c on c.AircraftType=a.aircraft_type_rating and c.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c.ModelCode and getdate() between c.Fdate and c.Xdate--and c.VersionId=v.versionid
 left join #AircraftModelModifierLiab b1 on b1.AircraftType=a.aircraft_type_rating and b1.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b1.GearType and a.Model_Code=b1.ModelCode and getdate() between b1.Fdate and b1.Xdate--b1.VersionId=v.versionid
 left join #AircraftModelModifierLiab_ex_gear c1 on c1.AircraftType=a.aircraft_type_rating and c1.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c1.ModelCode  and getdate() between c1.Fdate and c1.Xdate--c1.VersionId=v.versionid
 left join #SeatIndex b2 on b2.AircraftType=a.aircraft_type_rating and b2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between b2.NoOfSeatsMin and case when b2.NoOfSeatsMax is null then 999999999 else b2.NoOfSeatsMax end and getdate() between b2.Fdate and b2.Xdate--b2.VersionId=v.versionid
 left join #SeatIndex_second c2 on  c2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between c2.NoOfSeatsMin and case when c2.NoOfSeatsMax is null then 999999999 else c2.NoOfSeatsMax end and getdate() between c2.Fdate and c2.Xdate --c2.VersionId=v.versionid
 left join #PrimaryPilotRating b3 on b3.AircraftType=a.aircraft_type_rating and b3.PrimaryUseId=a.Primary_use_rating and b3.GearType=a.gear_type_rating and cast(a.Min_Total_Hours as int) between b3.PilotMinTotalHrsMin and case when b3.PilotMinTotalHrsMax is null then 999999999 else b3.PilotMinTotalHrsMax end and getdate() between b3.Fdate and b3.Xdate --b3.VersionId=v.versionid
 left join #PrimaryPilotRating_second c3 on  c3.AircraftType=a.aircraft_type_rating and c3.PrimaryUseId=a.Primary_use_rating and cast(a.Min_Total_Hours as int) between c3.PilotMinTotalHrsMin and case when c3.PilotMinTotalHrsMax is null then 999999999 else c3.PilotMinTotalHrsMax end and getdate() between c3.Fdate and c3.Xdate--c3.VersionId=v.versionid
 left join #PrimaryPilotRating_third d3 on  d3.AircraftType=a.aircraft_type_rating and cast(a.Min_Total_Hours as int) between d3.PilotMinTotalHrsMin and case when d3.PilotMinTotalHrsMax is null then 999999999 else d3.PilotMinTotalHrsMax end and getdate() between d3.Fdate and d3.Xdate--d3.VersionId=v.versionid
 left join #PrimaryPilotRating_fourth e3 on  cast(a.Min_Total_Hours as int) between e3.PilotMinTotalHrsMin and case when e3.PilotMinTotalHrsMax is null then 999999999 else e3.PilotMinTotalHrsMax end and getdate() between e3.Fdate and e3.Xdate--e3.VersionId=v.versionid
 left join #CMIndexHull b4 on b4.AircraftType=a.aircraft_type_rating and b4.PrimaryUseId=a.Primary_use_rating and b4.GearType=a.gear_type_rating and getdate() between b4.Fdate and b4.Xdate--b4.VersionId=v.versionid
 left join #CMIndexHull_second c4 on  c4.AircraftType=a.aircraft_type_rating and c4.PrimaryUseId=a.Primary_use_rating and getdate() between c4.Fdate and c4.Xdate--c4.VersionId=v.versionid
 left join #CMIndexHull_third d4 on getdate() between d4.Fdate and d4.Xdate-- d4.VersionId=v.versionid
 left join #CMIndexLiability b5 on b5.AircraftType=a.aircraft_type_rating and b5.PrimaryUseId=a.Primary_use_rating and b5.GearType=a.gear_type_rating and getdate() between b5.Fdate and b5.Xdate--b5.VersionId=v.versionid
 left join #CMIndexLiability_second c5 on  c5.AircraftType=a.aircraft_type_rating and c5.PrimaryUseId=a.Primary_use_rating and getdate() between c5.Fdate and c5.Xdate-- c5.VersionId=v.versionid
 left join #CMIndexLiability_third d5 on getdate() between d5.Fdate and d5.Xdate-- d5.VersionId=v.versionid
 left join #CMIndexMedPay b6 on getdate() between b6.Fdate and b6.Xdate --b6.VersionId=v.versionid
 left join #StdDiscountHull b7 on getdate() between b7.Fdate and b7.Xdate --b7.VersionId=v.versionid
 left join #StdDiscountLiab b8 on getdate() between b8.Fdate and b8.Xdate  --b8.VersionId=v.versionid
 left join #IsManual b9 on b9.AircraftType=a.aircraft_type_rating and b9.PrimaryUseId=a.Primary_use_rating and b9.GearType=a.gear_type_rating and getdate() between b9.Fdate and b9.Xdate--b9.VersionId=v.versionid
 left join #IsManual_second c9 on c9.AircraftType=a.aircraft_type_rating and c9.PrimaryUseId=a.Primary_use_rating and getdate() between c9.Fdate and c9.Xdate--c9.VersionId=v.versionid
 left join #IsManual_third d9 on d9.PrimaryUseId=a.Primary_use_rating and getdate() between d9.Fdate and d9.Xdate--d9.VersionId=v.versionid
 left join #IsManual_fourth e9 on getdate() between e9.Fdate and e9.Xdate--e9.VersionId=v.versionid
 left join #LiabilityOnlyModifier b10 on b10.HullValue = a.hull_value and getdate() between b10.Fdate and b10.Xdate--b10.VersionId=v.versionid
 left join #MinimumPremium b11 on b11.PrimaryUseId=a.Primary_use_rating and getdate() between b11.Fdate and b11.Xdate--b11.VersionId=v.versionid
 left join #MinimumPremium_second c11 on getdate() between c11.Fdate and c11.Xdate--c11.VersionId=v.versionid
 left join #PilotMinTotalHrsModifier b12 on b12.AircraftType=a.aircraft_type_rating and b12.PrimaryUseId=a.Primary_use_rating and b12.GearType=a.gear_type_rating and getdate() between b12.Fdate and b12.Xdate --b12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between b12.PilotMinTotalHrsMin and case when isnull(b12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else b12.PilotMinTotalHrsMax end
 left join #PilotMinTotalHrsModifier_second c12 on c12.AircraftType=a.aircraft_type_rating and c12.PrimaryUseId=a.Primary_use_rating and getdate() between c12.Fdate and c12.Xdate --c12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between c12.PilotMinTotalHrsMin and case when isnull(c12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else c12.PilotMinTotalHrsMax end
 left join #PilotMMHrsModifier b13 on b13.AircraftType=a.aircraft_type_rating and b13.PrimaryUseId=a.Primary_use_rating and b13.GearType=a.gear_type_rating and getdate() between b13.Fdate and b13.Xdate --b13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between b13.PilotMMHrsMin and case when b13.PilotMMHrsMax = 'NULL' then 999999999 else b13.PilotMMHrsMax end and b13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_second c13 on c13.AircraftType=a.aircraft_type_rating and c13.PrimaryUseId=a.Primary_use_rating and getdate() between c13.Fdate and c13.Xdate--c13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between c13.PilotMMHrsMin and case when c13.PilotMMHrsMax = 'NULL' then 999999999 else c13.PilotMMHrsMax end  and c13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_third d13 on d13.AircraftType=a.aircraft_type_rating and getdate() between d13.Fdate and d13.Xdate--d13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between d13.PilotMMHrsMin and case when d13.PilotMMHrsMax = 'NULL' then 999999999 else d13.PilotMMHrsMax end  and d13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier b14 on b14.AircraftType=a.aircraft_type_rating and b14.PrimaryUseId=a.Primary_use_rating and b14.GearType=a.gear_type_rating and getdate() between b14.Fdate and b14.Xdate--b14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between b14.PilotMEHrsMin and case when b14.PilotMEHrsMax = 'NULL' or b14.PilotMEHrsMax is null then 999999999 else b14.PilotMEHrsMax end and b14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_second c14 on c14.AircraftType=a.aircraft_type_rating and c14.PrimaryUseId=a.Primary_use_rating and getdate() between c14.Fdate and c14.Xdate--c14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between c14.PilotMEHrsMin and case when c14.PilotMEHrsMax = 'NULL' or c14.PilotMEHrsMax is null then 999999999 else c14.PilotMEHrsMax end  and c14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_third d14 on d14.AircraftType=a.aircraft_type_rating and getdate() between d14.Fdate and d14.Xdate--d14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between d14.PilotMEHrsMin and case when d14.PilotMEHrsMax = 'NULL' or d14.PilotMEHrsMax is null then 999999999 else d14.PilotMEHrsMax end  and d14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotAgeMinModifier b15 on b15.AircraftType=a.aircraft_type_rating and b15.PrimaryUseId=a.Primary_use_rating and b15.GearType=a.gear_type_rating and getdate() between b15.Fdate and b15.Xdate--b15.VersionId=v.versionid
			and cast(a.min_age as int) between b15.PilotMinAgeMin and case when b15.PilotMinAgeMax = 'NULL' then 999999999 else b15.PilotMinAgeMax end 
 left join #PilotAgeMinModifier_second c15 on c15.AircraftType=a.aircraft_type_rating and c15.PrimaryUseId=a.Primary_use_rating and getdate() between c15.Fdate and c15.Xdate--c15.VersionId=v.versionid
			and cast(a.min_age as int) between c15.PilotMinAgeMin and case when c15.PilotMinAgeMax = 'NULL' then 999999999 else c15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_third d15 on d15.AircraftType=a.aircraft_type_rating and getdate() between d15.Fdate and d15.Xdate--d15.VersionId=v.versionid
			and cast(a.min_age as int) between d15.PilotMinAgeMin and case when d15.PilotMinAgeMax = 'NULL' then 999999999 else d15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_fourth e15 on getdate() between e15.Fdate and e15.Xdate--e15.VersionId=v.versionid 
			and cast(a.min_age as int) between e15.PilotMinAgeMin and case when e15.PilotMinAgeMax = 'NULL' then 999999999 else e15.PilotMinAgeMax end  
 left join #PilotAgeMaxModifier b16 on b16.AircraftType=a.aircraft_type_rating and b16.PrimaryUseId=a.Primary_use_rating and b16.GearType=a.gear_type_rating and getdate() between b16.Fdate and b16.Xdate--b16.VersionId=v.versionid
			and cast(a.max_age as int) between b16.PilotMaxAgeMin and case when b16.PilotMaxAgeMax = 'NULL' then 999999999 else b16.PilotMaxAgeMax end 
 left join #PilotAgeMaxModifier_second c16 on c16.AircraftType=a.aircraft_type_rating and c16.PrimaryUseId=a.Primary_use_rating and getdate() between c16.Fdate and c16.Xdate--c16.VersionId=v.versionid
			and cast(a.max_age as int) between c16.PilotMaxAgeMin and case when c16.PilotMaxAgeMax = 'NULL' then 999999999 else c16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_third d16 on d16.AircraftType=a.aircraft_type_rating and getdate() between d16.Fdate and d16.Xdate--d16.VersionId=v.versionid
			and cast(a.max_age as int) between d16.PilotMaxAgeMin and case when d16.PilotMaxAgeMax = 'NULL' then 999999999 else d16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_fourth e16 on getdate() between e16.Fdate and e16.Xdate --e16.VersionId=v.versionid 
			and cast(a.max_age as int) between e16.PilotMaxAgeMin and case when e16.PilotMaxAgeMax = 'NULL' then 999999999 else e16.PilotMaxAgeMax end  
 left join #HullModifier b17 on b17.AircraftType=a.aircraft_type_rating and b17.PrimaryUseId=a.Primary_use_rating and b17.GearType=a.gear_type_rating and getdate() between b17.Fdate and b17.Xdate--b17.VersionId=v.versionid
			and a.model_age between b17.HullAgeMin and case when isnull(b17.HullAgeMax,'Null') = 'NULL' then 999999999 else b17.HullAgeMax end 
 left join #HullModifier_second c17 on c17.AircraftType=a.aircraft_type_rating and c17.PrimaryUseId=a.Primary_use_rating and getdate() between c17.Fdate and c17.Xdate--c17.VersionId=v.versionid
			and a.model_age between c17.HullAgeMin and case when isnull(c17.HullAgeMax,'Null') = 'NULL' then 999999999 else c17.HullAgeMax end 
 left join #HullModifier_third d17 on d17.PrimaryUseId=a.Primary_use_rating and getdate() between d17.Fdate and d17.Xdate --d17.VersionId=v.versionid
			and a.model_age between d17.HullAgeMin and case when isnull(d17.HullAgeMax,'Null') = 'NULL' then 999999999 else d17.HullAgeMax end 
 left join #HullModifier_fourth e17 on getdate() between e17.Fdate and e17.Xdate --e17.VersionId=v.versionid
			and a.model_age between e17.HullAgeMin and case when isnull(e17.HullAgeMax,'Null') = 'NULL' then 999999999 else e17.HullAgeMax end 
 left join #GroundOnlyModifier b18 on b18.coverage=a.limit_dscr and getdate() between b18.Fdate and b18.Xdate --b18.VersionId=v.versionid
 left join #HullBaseRate b19 on b19.AircraftType=a.aircraft_type_description and b19.PrimaryUseId=a.Primary_use_rating and b19.GearType=a.gear_type_dscr and 
			getdate() between (case when a.pol_ed > 1 then b19.fdate_ren else b19.Fdate end)
									and 
								(case when a.pol_ed > 1 then b19.xdate_ren else b19.Xdate end) --b19.VersionId=v.versionid
			and a.hull_value between b19.HullValueMin and b19.HullValueMax
 left join #HullBaseRate_second c19 on c19.AircraftType=a.aircraft_type_description and c19.PrimaryUseId=a.Primary_use_rating and 
			getdate() between (case when a.pol_ed > 1 then c19.fdate_ren else c19.Fdate end)
									and 
								(case when a.pol_ed > 1 then c19.xdate_ren else c19.Xdate end) --c19.VersionId=v.versionid
			and a.hull_value between c19.HullValueMin and c19.HullValueMax
  left join #LiabBaseRate b20 on b20.AircraftType=a.aircraft_type_rating and b20.geartype=a.gear_type_rating and b20.PrimaryUseId=a.Primary_use_rating and getdate() between b20.Fdate and b20.Xdate --b20.VersionId=v.versionid
			and b20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description= b20.PassengerLimitText and a.CSL_Occurance_Limit = b20.LiabOccurLimitMin
 left join #LiabBaseRate_second c20 on c20.AircraftType=a.aircraft_type_rating and c20.PrimaryUseId=a.Primary_use_rating and getdate() between c20.Fdate and c20.Xdate --c20.VersionId=v.versionid
			and c20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description = c20.PassengerLimitText and a.CSL_Occurance_Limit = c20.LiabOccurLimitMin
 left join #LiabBaseAddtlSeat b21 on a.aircraft_type_rating=b21.AircraftType and a.Primary_use_rating=b21.PrimaryUseId and a.gear_type_rating=b21.GearType and b21.VersionId=v.versionid --getdate() between b21.Fdate and b21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=b21.PassengerLimitText
 left join #LiabBaseAddtlSeat_second c21 on a.aircraft_type_rating=c21.AircraftType and a.Primary_use_rating=c21.PrimaryUseId and c21.VersionId=v.versionid --getdate() between c21.Fdate and c21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=c21.PassengerLimitText
left join #MedPayBaseRate b22 on a.aircraft_type_description=b22.AircraftType and a.Primary_use_rating=b22.PrimaryUseId and a.gear_type_dscr=b22.GearType and getdate() between b22.Fdate and b22.Xdate --b22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=b22.SeatIndex and a.Med_Passenger_Limit_description between b22.MedPayLimitMin and b22.MedPayLimitMax
left join #MedPayBaseRate_second c22 on a.aircraft_type_description=c22.AircraftType and a.Primary_use_rating=c22.PrimaryUseId and getdate() between c22.Fdate and c22.Xdate --c22.VersionId=v.versionid
		and a.gear_type_dscr=c22.GearType and a.Med_Passenger_Limit_description between c22.MedPayLimitMin and c22.MedPayLimitMax
left join #MedPayBaseRate_third d22 on a.aircraft_type_description=d22.AircraftType and a.Primary_use_rating=d22.PrimaryUseId and getdate() between d22.Fdate and d22.Xdate --d22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=d22.SeatIndex and a.Med_Passenger_Limit_description between d22.MedPayLimitMin and d22.MedPayLimitMax
left join #PilotIFRModifier b23 on a.aircraft_type_description=b23.AircraftType and a.Primary_use_rating=b23.PrimaryUseId and a.gear_type_dscr=b23.GearType and getdate() between b23.Fdate and b23.Xdate --b23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=b23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =b23.PilotMinIFR
left join #PilotIFRModifier_second c23 on a.aircraft_type_description=c23.AircraftType and a.Primary_use_rating=c23.PrimaryUseId and getdate() between c23.Fdate and c23.Xdate --c23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=c23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =c23.PilotMinIFR
left join #PilotIFRModifier_third d23 on a.aircraft_type_description=d23.AircraftType and getdate() between d23.Fdate and d23.Xdate --d23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=d23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =d23.PilotMinIFR
left join #PilotGearHrsModifier b24 on  b24.AircraftType= a.aircraft_type_rating and b24.PrimaryUseId=a.Primary_use_rating and 	b24.GearType=a.gear_type_rating and b24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	b24.PilotGearHrsMin and case when b24.PilotGearHrsMax='NULL' or b24.PilotGearHrsMax is null then 999999999 else b24.PilotGearHrsMax end  and getdate() between b24.Fdate and b24.Xdate --b24.VersionId=v.versionid
left join #PilotGearHrsModifier_second c24 on  c24.AircraftType= a.aircraft_type_rating and c24.PrimaryUseId=a.Primary_use_rating and c24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	c24.PilotGearHrsMin and case when c24.PilotGearHrsMax='NULL' or c24.PilotGearHrsMax is null then 999999999 else c24.PilotGearHrsMax end and getdate() between c24.Fdate and c24.Xdate --c24.VersionId=v.versionid
left join #PilotGearHrsModifier_third d24 on  d24.AircraftType= a.aircraft_type_rating and d24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	d24.PilotGearHrsMin and case when d24.PilotGearHrsMax='NULL' or d24.PilotGearHrsMax is null then 999999999 else d24.PilotGearHrsMax end and getdate() between d24.Fdate and d24.Xdate --d24.VersionId=v.versionid
left join #Coastal b25 on b25.[Airport_State]=case when state_risk <>'FL' then 'All Other States' else 'FL' end and [Airport_Coastal_Flag]=a.is_coastal and getdate() between b25.Fdate and b25.Xdate --b25.VersionId=v.versionid
left join #Aircraft_Type_Modifier c28 on a.aircraft_type_description = c28.AircraftType and a.Primary_use_rating = c28.PrimaryUseId and a.gear_type_dscr = c28.GearType and getdate() between c28.Fdate and c28.Xdate
left join #Aircraft_Type_Modifier_second d28 on a.aircraft_type_description = d28.AircraftType and a.Primary_use_rating = d28.PrimaryUseId and getdate() between d28.Fdate and d28.Xdate
left join #ded_base_model_1 c25 on a.model_code = c25.ModelCode and a.model = c25.model  and a.make_dscr = c25.Manufacturer and a.aircraftuse_dscr = c25.[Use] and a.Coverage_group = c25.[Type] and getdate() between c25.Fdate and c25.Xdate
left join #ded_base_model_2 d25 on a.model_code = d25.ModelCode and a.model = d25.model  and a.make_dscr = d25.Manufacturer and a.aircraftuse_dscr = d25.[Use] and getdate() between d25.Fdate and d25.Xdate
left join #ded_base_model_3 e25 on a.model_code = e25.ModelCode and a.model = e25.model  and a.make_dscr = e25.Manufacturer and a.aircraftuse_dscr = e25.[Use] and getdate() between e25.Fdate and e25.Xdate
left join #ded_base_age_1 c26 on a.aircraft_type_description = c26.[Aircraft type] and a.max_age between c26.[Age Low] and c26.[Age High] and getdate() between c26.Fdate and c26.Xdate 
left join #ded_base_type_1 c27 on a.aircraft_type_description = c27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when c27.[Type] = 'GRO-NIM' then 'GRO-NIM' when c27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when c27.[Type] is null then 'GRO-Flight' else null end) and a.gear_type_rating = c27.[GEAR TYPE] and a.Primary_use_rating = c27.[Use] and getdate() between c27.Fdate and c27.Xdate 
left join #ded_base_type_2 d27 on a.aircraft_type_description = d27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when d27.[Type] = 'GRO-NIM' then 'GRO-NIM' when d27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when d27.[Type] is null then 'GRO-Flight' else null end) and a.Primary_use_rating = d27.[Use] and getdate() between d27.Fdate and d27.Xdate 
left join #ded_base_type_3 e27 on a.aircraft_type_description = e27.[AIRCRAFT DESCRIPTION] and a.Primary_use_rating = e27.[Use] and getdate() between e27.Fdate and e27.Xdate 


ALTER TABLE #temp03
ADD rr_max_base_deductible INT 

update #temp03
set rr_BaseModelDeductible = case when rr_BaseModelDeductible < 1 then isnull(rr_BaseModelDeductible * hull_value,0)
								else isnull(rr_BaseModelDeductible,0)
								end,
	rr_BaseAgeDeductible = case when rr_BaseAgeDeductible < 1 then isnull(rr_BaseAgeDeductible * hull_value,0)
								else isnull(rr_BaseAgeDeductible,0)
								end,
	rr_BaseTypeDeductible = case when rr_BaseTypeDeductible < 1 then isnull(rr_BaseTypeDeductible * hull_value,0)
								else isnull(rr_BaseTypeDeductible,0)
								end
update #temp03
set	rr_max_base_deductible = CASE
							WHEN rr_BaseModelDeductible >= rr_BaseAgeDeductible AND rr_BaseModelDeductible >= rr_BaseTypeDeductible THEN rr_BaseModelDeductible
							WHEN rr_BaseAgeDeductible >= rr_BaseModelDeductible AND rr_BaseAgeDeductible >= rr_BaseTypeDeductible THEN rr_BaseAgeDeductible
							WHEN rr_BaseTypeDeductible >= rr_BaseModelDeductible AND rr_BaseTypeDeductible >= rr_BaseAgeDeductible THEN rr_BaseTypeDeductible
							ELSE rr_BaseModelDeductible
							END



 --rerating factors at a year from today
if OBJECT_ID('tempdb.dbo.#temp04') is not null drop table #temp04
 select a.*
 ,v.versionid rrr_versionid
 ,v.eff_date rrr_version_eff_date
 ,isnull(b.RESULTVALUE,isnull(c.RESULTVALUE,0)) rrr_AircraftModelModifierHull 
 ,isnull(b1.RESULTVALUE,isnull(c1.RESULTVALUE,0)) rrr_AircraftModelModifierLiab
 ,isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) rrr_SeatIndex
 ,isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE))) rrr_PrimaryPilotRating 
 ,0 rrr_airport_modifier 
 ,isnull(b4.RESULTVALUE,isnull(c4.RESULTVALUE,d4.RESULTVALUE)) rrr_CMIndexHull 
 ,isnull(b5.RESULTVALUE,isnull(c5.RESULTVALUE,d5.RESULTVALUE)) rrr_CMIndexLiability 
 ,b6.RESULTVALUE rrr_CMIndexMedPay 
 ,b7.RESULTVALUE rrr_StdDiscountHull 
 ,b8.RESULTVALUE rrr_StdDiscountLiab
 ,isnull(b9.RESULTVALUE,isnull(c9.RESULTVALUE,isnull(d9.RESULTVALUE,e9.RESULTVALUE))) rrr_IsManual 
 ,b10.RESULTVALUE rrr_LiabilityOnlyModifier 
 ,isnull(b11.RESULTVALUE,c11.RESULTVALUE) rrr_MinimumPremium 
 ,isnull(b12.RESULTVALUE,c12.RESULTVALUE) rrr_PilotMinTotalHrsModifier
 ,isnull(b13.RESULTVALUE,isnull(c13.RESULTVALUE,d13.RESULTVALUE)) rrr_PilotMMHrsModifier
 ,isnull(b14.RESULTVALUE,isnull(c14.RESULTVALUE,d14.RESULTVALUE)) rrr_PilotMEHrsModifier
 ,isnull(b15.RESULTVALUE,isnull(c15.RESULTVALUE,isnull(d15.RESULTVALUE,e15.RESULTVALUE))) rrr_PilotAgeMinModifier
 ,isnull(b16.RESULTVALUE,isnull(c16.RESULTVALUE,isnull(d16.RESULTVALUE,e16.RESULTVALUE))) rrr_PilotAgeMaxModifier
 ,isnull(b17.RESULTVALUE,isnull(c17.RESULTVALUE,isnull(d17.RESULTVALUE,e17.RESULTVALUE))) rrr_HullModifier
 ,b18.RESULTVALUE rrr_Ground_Modifier
 ,isnull(b19.RESULTVALUE,c19.RESULTVALUE) rrr_HullBaseRate
 ,isnull(b20.RESULTVALUE,c20.RESULTVALUE) rrr_LiabBaseRate
 ,isnull(b21.RESULTVALUE,c21.RESULTVALUE) rrr_LiabBaseAddtlSeat  
 ,isnull(b22.RESULTVALUE,isnull(c22.RESULTVALUE,d22.RESULTVALUE)) rrr_MedPayBaseRate  
 ,isnull(b23.RESULTVALUE,isnull(c23.RESULTVALUE,d23.RESULTVALUE)) rrr_PilotIFRModifier
 ,round(isnull(b24.RESULTVALUE,isnull(c24.RESULTVALUE,d24.RESULTVALUE)),4) rrr_PilotMinGearHrsModifier
 ,b25.rate rrr_coastal_factor
 ,isnull(c28.RESULTVALUE,d28.RESULTVALUE) rrr_AircraftTypeModifier
 ,isnull(c25.[Base_ded],isnull(d25.[Base_ded],e25.[Base_ded])) rrr_BaseModelDeductible
 ,c26.[Min Ded] rrr_BaseAgeDeductible
 ,isnull(c27.[Deductible],isnull(d27.[Deductible],e27.[Deductible])) rrr_BaseTypeDeductible
 into #temp04
FROM #temp03 a
 left join #version v on dateadd(yy,1,getdate()) between v.eff_date and v.exp_date
 left join #AircraftModelModifierHull b on b.AircraftType=a.aircraft_type_rating and b.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b.GearType and a.Model_Code=b.ModelCode and dateadd(yy,1,getdate()) between b.Fdate and b.Xdate--b.VersionId=v.versionid
 left join #AircraftModelModifierHull_ex_gear c on c.AircraftType=a.aircraft_type_rating and c.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c.ModelCode and dateadd(yy,1,getdate()) between c.Fdate and c.Xdate--and c.VersionId=v.versionid
 left join #AircraftModelModifierLiab b1 on b1.AircraftType=a.aircraft_type_rating and b1.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b1.GearType and a.Model_Code=b1.ModelCode and dateadd(yy,1,getdate()) between b1.Fdate and b1.Xdate--b1.VersionId=v.versionid
 left join #AircraftModelModifierLiab_ex_gear c1 on c1.AircraftType=a.aircraft_type_rating and c1.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c1.ModelCode  and dateadd(yy,1,getdate()) between c1.Fdate and c1.Xdate--c1.VersionId=v.versionid
 left join #SeatIndex b2 on b2.AircraftType=a.aircraft_type_rating and b2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between b2.NoOfSeatsMin and case when b2.NoOfSeatsMax is null then 999999999 else b2.NoOfSeatsMax end and dateadd(yy,1,getdate()) between b2.Fdate and b2.Xdate--b2.VersionId=v.versionid
 left join #SeatIndex_second c2 on  c2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between c2.NoOfSeatsMin and case when c2.NoOfSeatsMax is null then 999999999 else c2.NoOfSeatsMax end and dateadd(yy,1,getdate()) between c2.Fdate and c2.Xdate --c2.VersionId=v.versionid
 left join #PrimaryPilotRating b3 on b3.AircraftType=a.aircraft_type_rating and b3.PrimaryUseId=a.Primary_use_rating and b3.GearType=a.gear_type_rating and cast(a.Min_Total_Hours as int) between b3.PilotMinTotalHrsMin and case when b3.PilotMinTotalHrsMax is null then 999999999 else b3.PilotMinTotalHrsMax end and dateadd(yy,1,getdate()) between b3.Fdate and b3.Xdate --b3.VersionId=v.versionid
 left join #PrimaryPilotRating_second c3 on  c3.AircraftType=a.aircraft_type_rating and c3.PrimaryUseId=a.Primary_use_rating and cast(a.Min_Total_Hours as int) between c3.PilotMinTotalHrsMin and case when c3.PilotMinTotalHrsMax is null then 999999999 else c3.PilotMinTotalHrsMax end and dateadd(yy,1,getdate()) between c3.Fdate and c3.Xdate--c3.VersionId=v.versionid
 left join #PrimaryPilotRating_third d3 on  d3.AircraftType=a.aircraft_type_rating and cast(a.Min_Total_Hours as int) between d3.PilotMinTotalHrsMin and case when d3.PilotMinTotalHrsMax is null then 999999999 else d3.PilotMinTotalHrsMax end and dateadd(yy,1,getdate()) between d3.Fdate and d3.Xdate--d3.VersionId=v.versionid
 left join #PrimaryPilotRating_fourth e3 on  cast(a.Min_Total_Hours as int) between e3.PilotMinTotalHrsMin and case when e3.PilotMinTotalHrsMax is null then 999999999 else e3.PilotMinTotalHrsMax end and dateadd(yy,1,getdate()) between e3.Fdate and e3.Xdate--e3.VersionId=v.versionid
 left join #CMIndexHull b4 on b4.AircraftType=a.aircraft_type_rating and b4.PrimaryUseId=a.Primary_use_rating and b4.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b4.Fdate and b4.Xdate--b4.VersionId=v.versionid
 left join #CMIndexHull_second c4 on  c4.AircraftType=a.aircraft_type_rating and c4.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c4.Fdate and c4.Xdate--c4.VersionId=v.versionid
 left join #CMIndexHull_third d4 on dateadd(yy,1,getdate()) between d4.Fdate and d4.Xdate-- d4.VersionId=v.versionid
 left join #CMIndexLiability b5 on b5.AircraftType=a.aircraft_type_rating and b5.PrimaryUseId=a.Primary_use_rating and b5.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b5.Fdate and b5.Xdate--b5.VersionId=v.versionid
 left join #CMIndexLiability_second c5 on  c5.AircraftType=a.aircraft_type_rating and c5.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c5.Fdate and c5.Xdate-- c5.VersionId=v.versionid
 left join #CMIndexLiability_third d5 on dateadd(yy,1,getdate()) between d5.Fdate and d5.Xdate-- d5.VersionId=v.versionid
 left join #CMIndexMedPay b6 on dateadd(yy,1,getdate()) between b6.Fdate and b6.Xdate --b6.VersionId=v.versionid
 left join #StdDiscountHull b7 on dateadd(yy,1,getdate()) between b7.Fdate and b7.Xdate --b7.VersionId=v.versionid
 left join #StdDiscountLiab b8 on dateadd(yy,1,getdate()) between b8.Fdate and b8.Xdate  --b8.VersionId=v.versionid
 left join #IsManual b9 on b9.AircraftType=a.aircraft_type_rating and b9.PrimaryUseId=a.Primary_use_rating and b9.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b9.Fdate and b9.Xdate--b9.VersionId=v.versionid
 left join #IsManual_second c9 on c9.AircraftType=a.aircraft_type_rating and c9.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c9.Fdate and c9.Xdate--c9.VersionId=v.versionid
 left join #IsManual_third d9 on d9.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between d9.Fdate and d9.Xdate--d9.VersionId=v.versionid
 left join #IsManual_fourth e9 on dateadd(yy,1,getdate()) between e9.Fdate and e9.Xdate--e9.VersionId=v.versionid
 left join #LiabilityOnlyModifier b10 on b10.HullValue = a.hull_value and dateadd(yy,1,getdate()) between b10.Fdate and b10.Xdate--b10.VersionId=v.versionid
 left join #MinimumPremium b11 on b11.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between b11.Fdate and b11.Xdate--b11.VersionId=v.versionid
 left join #MinimumPremium_second c11 on dateadd(yy,1,getdate()) between c11.Fdate and c11.Xdate--c11.VersionId=v.versionid
 left join #PilotMinTotalHrsModifier b12 on b12.AircraftType=a.aircraft_type_rating and b12.PrimaryUseId=a.Primary_use_rating and b12.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b12.Fdate and b12.Xdate --b12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between b12.PilotMinTotalHrsMin and case when isnull(b12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else b12.PilotMinTotalHrsMax end
 left join #PilotMinTotalHrsModifier_second c12 on c12.AircraftType=a.aircraft_type_rating and c12.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c12.Fdate and c12.Xdate --c12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between c12.PilotMinTotalHrsMin and case when isnull(c12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else c12.PilotMinTotalHrsMax end
 left join #PilotMMHrsModifier b13 on b13.AircraftType=a.aircraft_type_rating and b13.PrimaryUseId=a.Primary_use_rating and b13.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b13.Fdate and b13.Xdate --b13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between b13.PilotMMHrsMin and case when b13.PilotMMHrsMax = 'NULL' then 999999999 else b13.PilotMMHrsMax end and b13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_second c13 on c13.AircraftType=a.aircraft_type_rating and c13.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c13.Fdate and c13.Xdate--c13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between c13.PilotMMHrsMin and case when c13.PilotMMHrsMax = 'NULL' then 999999999 else c13.PilotMMHrsMax end  and c13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_third d13 on d13.AircraftType=a.aircraft_type_rating and dateadd(yy,1,getdate()) between d13.Fdate and d13.Xdate--d13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between d13.PilotMMHrsMin and case when d13.PilotMMHrsMax = 'NULL' then 999999999 else d13.PilotMMHrsMax end  and d13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier b14 on b14.AircraftType=a.aircraft_type_rating and b14.PrimaryUseId=a.Primary_use_rating and b14.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b14.Fdate and b14.Xdate--b14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between b14.PilotMEHrsMin and case when b14.PilotMEHrsMax = 'NULL' or b14.PilotMEHrsMax is null then 999999999 else b14.PilotMEHrsMax end and b14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_second c14 on c14.AircraftType=a.aircraft_type_rating and c14.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c14.Fdate and c14.Xdate--c14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between c14.PilotMEHrsMin and case when c14.PilotMEHrsMax = 'NULL' or c14.PilotMEHrsMax is null then 999999999 else c14.PilotMEHrsMax end  and c14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_third d14 on d14.AircraftType=a.aircraft_type_rating and dateadd(yy,1,getdate()) between d14.Fdate and d14.Xdate--d14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between d14.PilotMEHrsMin and case when d14.PilotMEHrsMax = 'NULL' or d14.PilotMEHrsMax is null then 999999999 else d14.PilotMEHrsMax end  and d14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotAgeMinModifier b15 on b15.AircraftType=a.aircraft_type_rating and b15.PrimaryUseId=a.Primary_use_rating and b15.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b15.Fdate and b15.Xdate--b15.VersionId=v.versionid
			and cast(a.min_age as int) between b15.PilotMinAgeMin and case when b15.PilotMinAgeMax = 'NULL' then 999999999 else b15.PilotMinAgeMax end 
 left join #PilotAgeMinModifier_second c15 on c15.AircraftType=a.aircraft_type_rating and c15.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c15.Fdate and c15.Xdate--c15.VersionId=v.versionid
			and cast(a.min_age as int) between c15.PilotMinAgeMin and case when c15.PilotMinAgeMax = 'NULL' then 999999999 else c15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_third d15 on d15.AircraftType=a.aircraft_type_rating and dateadd(yy,1,getdate()) between d15.Fdate and d15.Xdate--d15.VersionId=v.versionid
			and cast(a.min_age as int) between d15.PilotMinAgeMin and case when d15.PilotMinAgeMax = 'NULL' then 999999999 else d15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_fourth e15 on dateadd(yy,1,getdate()) between e15.Fdate and e15.Xdate--e15.VersionId=v.versionid 
			and cast(a.min_age as int) between e15.PilotMinAgeMin and case when e15.PilotMinAgeMax = 'NULL' then 999999999 else e15.PilotMinAgeMax end  
 left join #PilotAgeMaxModifier b16 on b16.AircraftType=a.aircraft_type_rating and b16.PrimaryUseId=a.Primary_use_rating and b16.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b16.Fdate and b16.Xdate--b16.VersionId=v.versionid
			and cast(a.max_age as int) between b16.PilotMaxAgeMin and case when b16.PilotMaxAgeMax = 'NULL' then 999999999 else b16.PilotMaxAgeMax end 
 left join #PilotAgeMaxModifier_second c16 on c16.AircraftType=a.aircraft_type_rating and c16.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c16.Fdate and c16.Xdate--c16.VersionId=v.versionid
			and cast(a.max_age as int) between c16.PilotMaxAgeMin and case when c16.PilotMaxAgeMax = 'NULL' then 999999999 else c16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_third d16 on d16.AircraftType=a.aircraft_type_rating and dateadd(yy,1,getdate()) between d16.Fdate and d16.Xdate--d16.VersionId=v.versionid
			and cast(a.max_age as int) between d16.PilotMaxAgeMin and case when d16.PilotMaxAgeMax = 'NULL' then 999999999 else d16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_fourth e16 on dateadd(yy,1,getdate()) between e16.Fdate and e16.Xdate --e16.VersionId=v.versionid 
			and cast(a.max_age as int) between e16.PilotMaxAgeMin and case when e16.PilotMaxAgeMax = 'NULL' then 999999999 else e16.PilotMaxAgeMax end  
 left join #HullModifier b17 on b17.AircraftType=a.aircraft_type_rating and b17.PrimaryUseId=a.Primary_use_rating and b17.GearType=a.gear_type_rating and dateadd(yy,1,getdate()) between b17.Fdate and b17.Xdate--b17.VersionId=v.versionid
			and a.model_age between b17.HullAgeMin and case when isnull(b17.HullAgeMax,'Null') = 'NULL' then 999999999 else b17.HullAgeMax end 
 left join #HullModifier_second c17 on c17.AircraftType=a.aircraft_type_rating and c17.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c17.Fdate and c17.Xdate--c17.VersionId=v.versionid
			and a.model_age between c17.HullAgeMin and case when isnull(c17.HullAgeMax,'Null') = 'NULL' then 999999999 else c17.HullAgeMax end 
 left join #HullModifier_third d17 on d17.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between d17.Fdate and d17.Xdate --d17.VersionId=v.versionid
			and a.model_age between d17.HullAgeMin and case when isnull(d17.HullAgeMax,'Null') = 'NULL' then 999999999 else d17.HullAgeMax end 
 left join #HullModifier_fourth e17 on dateadd(yy,1,getdate()) between e17.Fdate and e17.Xdate --e17.VersionId=v.versionid
			and a.model_age between e17.HullAgeMin and case when isnull(e17.HullAgeMax,'Null') = 'NULL' then 999999999 else e17.HullAgeMax end 
 left join #GroundOnlyModifier b18 on b18.coverage=a.limit_dscr and dateadd(yy,1,getdate()) between b18.Fdate and b18.Xdate --b18.VersionId=v.versionid
 left join #HullBaseRate b19 on b19.AircraftType=a.aircraft_type_description and b19.PrimaryUseId=a.Primary_use_rating and b19.GearType=a.gear_type_dscr and 
			dateadd(yy,1,getdate()) between (case when a.pol_ed > 1 then b19.fdate_ren else b19.Fdate end)
									and 
								(case when a.pol_ed > 1 then b19.xdate_ren else b19.Xdate end) --b19.VersionId=v.versionid
			and a.hull_value between b19.HullValueMin and b19.HullValueMax
 left join #HullBaseRate_second c19 on c19.AircraftType=a.aircraft_type_description and c19.PrimaryUseId=a.Primary_use_rating and 
			dateadd(yy,1,getdate()) between (case when a.pol_ed > 1 then c19.fdate_ren else c19.Fdate end)
									and 
								(case when a.pol_ed > 1 then c19.xdate_ren else c19.Xdate end) --c19.VersionId=v.versionid
			and a.hull_value between c19.HullValueMin and c19.HullValueMax
  left join #LiabBaseRate b20 on b20.AircraftType=a.aircraft_type_rating and b20.geartype=a.gear_type_rating and b20.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between b20.Fdate and b20.Xdate --b20.VersionId=v.versionid
			and b20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description= b20.PassengerLimitText and a.CSL_Occurance_Limit = b20.LiabOccurLimitMin
 left join #LiabBaseRate_second c20 on c20.AircraftType=a.aircraft_type_rating and c20.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,getdate()) between c20.Fdate and c20.Xdate --c20.VersionId=v.versionid
			and c20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description = c20.PassengerLimitText and a.CSL_Occurance_Limit = c20.LiabOccurLimitMin
 left join #LiabBaseAddtlSeat b21 on a.aircraft_type_rating=b21.AircraftType and a.Primary_use_rating=b21.PrimaryUseId and a.gear_type_rating=b21.GearType and b21.VersionId=v.versionid --dateadd(yy,1,getdate()) between b21.Fdate and b21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=b21.PassengerLimitText
 left join #LiabBaseAddtlSeat_second c21 on a.aircraft_type_rating=c21.AircraftType and a.Primary_use_rating=c21.PrimaryUseId and c21.VersionId=v.versionid --dateadd(yy,1,getdate()) between c21.Fdate and c21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=c21.PassengerLimitText
left join #MedPayBaseRate b22 on a.aircraft_type_description=b22.AircraftType and a.Primary_use_rating=b22.PrimaryUseId and a.gear_type_dscr=b22.GearType and dateadd(yy,1,getdate()) between b22.Fdate and b22.Xdate --b22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=b22.SeatIndex and a.Med_Passenger_Limit_description between b22.MedPayLimitMin and b22.MedPayLimitMax
left join #MedPayBaseRate_second c22 on a.aircraft_type_description=c22.AircraftType and a.Primary_use_rating=c22.PrimaryUseId and dateadd(yy,1,getdate()) between c22.Fdate and c22.Xdate --c22.VersionId=v.versionid
		and a.gear_type_dscr=c22.GearType and a.Med_Passenger_Limit_description between c22.MedPayLimitMin and c22.MedPayLimitMax
left join #MedPayBaseRate_third d22 on a.aircraft_type_description=d22.AircraftType and a.Primary_use_rating=d22.PrimaryUseId and dateadd(yy,1,getdate()) between d22.Fdate and d22.Xdate --d22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=d22.SeatIndex and a.Med_Passenger_Limit_description between d22.MedPayLimitMin and d22.MedPayLimitMax
left join #PilotIFRModifier b23 on a.aircraft_type_description=b23.AircraftType and a.Primary_use_rating=b23.PrimaryUseId and a.gear_type_dscr=b23.GearType and dateadd(yy,1,getdate()) between b23.Fdate and b23.Xdate --b23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=b23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =b23.PilotMinIFR
left join #PilotIFRModifier_second c23 on a.aircraft_type_description=c23.AircraftType and a.Primary_use_rating=c23.PrimaryUseId and dateadd(yy,1,getdate()) between c23.Fdate and c23.Xdate --c23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=c23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =c23.PilotMinIFR
left join #PilotIFRModifier_third d23 on a.aircraft_type_description=d23.AircraftType and dateadd(yy,1,getdate()) between d23.Fdate and d23.Xdate --d23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=d23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =d23.PilotMinIFR
left join #PilotGearHrsModifier b24 on  b24.AircraftType= a.aircraft_type_rating and b24.PrimaryUseId=a.Primary_use_rating and 	b24.GearType=a.gear_type_rating and b24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	b24.PilotGearHrsMin and case when b24.PilotGearHrsMax='NULL' or b24.PilotGearHrsMax is null then 999999999 else b24.PilotGearHrsMax end  and dateadd(yy,1,getdate()) between b24.Fdate and b24.Xdate --b24.VersionId=v.versionid
left join #PilotGearHrsModifier_second c24 on  c24.AircraftType= a.aircraft_type_rating and c24.PrimaryUseId=a.Primary_use_rating and c24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	c24.PilotGearHrsMin and case when c24.PilotGearHrsMax='NULL' or c24.PilotGearHrsMax is null then 999999999 else c24.PilotGearHrsMax end and dateadd(yy,1,getdate()) between c24.Fdate and c24.Xdate --c24.VersionId=v.versionid
left join #PilotGearHrsModifier_third d24 on  d24.AircraftType= a.aircraft_type_rating and d24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	d24.PilotGearHrsMin and case when d24.PilotGearHrsMax='NULL' or d24.PilotGearHrsMax is null then 999999999 else d24.PilotGearHrsMax end and dateadd(yy,1,getdate()) between d24.Fdate and d24.Xdate --d24.VersionId=v.versionid
left join #Coastal b25 on b25.[Airport_State]=case when state_risk <>'FL' then 'All Other States' else 'FL' end and [Airport_Coastal_Flag]=a.is_coastal and dateadd(yy,1,getdate()) between b25.Fdate and b25.Xdate --b25.VersionId=v.versionid
left join #Aircraft_Type_Modifier c28 on a.aircraft_type_description = c28.AircraftType and a.Primary_use_rating = c28.PrimaryUseId and a.gear_type_dscr = c28.GearType and dateadd(yy,1,getdate()) between c28.Fdate and c28.Xdate
left join #Aircraft_Type_Modifier_second d28 on a.aircraft_type_description = d28.AircraftType and a.Primary_use_rating = d28.PrimaryUseId and dateadd(yy,1,getdate()) between d28.Fdate and d28.Xdate
left join #ded_base_model_1 c25 on a.model_code = c25.ModelCode and a.model = c25.model  and a.make_dscr = c25.Manufacturer and a.aircraftuse_dscr = c25.[Use] and a.Coverage_group = c25.[Type] and dateadd(yy,1,getdate()) between c25.Fdate and c25.Xdate
left join #ded_base_model_2 d25 on a.model_code = d25.ModelCode and a.model = d25.model  and a.make_dscr = d25.Manufacturer and a.aircraftuse_dscr = d25.[Use] and dateadd(yy,1,getdate()) between d25.Fdate and d25.Xdate
left join #ded_base_model_3 e25 on a.model_code = e25.ModelCode and a.model = e25.model  and a.make_dscr = e25.Manufacturer and a.aircraftuse_dscr = e25.[Use] and dateadd(yy,1,getdate()) between e25.Fdate and e25.Xdate
left join #ded_base_age_1 c26 on a.aircraft_type_description = c26.[Aircraft type] and a.max_age between c26.[Age Low] and c26.[Age High] and dateadd(yy,1,getdate()) between c26.Fdate and c26.Xdate 
left join #ded_base_type_1 c27 on a.aircraft_type_description = c27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when c27.[Type] = 'GRO-NIM' then 'GRO-NIM' when c27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when c27.[Type] is null then 'GRO-Flight' else null end) and a.gear_type_rating = c27.[GEAR TYPE] and a.Primary_use_rating = c27.[Use] and dateadd(yy,1,getdate()) between c27.Fdate and c27.Xdate 
left join #ded_base_type_2 d27 on a.aircraft_type_description = d27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when d27.[Type] = 'GRO-NIM' then 'GRO-NIM' when d27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when d27.[Type] is null then 'GRO-Flight' else null end) and a.Primary_use_rating = d27.[Use] and dateadd(yy,1,getdate()) between d27.Fdate and d27.Xdate 
left join #ded_base_type_3 e27 on a.aircraft_type_description = e27.[AIRCRAFT DESCRIPTION] and a.Primary_use_rating = e27.[Use] and dateadd(yy,1,getdate()) between e27.Fdate and e27.Xdate 


ALTER TABLE #temp04
ADD rrr_max_base_deductible INT 

update #temp04
set rrr_BaseModelDeductible = case when rrr_BaseModelDeductible < 1 then isnull(rrr_BaseModelDeductible * hull_value,0)
								else isnull(rrr_BaseModelDeductible,0)
								end,
	rrr_BaseAgeDeductible = case when rrr_BaseAgeDeductible < 1 then isnull(rrr_BaseAgeDeductible * hull_value,0)
								else isnull(rrr_BaseAgeDeductible,0)
								end,
	rrr_BaseTypeDeductible = case when rrr_BaseTypeDeductible < 1 then isnull(rrr_BaseTypeDeductible * hull_value,0)
								else isnull(rrr_BaseTypeDeductible,0)
								end
update #temp04
set	rrr_max_base_deductible = CASE
							WHEN rrr_BaseModelDeductible >= rrr_BaseAgeDeductible AND rrr_BaseModelDeductible >= rrr_BaseTypeDeductible THEN rrr_BaseModelDeductible
							WHEN rrr_BaseAgeDeductible >= rrr_BaseModelDeductible AND rrr_BaseAgeDeductible >= rrr_BaseTypeDeductible THEN rrr_BaseAgeDeductible
							WHEN rrr_BaseTypeDeductible >= rrr_BaseModelDeductible AND rrr_BaseTypeDeductible >= rrr_BaseAgeDeductible THEN rrr_BaseTypeDeductible
							ELSE rrr_BaseModelDeductible
							END

--select * from #temp04	

 --rerating factors at expiration
if OBJECT_ID('tempdb.dbo.#temp05') is not null drop table #temp05
 select a.*
 ,v.versionid zz_versionid
 ,v.eff_date zz_version_eff_date
 ,isnull(b.RESULTVALUE,isnull(c.RESULTVALUE,0)) zz_AircraftModelModifierHull 
 ,isnull(b1.RESULTVALUE,isnull(c1.RESULTVALUE,0)) zz_AircraftModelModifierLiab
 ,isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) zz_SeatIndex
 ,isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE))) zz_PrimaryPilotRating 
 ,0 zz_airport_modifier 
 ,isnull(b4.RESULTVALUE,isnull(c4.RESULTVALUE,d4.RESULTVALUE)) zz_CMIndexHull 
 ,isnull(b5.RESULTVALUE,isnull(c5.RESULTVALUE,d5.RESULTVALUE)) zz_CMIndexLiability 
 ,b6.RESULTVALUE zz_CMIndexMedPay 
 ,b7.RESULTVALUE zz_StdDiscountHull 
 ,b8.RESULTVALUE zz_StdDiscountLiab
 ,isnull(b9.RESULTVALUE,isnull(c9.RESULTVALUE,isnull(d9.RESULTVALUE,e9.RESULTVALUE))) zz_IsManual 
 ,b10.RESULTVALUE zz_LiabilityOnlyModifier 
 ,isnull(b11.RESULTVALUE,c11.RESULTVALUE) zz_MinimumPremium
 ,isnull(b12.RESULTVALUE,c12.RESULTVALUE) zz_PilotMinTotalHrsModifier
 ,isnull(b13.RESULTVALUE,isnull(c13.RESULTVALUE,d13.RESULTVALUE)) zz_PilotMMHrsModifier
 ,isnull(b14.RESULTVALUE,isnull(c14.RESULTVALUE,d14.RESULTVALUE)) zz_PilotMEHrsModifier
 ,isnull(b15.RESULTVALUE,isnull(c15.RESULTVALUE,isnull(d15.RESULTVALUE,e15.RESULTVALUE))) zz_PilotAgeMinModifier
 ,isnull(b16.RESULTVALUE,isnull(c16.RESULTVALUE,isnull(d16.RESULTVALUE,e16.RESULTVALUE))) zz_PilotAgeMaxModifier
 ,isnull(b17.RESULTVALUE,isnull(c17.RESULTVALUE,isnull(d17.RESULTVALUE,e17.RESULTVALUE))) zz_HullModifier
 ,b18.RESULTVALUE zz_Ground_Modifier
 ,isnull(b19.RESULTVALUE,c19.RESULTVALUE) zz_HullBaseRate
 ,isnull(b20.RESULTVALUE,c20.RESULTVALUE) zz_LiabBaseRate
 ,isnull(b21.RESULTVALUE,c21.RESULTVALUE) zz_LiabBaseAddtlSeat  
 ,isnull(b22.RESULTVALUE,isnull(c22.RESULTVALUE,d22.RESULTVALUE)) zz_MedPayBaseRate  
 ,isnull(b23.RESULTVALUE,isnull(c23.RESULTVALUE,d23.RESULTVALUE)) zz_PilotIFRModifier
 ,round(isnull(b24.RESULTVALUE,isnull(c24.RESULTVALUE,d24.RESULTVALUE)),4) zz_PilotMinGearHrsModifier
 ,b25.rate zz_coastal_factor
 ,isnull(c28.RESULTVALUE,d28.RESULTVALUE) zz_AircraftTypeModifier
 ,isnull(c25.[Base_ded],isnull(d25.[Base_ded],e25.[Base_ded])) zz_BaseModelDeductible
 ,c26.[Min Ded] zz_BaseAgeDeductible
 ,isnull(c27.[Deductible],isnull(d27.[Deductible],e27.[Deductible])) zz_BaseTypeDeductible
 into #temp05
FROM #temp04 a
 left join #version v on dateadd(yy,1,a.date_pol_eff) between v.eff_date and v.exp_date
 left join #AircraftModelModifierHull b on b.AircraftType=a.aircraft_type_rating and b.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b.GearType and a.Model_Code=b.ModelCode and dateadd(yy,1,a.date_pol_eff) between b.Fdate and b.Xdate--b.VersionId=v.versionid
 left join #AircraftModelModifierHull_ex_gear c on c.AircraftType=a.aircraft_type_rating and c.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c.ModelCode and dateadd(yy,1,a.date_pol_eff) between c.Fdate and c.Xdate--and c.VersionId=v.versionid
 left join #AircraftModelModifierLiab b1 on b1.AircraftType=a.aircraft_type_rating and b1.PrimaryUseId=a.Primary_use_rating and a.gear_type_dscr=b1.GearType and a.Model_Code=b1.ModelCode and dateadd(yy,1,a.date_pol_eff) between b1.Fdate and b1.Xdate--b1.VersionId=v.versionid
 left join #AircraftModelModifierLiab_ex_gear c1 on c1.AircraftType=a.aircraft_type_rating and c1.PrimaryUseId=a.Primary_use_rating and a.Model_Code=c1.ModelCode  and dateadd(yy,1,a.date_pol_eff) between c1.Fdate and c1.Xdate--c1.VersionId=v.versionid
 left join #SeatIndex b2 on b2.AircraftType=a.aircraft_type_rating and b2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between b2.NoOfSeatsMin and case when b2.NoOfSeatsMax is null then 999999999 else b2.NoOfSeatsMax end and dateadd(yy,1,a.date_pol_eff) between b2.Fdate and b2.Xdate--b2.VersionId=v.versionid
 left join #SeatIndex_second c2 on  c2.PrimaryUseId=a.Primary_use_rating and seating_capacity_dscr between c2.NoOfSeatsMin and case when c2.NoOfSeatsMax is null then 999999999 else c2.NoOfSeatsMax end and dateadd(yy,1,a.date_pol_eff) between c2.Fdate and c2.Xdate --c2.VersionId=v.versionid
 left join #PrimaryPilotRating b3 on b3.AircraftType=a.aircraft_type_rating and b3.PrimaryUseId=a.Primary_use_rating and b3.GearType=a.gear_type_rating and cast(a.Min_Total_Hours as int) between b3.PilotMinTotalHrsMin and case when b3.PilotMinTotalHrsMax is null then 999999999 else b3.PilotMinTotalHrsMax end and dateadd(yy,1,a.date_pol_eff) between b3.Fdate and b3.Xdate --b3.VersionId=v.versionid
 left join #PrimaryPilotRating_second c3 on  c3.AircraftType=a.aircraft_type_rating and c3.PrimaryUseId=a.Primary_use_rating and cast(a.Min_Total_Hours as int) between c3.PilotMinTotalHrsMin and case when c3.PilotMinTotalHrsMax is null then 999999999 else c3.PilotMinTotalHrsMax end and dateadd(yy,1,a.date_pol_eff) between c3.Fdate and c3.Xdate--c3.VersionId=v.versionid
 left join #PrimaryPilotRating_third d3 on  d3.AircraftType=a.aircraft_type_rating and cast(a.Min_Total_Hours as int) between d3.PilotMinTotalHrsMin and case when d3.PilotMinTotalHrsMax is null then 999999999 else d3.PilotMinTotalHrsMax end and dateadd(yy,1,a.date_pol_eff) between d3.Fdate and d3.Xdate--d3.VersionId=v.versionid
 left join #PrimaryPilotRating_fourth e3 on  cast(a.Min_Total_Hours as int) between e3.PilotMinTotalHrsMin and case when e3.PilotMinTotalHrsMax is null then 999999999 else e3.PilotMinTotalHrsMax end and dateadd(yy,1,a.date_pol_eff) between e3.Fdate and e3.Xdate--e3.VersionId=v.versionid
 left join #CMIndexHull b4 on b4.AircraftType=a.aircraft_type_rating and b4.PrimaryUseId=a.Primary_use_rating and b4.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b4.Fdate and b4.Xdate--b4.VersionId=v.versionid
 left join #CMIndexHull_second c4 on  c4.AircraftType=a.aircraft_type_rating and c4.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c4.Fdate and c4.Xdate--c4.VersionId=v.versionid
 left join #CMIndexHull_third d4 on dateadd(yy,1,a.date_pol_eff) between d4.Fdate and d4.Xdate-- d4.VersionId=v.versionid
 left join #CMIndexLiability b5 on b5.AircraftType=a.aircraft_type_rating and b5.PrimaryUseId=a.Primary_use_rating and b5.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b5.Fdate and b5.Xdate--b5.VersionId=v.versionid
 left join #CMIndexLiability_second c5 on  c5.AircraftType=a.aircraft_type_rating and c5.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c5.Fdate and c5.Xdate-- c5.VersionId=v.versionid
 left join #CMIndexLiability_third d5 on dateadd(yy,1,a.date_pol_eff) between d5.Fdate and d5.Xdate-- d5.VersionId=v.versionid
 left join #CMIndexMedPay b6 on dateadd(yy,1,a.date_pol_eff) between b6.Fdate and b6.Xdate --b6.VersionId=v.versionid
 left join #StdDiscountHull b7 on dateadd(yy,1,a.date_pol_eff) between b7.Fdate and b7.Xdate --b7.VersionId=v.versionid
 left join #StdDiscountLiab b8 on dateadd(yy,1,a.date_pol_eff) between b8.Fdate and b8.Xdate  --b8.VersionId=v.versionid
 left join #IsManual b9 on b9.AircraftType=a.aircraft_type_rating and b9.PrimaryUseId=a.Primary_use_rating and b9.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b9.Fdate and b9.Xdate--b9.VersionId=v.versionid
 left join #IsManual_second c9 on c9.AircraftType=a.aircraft_type_rating and c9.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c9.Fdate and c9.Xdate--c9.VersionId=v.versionid
 left join #IsManual_third d9 on d9.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between d9.Fdate and d9.Xdate--d9.VersionId=v.versionid
 left join #IsManual_fourth e9 on dateadd(yy,1,a.date_pol_eff) between e9.Fdate and e9.Xdate--e9.VersionId=v.versionid
 left join #LiabilityOnlyModifier b10 on b10.HullValue = a.hull_value and dateadd(yy,1,a.date_pol_eff) between b10.Fdate and b10.Xdate--b10.VersionId=v.versionid
 left join #MinimumPremium b11 on b11.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between b11.Fdate and b11.Xdate--b11.VersionId=v.versionid
 left join #MinimumPremium_second c11 on dateadd(yy,1,a.date_pol_eff) between c11.Fdate and c11.Xdate--c11.VersionId=v.versionid
 left join #PilotMinTotalHrsModifier b12 on b12.AircraftType=a.aircraft_type_rating and b12.PrimaryUseId=a.Primary_use_rating and b12.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b12.Fdate and b12.Xdate --b12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between b12.PilotMinTotalHrsMin and case when isnull(b12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else b12.PilotMinTotalHrsMax end
 left join #PilotMinTotalHrsModifier_second c12 on c12.AircraftType=a.aircraft_type_rating and c12.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c12.Fdate and c12.Xdate --c12.VersionId=v.versionid
			and cast(a.Min_Total_Hours as int) between c12.PilotMinTotalHrsMin and case when isnull(c12.PilotMinTotalHrsMax, 'NULL') = 'NULL' then 999999999 else c12.PilotMinTotalHrsMax end
 left join #PilotMMHrsModifier b13 on b13.AircraftType=a.aircraft_type_rating and b13.PrimaryUseId=a.Primary_use_rating and b13.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b13.Fdate and b13.Xdate --b13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between b13.PilotMMHrsMin and case when b13.PilotMMHrsMax = 'NULL' then 999999999 else b13.PilotMMHrsMax end and b13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_second c13 on c13.AircraftType=a.aircraft_type_rating and c13.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c13.Fdate and c13.Xdate--c13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between c13.PilotMMHrsMin and case when c13.PilotMMHrsMax = 'NULL' then 999999999 else c13.PilotMMHrsMax end  and c13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMMHrsModifier_third d13 on d13.AircraftType=a.aircraft_type_rating and dateadd(yy,1,a.date_pol_eff) between d13.Fdate and d13.Xdate--d13.VersionId=v.versionid
			and cast(a.Min_MM_Hours as int) between d13.PilotMMHrsMin and case when d13.PilotMMHrsMax = 'NULL' then 999999999 else d13.PilotMMHrsMax end  and d13.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier b14 on b14.AircraftType=a.aircraft_type_rating and b14.PrimaryUseId=a.Primary_use_rating and b14.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b14.Fdate and b14.Xdate--b14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between b14.PilotMEHrsMin and case when b14.PilotMEHrsMax = 'NULL' or b14.PilotMEHrsMax is null then 999999999 else b14.PilotMEHrsMax end and b14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_second c14 on c14.AircraftType=a.aircraft_type_rating and c14.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c14.Fdate and c14.Xdate--c14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between c14.PilotMEHrsMin and case when c14.PilotMEHrsMax = 'NULL' or c14.PilotMEHrsMax is null then 999999999 else c14.PilotMEHrsMax end  and c14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotMEHrsModifier_third d14 on d14.AircraftType=a.aircraft_type_rating and dateadd(yy,1,a.date_pol_eff) between d14.Fdate and d14.Xdate--d14.VersionId=v.versionid
			and cast(a.Min_ME_Total as int) between d14.PilotMEHrsMin and case when d14.PilotMEHrsMax = 'NULL' or d14.PilotMEHrsMax is null then 999999999 else d14.PilotMEHrsMax end  and d14.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
 left join #PilotAgeMinModifier b15 on b15.AircraftType=a.aircraft_type_rating and b15.PrimaryUseId=a.Primary_use_rating and b15.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b15.Fdate and b15.Xdate--b15.VersionId=v.versionid
			and cast(a.min_age as int) between b15.PilotMinAgeMin and case when b15.PilotMinAgeMax = 'NULL' then 999999999 else b15.PilotMinAgeMax end 
 left join #PilotAgeMinModifier_second c15 on c15.AircraftType=a.aircraft_type_rating and c15.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c15.Fdate and c15.Xdate--c15.VersionId=v.versionid
			and cast(a.min_age as int) between c15.PilotMinAgeMin and case when c15.PilotMinAgeMax = 'NULL' then 999999999 else c15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_third d15 on d15.AircraftType=a.aircraft_type_rating and dateadd(yy,1,a.date_pol_eff) between d15.Fdate and d15.Xdate--d15.VersionId=v.versionid
			and cast(a.min_age as int) between d15.PilotMinAgeMin and case when d15.PilotMinAgeMax = 'NULL' then 999999999 else d15.PilotMinAgeMax end  
 left join #PilotAgeMinModifier_fourth e15 on dateadd(yy,1,a.date_pol_eff) between e15.Fdate and e15.Xdate--e15.VersionId=v.versionid 
			and cast(a.min_age as int) between e15.PilotMinAgeMin and case when e15.PilotMinAgeMax = 'NULL' then 999999999 else e15.PilotMinAgeMax end  
 left join #PilotAgeMaxModifier b16 on b16.AircraftType=a.aircraft_type_rating and b16.PrimaryUseId=a.Primary_use_rating and b16.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b16.Fdate and b16.Xdate--b16.VersionId=v.versionid
			and cast(a.max_age as int) between b16.PilotMaxAgeMin and case when b16.PilotMaxAgeMax = 'NULL' then 999999999 else b16.PilotMaxAgeMax end 
 left join #PilotAgeMaxModifier_second c16 on c16.AircraftType=a.aircraft_type_rating and c16.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c16.Fdate and c16.Xdate--c16.VersionId=v.versionid
			and cast(a.max_age as int) between c16.PilotMaxAgeMin and case when c16.PilotMaxAgeMax = 'NULL' then 999999999 else c16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_third d16 on d16.AircraftType=a.aircraft_type_rating and dateadd(yy,1,a.date_pol_eff) between d16.Fdate and d16.Xdate--d16.VersionId=v.versionid
			and cast(a.max_age as int) between d16.PilotMaxAgeMin and case when d16.PilotMaxAgeMax = 'NULL' then 999999999 else d16.PilotMaxAgeMax end  
 left join #PilotAgeMaxModifier_fourth e16 on dateadd(yy,1,a.date_pol_eff) between e16.Fdate and e16.Xdate --e16.VersionId=v.versionid 
			and cast(a.max_age as int) between e16.PilotMaxAgeMin and case when e16.PilotMaxAgeMax = 'NULL' then 999999999 else e16.PilotMaxAgeMax end  
 left join #HullModifier b17 on b17.AircraftType=a.aircraft_type_rating and b17.PrimaryUseId=a.Primary_use_rating and b17.GearType=a.gear_type_rating and dateadd(yy,1,a.date_pol_eff) between b17.Fdate and b17.Xdate--b17.VersionId=v.versionid
			and a.model_age between b17.HullAgeMin and case when isnull(b17.HullAgeMax,'Null') = 'NULL' then 999999999 else b17.HullAgeMax end 
 left join #HullModifier_second c17 on c17.AircraftType=a.aircraft_type_rating and c17.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c17.Fdate and c17.Xdate--c17.VersionId=v.versionid
			and a.model_age between c17.HullAgeMin and case when isnull(c17.HullAgeMax,'Null') = 'NULL' then 999999999 else c17.HullAgeMax end 
 left join #HullModifier_third d17 on d17.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between d17.Fdate and d17.Xdate --d17.VersionId=v.versionid
			and a.model_age between d17.HullAgeMin and case when isnull(d17.HullAgeMax,'Null') = 'NULL' then 999999999 else d17.HullAgeMax end 
 left join #HullModifier_fourth e17 on dateadd(yy,1,a.date_pol_eff) between e17.Fdate and e17.Xdate --e17.VersionId=v.versionid
			and a.model_age between e17.HullAgeMin and case when isnull(e17.HullAgeMax,'Null') = 'NULL' then 999999999 else e17.HullAgeMax end 
 left join #GroundOnlyModifier b18 on b18.coverage=a.limit_dscr and dateadd(yy,1,a.date_pol_eff) between b18.Fdate and b18.Xdate --b18.VersionId=v.versionid
 left join #HullBaseRate b19 on b19.AircraftType=a.aircraft_type_description and b19.PrimaryUseId=a.Primary_use_rating and b19.GearType=a.gear_type_dscr and 
			dateadd(yy,1,a.date_pol_eff) between (case when a.pol_ed > 1 then b19.fdate_ren else b19.Fdate end)
									and 
								(case when a.pol_ed > 1 then b19.xdate_ren else b19.Xdate end) --b19.VersionId=v.versionid
			and a.hull_value between b19.HullValueMin and b19.HullValueMax
 left join #HullBaseRate_second c19 on c19.AircraftType=a.aircraft_type_description and c19.PrimaryUseId=a.Primary_use_rating and 
			dateadd(yy,1,a.date_pol_eff) between (case when a.pol_ed > 1 then c19.fdate_ren else c19.Fdate end)
									and 
								(case when a.pol_ed > 1 then c19.xdate_ren else c19.Xdate end) --c19.VersionId=v.versionid
			and a.hull_value between c19.HullValueMin and c19.HullValueMax
  left join #LiabBaseRate b20 on b20.AircraftType=a.aircraft_type_rating and b20.geartype=a.gear_type_rating and b20.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between b20.Fdate and b20.Xdate --b20.VersionId=v.versionid
			and b20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description= b20.PassengerLimitText and a.CSL_Occurance_Limit = b20.LiabOccurLimitMin
 left join #LiabBaseRate_second c20 on c20.AircraftType=a.aircraft_type_rating and c20.PrimaryUseId=a.Primary_use_rating and dateadd(yy,1,a.date_pol_eff) between c20.Fdate and c20.Xdate --c20.VersionId=v.versionid
			and c20.SeatIndex=isnull(b2.RESULTVALUE,isnull(c2.RESULTVALUE,0)) and a.CSL_Passenger_Limit_description = c20.PassengerLimitText and a.CSL_Occurance_Limit = c20.LiabOccurLimitMin
 left join #LiabBaseAddtlSeat b21 on a.aircraft_type_rating=b21.AircraftType and a.Primary_use_rating=b21.PrimaryUseId and a.gear_type_rating=b21.GearType and b21.VersionId=v.versionid --dateadd(yy,1,a.date_pol_eff) between b21.Fdate and b21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=b21.PassengerLimitText
 left join #LiabBaseAddtlSeat_second c21 on a.aircraft_type_rating=c21.AircraftType and a.Primary_use_rating=c21.PrimaryUseId and c21.VersionId=v.versionid --dateadd(yy,1,a.date_pol_eff) between c21.Fdate and c21.Xdate
		and cast(a.CSL_Passenger_Limit_description as varchar(25))=c21.PassengerLimitText
left join #MedPayBaseRate b22 on a.aircraft_type_description=b22.AircraftType and a.Primary_use_rating=b22.PrimaryUseId and a.gear_type_dscr=b22.GearType and dateadd(yy,1,a.date_pol_eff) between b22.Fdate and b22.Xdate --b22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=b22.SeatIndex and a.Med_Passenger_Limit_description between b22.MedPayLimitMin and b22.MedPayLimitMax
left join #MedPayBaseRate_second c22 on a.aircraft_type_description=c22.AircraftType and a.Primary_use_rating=c22.PrimaryUseId and dateadd(yy,1,a.date_pol_eff) between c22.Fdate and c22.Xdate --c22.VersionId=v.versionid
		and a.gear_type_dscr=c22.GearType and a.Med_Passenger_Limit_description between c22.MedPayLimitMin and c22.MedPayLimitMax
left join #MedPayBaseRate_third d22 on a.aircraft_type_description=d22.AircraftType and a.Primary_use_rating=d22.PrimaryUseId and dateadd(yy,1,a.date_pol_eff) between d22.Fdate and d22.Xdate --d22.VersionId=v.versionid
		and isnull(a.seating_capacity_dscr,0)=d22.SeatIndex and a.Med_Passenger_Limit_description between d22.MedPayLimitMin and d22.MedPayLimitMax
left join #PilotIFRModifier b23 on a.aircraft_type_description=b23.AircraftType and a.Primary_use_rating=b23.PrimaryUseId and a.gear_type_dscr=b23.GearType and dateadd(yy,1,a.date_pol_eff) between b23.Fdate and b23.Xdate --b23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=b23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =b23.PilotMinIFR
left join #PilotIFRModifier_second c23 on a.aircraft_type_description=c23.AircraftType and a.Primary_use_rating=c23.PrimaryUseId and dateadd(yy,1,a.date_pol_eff) between c23.Fdate and c23.Xdate --c23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=c23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =c23.PilotMinIFR
left join #PilotIFRModifier_third d23 on a.aircraft_type_description=d23.AircraftType and dateadd(yy,1,a.date_pol_eff) between d23.Fdate and d23.Xdate --d23.VersionId=v.versionid
		and isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))=d23.PrimaryPilotRating and case when a.[IFR-FW] =  1 or a.[IFR-RW] =  1 then 1 else 0 end  =d23.PilotMinIFR
left join #PilotGearHrsModifier b24 on  b24.AircraftType= a.aircraft_type_rating and b24.PrimaryUseId=a.Primary_use_rating and 	b24.GearType=a.gear_type_rating and b24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	b24.PilotGearHrsMin and case when b24.PilotGearHrsMax='NULL' or b24.PilotGearHrsMax is null then 999999999 else b24.PilotGearHrsMax end  and dateadd(yy,1,a.date_pol_eff) between b24.Fdate and b24.Xdate --b24.VersionId=v.versionid
left join #PilotGearHrsModifier_second c24 on  c24.AircraftType= a.aircraft_type_rating and c24.PrimaryUseId=a.Primary_use_rating and c24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	c24.PilotGearHrsMin and case when c24.PilotGearHrsMax='NULL' or c24.PilotGearHrsMax is null then 999999999 else c24.PilotGearHrsMax end and dateadd(yy,1,a.date_pol_eff) between c24.Fdate and c24.Xdate --c24.VersionId=v.versionid
left join #PilotGearHrsModifier_third d24 on  d24.AircraftType= a.aircraft_type_rating and d24.PrimaryPilotRating=isnull(b3.RESULTVALUE,isnull(c3.RESULTVALUE,isnull(d3.RESULTVALUE,e3.RESULTVALUE)))
		and a.gearhour between	d24.PilotGearHrsMin and case when d24.PilotGearHrsMax='NULL' or d24.PilotGearHrsMax is null then 999999999 else d24.PilotGearHrsMax end and dateadd(yy,1,a.date_pol_eff) between d24.Fdate and d24.Xdate --d24.VersionId=v.versionid
left join #Coastal b25 on b25.[Airport_State]=case when state_risk <>'FL' then 'All Other States' else 'FL' end and [Airport_Coastal_Flag]=a.is_coastal and dateadd(yy,1,a.date_pol_eff) between b25.Fdate and b25.Xdate --b25.VersionId=v.versionid
left join #Aircraft_Type_Modifier c28 on a.aircraft_type_description = c28.AircraftType and a.Primary_use_rating = c28.PrimaryUseId and a.gear_type_dscr = c28.GearType and dateadd(yy,1,a.date_pol_eff) between c28.Fdate and c28.Xdate
left join #Aircraft_Type_Modifier_second d28 on a.aircraft_type_description = d28.AircraftType and a.Primary_use_rating = d28.PrimaryUseId and dateadd(yy,1,a.date_pol_eff) between d28.Fdate and d28.Xdate
left join #ded_base_model_1 c25 on a.model_code = c25.ModelCode and a.model = c25.model  and a.make_dscr = c25.Manufacturer and a.aircraftuse_dscr = c25.[Use] and a.Coverage_group = c25.[Type] and dateadd(yy,1,a.date_pol_eff) between c25.Fdate and c25.Xdate
left join #ded_base_model_2 d25 on a.model_code = d25.ModelCode and a.model = d25.model  and a.make_dscr = d25.Manufacturer and a.aircraftuse_dscr = d25.[Use] and dateadd(yy,1,a.date_pol_eff) between d25.Fdate and d25.Xdate
left join #ded_base_model_3 e25 on a.model_code = e25.ModelCode and a.model = e25.model  and a.make_dscr = e25.Manufacturer and a.aircraftuse_dscr = e25.[Use] and dateadd(yy,1,a.date_pol_eff) between e25.Fdate and e25.Xdate
left join #ded_base_age_1 c26 on a.aircraft_type_description = c26.[Aircraft type] and a.max_age between c26.[Age Low] and c26.[Age High] and dateadd(yy,1,a.date_pol_eff) between c26.Fdate and c26.Xdate 
left join #ded_base_type_1 c27 on a.aircraft_type_description = c27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when c27.[Type] = 'GRO-NIM' then 'GRO-NIM' when c27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when c27.[Type] is null then 'GRO-Flight' else null end) and a.gear_type_rating = c27.[GEAR TYPE] and a.Primary_use_rating = c27.[Use] and dateadd(yy,1,a.date_pol_eff) between c27.Fdate and c27.Xdate 
left join #ded_base_type_2 d27 on a.aircraft_type_description = d27.[AIRCRAFT DESCRIPTION] and a.Coverage_group = (case when d27.[Type] = 'GRO-NIM' then 'GRO-NIM' when d27.[Type] = 'GRO-Taxi' then 'GRO-Taxi' when d27.[Type] is null then 'GRO-Flight' else null end) and a.Primary_use_rating = d27.[Use] and dateadd(yy,1,a.date_pol_eff) between d27.Fdate and d27.Xdate 
left join #ded_base_type_3 e27 on a.aircraft_type_description = e27.[AIRCRAFT DESCRIPTION] and a.Primary_use_rating = e27.[Use] and dateadd(yy,1,a.date_pol_eff) between e27.Fdate and e27.Xdate 


ALTER TABLE #temp05
ADD zz_max_base_deductible INT 

update #temp05
set zz_BaseModelDeductible = case when zz_BaseModelDeductible < 1 then isnull(zz_BaseModelDeductible * hull_value,0)
								else isnull(zz_BaseModelDeductible,0)
								end,
	zz_BaseAgeDeductible = case when zz_BaseAgeDeductible < 1 then isnull(zz_BaseAgeDeductible * hull_value,0)
								else isnull(zz_BaseAgeDeductible,0)
								end,
	zz_BaseTypeDeductible = case when zz_BaseTypeDeductible < 1 then isnull(zz_BaseTypeDeductible * hull_value,0)
								else isnull(zz_BaseTypeDeductible,0)
								end
update #temp05
set	zz_max_base_deductible = CASE
							WHEN zz_BaseModelDeductible >= zz_BaseAgeDeductible AND zz_BaseModelDeductible >= zz_BaseTypeDeductible THEN zz_BaseModelDeductible
							WHEN zz_BaseAgeDeductible >= zz_BaseModelDeductible AND zz_BaseAgeDeductible >= zz_BaseTypeDeductible THEN zz_BaseAgeDeductible
							WHEN zz_BaseTypeDeductible >= zz_BaseModelDeductible AND zz_BaseTypeDeductible >= zz_BaseAgeDeductible THEN zz_BaseTypeDeductible
							ELSE zz_BaseModelDeductible
							END

alter table #temp05
alter column premium_tech_annual float

alter table #temp05
alter column premium_written float


---------------------------------------------------------------
--90009
--90064
--90066
--calculate the deductible offset
if OBJECT_ID('tempdb.dbo.#temp06') is not null drop table #temp06
select 
	case 
			--90009
			when coveragecode_id = 90009 and PD_Limit <> 'Ground - Not In Motion' 
			then round(round(round(cast(r_HullBaseRate * (cast(r_CMIndexHull as float)/100) * (isnull(r_Ground_Modifier,0)) as money) ,2) * round(cast((1 + isnull(r_PilotMinGearHrsModifier,0) + isnull(r_PilotMinTotalHrsModifier,0) + isnull(r_PilotMMHrsModifier,0)	+ isnull(r_PilotMEHrsModifier,0)
									+ isnull(r_PilotIFRModifier,0) + isnull(r_HullModifier,0) + isnull(r_PilotAgeMaxModifier,0) - 1 + isnull(r_AircraftModelModifierHull,0) + isnull(r_StdDiscountHull,0) + isnull(r_coastal_factor,0) + isnull(r_AircraftTypeModifier,0)) as money),2),2) * round(cast(hull_value / 100 as money),2), 0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground - Not In Motion' 
			then round(round(r_HullBaseRate * (cast(r_CMIndexHull as float)/100),2) * (cast(isnull(r_Ground_Modifier,0) as money)) * (isnull(r_StdDiscountHull,0) + isnull(r_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(round(r_HullBaseRate * (cast(r_CMIndexHull as float)/100),2) * (cast(isnull(r_Ground_Modifier,0) as money)) * (isnull(r_StdDiscountHull,0) + isnull(r_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			--90064
			when coveragecode_id = 90064 and (PD_Limit <> 'Ground - Not In Motion' or PD_Limit is null)
			THEN round(round(round(cast(isnull(r_LiabBaseRate,0) * (cast(r_CMIndexLiability as float)/100) as money) ,4) * round(cast((1 + isnull(r_PilotMinGearHrsModifier,0) + isnull(r_PilotMinTotalHrsModifier,0) + ISNULL(r_PilotIFRModifier,0) + isnull(r_PilotMMHrsModifier,0)	+ isnull(r_PilotMEHrsModifier,0)
									+ isnull(r_PilotAgeMaxModifier,0) - 1 + isnull(r_AircraftModelModifierLiab,0) + isnull(r_AircraftTypeModifier,0)) as money) ,2),2) * case when PD_Limit_description = 'Null' or PD_Limit_description = 'No Coverage' or PD_Limit_description is Null then 1 + r_LiabilityOnlyModifier else 1 end,2)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground - Not In Motion' 
			then round(cast(r_LiabBaseRate * (cast(r_CMIndexLiability as float)/100) as money),0)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(cast(r_LiabBaseRate * (cast(r_CMIndexLiability as float)/100) as money),0)
			
			--90157
			when coveragecode_id=90157
			then .4 * round(round(round(r_HullBaseRate * (cast(r_CMIndexHull as float)/100) * (1+isnull(r_Ground_Modifier,0)) ,2) * round((1 + isnull(r_PilotMinGearHrsModifier,0) + isnull(r_PilotMinTotalHrsModifier,0) + isnull(r_PilotMMHrsModifier,0)	+ isnull(r_PilotMEHrsModifier,0)
									+ isnull(r_PilotIFRModifier,0) + isnull(r_HullModifier,0) + isnull(r_PilotAgeMaxModifier,0) - 1 + isnull(r_AircraftModelModifierHull,0) + isnull(r_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90158
			when coveragecode_id=90158
			then .6 * round(round(round(r_HullBaseRate * (cast(r_CMIndexHull as float)/100) * (1+isnull(r_Ground_Modifier,0)) ,2) * round((1 + isnull(r_PilotMinGearHrsModifier,0) + isnull(r_PilotMinTotalHrsModifier,0) + isnull(r_PilotMMHrsModifier,0)	+ isnull(r_PilotMEHrsModifier,0)
									+ isnull(r_PilotIFRModifier,0) + isnull(r_HullModifier,0) + isnull(r_PilotAgeMaxModifier,0) - 1 + isnull(r_AircraftModelModifierHull,0) + isnull(r_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90066
			when coveragecode_id=90066 
			then r_MedPayBaseRate * r_CMIndexMedPay/100
			
			END r_prem_tech_annual --calculate the manual premium
	,case 
			--90009
			when coveragecode_id = 90009 and PD_Limit <> 'Ground - Not In Motion' 
			then round(round(round(cast(rr_HullBaseRate * (cast(rr_CMIndexHull as float)/100) * (isnull(rr_Ground_Modifier,0)) as money) ,2) * round(cast((1 + isnull(rr_PilotMinGearHrsModifier,0) + isnull(rr_PilotMinTotalHrsModifier,0) + isnull(rr_PilotMMHrsModifier,0)	+ isnull(rr_PilotMEHrsModifier,0)
									+ isnull(rr_PilotIFRModifier,0) + isnull(rr_HullModifier,0) + isnull(rr_PilotAgeMaxModifier,0) - 1 + isnull(rr_AircraftModelModifierHull,0) + isnull(rr_StdDiscountHull,0) + isnull(rr_coastal_factor,0) + isnull(rr_AircraftTypeModifier,0)) as money),2),2) * round(cast(hull_value / 100 as money),2), 0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground - Not In Motion' 
			then round(round(rr_HullBaseRate * (cast(rr_CMIndexHull as float)/100),2) * (cast(isnull(rr_Ground_Modifier,0) as money)) * (isnull(rr_StdDiscountHull,0) + isnull(rr_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(round(rr_HullBaseRate * (cast(rr_CMIndexHull as float)/100),2) * (cast(isnull(rr_Ground_Modifier,0) as money)) * (isnull(rr_StdDiscountHull,0) + isnull(rr_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			--90064
			when coveragecode_id = 90064 and (PD_Limit <> 'Ground - Not In Motion' or PD_Limit is null)
			THEN round(round(round(cast(isnull(rr_LiabBaseRate,0) * (cast(rr_CMIndexLiability as float)/100) as money) ,4) * round(cast((1 + isnull(rr_PilotMinGearHrsModifier,0) + isnull(rr_PilotMinTotalHrsModifier,0) + ISNULL(rr_PilotIFRModifier,0) + isnull(rr_PilotMMHrsModifier,0)	+ isnull(rr_PilotMEHrsModifier,0)
									+ isnull(rr_PilotAgeMaxModifier,0) - 1 + isnull(rr_AircraftModelModifierLiab,0) + isnull(rr_AircraftTypeModifier,0)) as money) ,2),2) * case when PD_Limit_description = 'Null' or PD_Limit_description = 'No Coverage' or PD_Limit_description is Null then 1 + rr_LiabilityOnlyModifier else 1 end,2)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground - Not In Motion' 
			then round(cast(rr_LiabBaseRate * (cast(rr_CMIndexLiability as float)/100) as money),0)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(cast(rr_LiabBaseRate * (cast(rr_CMIndexLiability as float)/100) as money),0)
			
			--90157
			when coveragecode_id=90157
			then .4 * round(round(round(rr_HullBaseRate * (cast(rr_CMIndexHull as float)/100) * (1+isnull(rr_Ground_Modifier,0)) ,2) * round((1 + isnull(rr_PilotMinGearHrsModifier,0) + isnull(rr_PilotMinTotalHrsModifier,0) + isnull(rr_PilotMMHrsModifier,0)	+ isnull(rr_PilotMEHrsModifier,0)
									+ isnull(rr_PilotIFRModifier,0) + isnull(rr_HullModifier,0) + isnull(rr_PilotAgeMaxModifier,0) - 1 + isnull(rr_AircraftModelModifierHull,0) + isnull(rr_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90158
			when coveragecode_id=90158
			then .6 * round(round(round(rr_HullBaseRate * (cast(rr_CMIndexHull as float)/100) * (1+isnull(rr_Ground_Modifier,0)) ,2) * round((1 + isnull(rr_PilotMinGearHrsModifier,0) + isnull(rr_PilotMinTotalHrsModifier,0) + isnull(rr_PilotMMHrsModifier,0)	+ isnull(rr_PilotMEHrsModifier,0)
									+ isnull(rr_PilotIFRModifier,0) + isnull(rr_HullModifier,0) + isnull(rr_PilotAgeMaxModifier,0) - 1 + isnull(rr_AircraftModelModifierHull,0) + isnull(rr_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90066
			when coveragecode_id=90066 
			then rr_MedPayBaseRate * rr_CMIndexMedPay/100
			
			END rr_prem_tech_annual --calculate the manual premium
	,case 
			--90009
			when coveragecode_id = 90009 and PD_Limit <> 'Ground - Not In Motion' 
			then round(round(round(cast(rrr_HullBaseRate * (cast(rrr_CMIndexHull as float)/100) * (isnull(rrr_Ground_Modifier,0)) as money) ,2) * round(cast((1 + isnull(rrr_PilotMinGearHrsModifier,0) + isnull(rrr_PilotMinTotalHrsModifier,0) + isnull(rrr_PilotMMHrsModifier,0)	+ isnull(rrr_PilotMEHrsModifier,0)
									+ isnull(rrr_PilotIFRModifier,0) + isnull(rrr_HullModifier,0) + isnull(rrr_PilotAgeMaxModifier,0) - 1 + isnull(rrr_AircraftModelModifierHull,0) + isnull(rrr_StdDiscountHull,0) + isnull(rrr_coastal_factor,0) + isnull(rrr_AircraftTypeModifier,0)) as money),2),2) * round(cast(hull_value / 100 as money),2), 0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground - Not In Motion' 
			then round(round(rrr_HullBaseRate * (cast(rrr_CMIndexHull as float)/100),2) * (cast(isnull(rrr_Ground_Modifier,0) as money)) * (isnull(rrr_StdDiscountHull,0) + isnull(rrr_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(round(rrr_HullBaseRate * (cast(rrr_CMIndexHull as float)/100),2) * (cast(isnull(rrr_Ground_Modifier,0) as money)) * (isnull(rrr_StdDiscountHull,0) + isnull(rrr_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			--90064
			when coveragecode_id = 90064 and (PD_Limit <> 'Ground - Not In Motion' or PD_Limit is null)
			THEN round(round(round(cast(isnull(rrr_LiabBaseRate,0) * (cast(rrr_CMIndexLiability as float)/100) as money) ,4) * round(cast((1 + isnull(rrr_PilotMinGearHrsModifier,0) + isnull(rrr_PilotMinTotalHrsModifier,0) + ISNULL(rrr_PilotIFRModifier,0) + isnull(rrr_PilotMMHrsModifier,0)	+ isnull(rrr_PilotMEHrsModifier,0)
									+ isnull(rrr_PilotAgeMaxModifier,0) - 1 + isnull(rrr_AircraftModelModifierLiab,0) + isnull(rrr_AircraftTypeModifier,0)) as money) ,2),2) * case when PD_Limit_description = 'Null' or PD_Limit_description = 'No Coverage' or PD_Limit_description is Null then 1 + rrr_LiabilityOnlyModifier else 1 end,2)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground - Not In Motion' 
			then round(cast(rrr_LiabBaseRate * (cast(rrr_CMIndexLiability as float)/100) as money),0)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(cast(rrr_LiabBaseRate * (cast(rrr_CMIndexLiability as float)/100) as money),0)
			
			--90157
			when coveragecode_id=90157
			then .4 * round(round(round(rrr_HullBaseRate * (cast(rrr_CMIndexHull as float)/100) * (1+isnull(rrr_Ground_Modifier,0)) ,2) * round((1 + isnull(rrr_PilotMinGearHrsModifier,0) + isnull(rrr_PilotMinTotalHrsModifier,0) + isnull(rrr_PilotMMHrsModifier,0)	+ isnull(rrr_PilotMEHrsModifier,0)
									+ isnull(rrr_PilotIFRModifier,0) + isnull(rrr_HullModifier,0) + isnull(rrr_PilotAgeMaxModifier,0) - 1 + isnull(rrr_AircraftModelModifierHull,0) + isnull(rrr_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90158
			when coveragecode_id=90158
			then .6 * round(round(round(rrr_HullBaseRate * (cast(rrr_CMIndexHull as float)/100) * (1+isnull(rrr_Ground_Modifier,0)) ,2) * round((1 + isnull(rrr_PilotMinGearHrsModifier,0) + isnull(rrr_PilotMinTotalHrsModifier,0) + isnull(rrr_PilotMMHrsModifier,0)	+ isnull(rrr_PilotMEHrsModifier,0)
									+ isnull(rrr_PilotIFRModifier,0) + isnull(rrr_HullModifier,0) + isnull(rrr_PilotAgeMaxModifier,0) - 1 + isnull(rrr_AircraftModelModifierHull,0) + isnull(rrr_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90066
			when coveragecode_id=90066 
			then rrr_MedPayBaseRate * rrr_CMIndexMedPay/100
			
			END rrr_prem_tech_annual --calculate the manual premium
	,case 
			--90009
			when coveragecode_id = 90009 and PD_Limit <> 'Ground - Not In Motion' 
			then round(round(round(cast(zz_HullBaseRate * (cast(zz_CMIndexHull as float)/100) * (isnull(zz_Ground_Modifier,0)) as money) ,2) * round(cast((1 + isnull(zz_PilotMinGearHrsModifier,0) + isnull(zz_PilotMinTotalHrsModifier,0) + isnull(zz_PilotMMHrsModifier,0)	+ isnull(zz_PilotMEHrsModifier,0)
									+ isnull(zz_PilotIFRModifier,0) + isnull(zz_HullModifier,0) + isnull(zz_PilotAgeMaxModifier,0) - 1 + isnull(zz_AircraftModelModifierHull,0) + isnull(zz_StdDiscountHull,0) + isnull(zz_coastal_factor,0) + isnull(zz_AircraftTypeModifier,0)) as money),2),2) * round(cast(hull_value / 100 as money),2), 0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground - Not In Motion' 
			then round(round(zz_HullBaseRate * (cast(zz_CMIndexHull as float)/100),2) * (cast(isnull(zz_Ground_Modifier,0) as money)) * (isnull(zz_StdDiscountHull,0) + isnull(zz_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(round(zz_HullBaseRate * (cast(zz_CMIndexHull as float)/100),2) * (cast(isnull(zz_Ground_Modifier,0) as money)) * (isnull(zz_StdDiscountHull,0) + isnull(zz_coastal_factor,0) + 1) * round(cast(hull_value / 100 as money),2),0)
			
			--90064
			when coveragecode_id = 90064 and (PD_Limit <> 'Ground - Not In Motion' or PD_Limit is null)
			THEN round(round(round(cast(isnull(zz_LiabBaseRate,0) * (cast(zz_CMIndexLiability as float)/100) as money) ,4) * round(cast((1 + isnull(zz_PilotMinGearHrsModifier,0) + isnull(zz_PilotMinTotalHrsModifier,0) + ISNULL(zz_PilotIFRModifier,0) + isnull(zz_PilotMMHrsModifier,0)	+ isnull(zz_PilotMEHrsModifier,0)
									+ isnull(zz_PilotAgeMaxModifier,0) - 1 + isnull(zz_AircraftModelModifierLiab,0) + isnull(zz_AircraftTypeModifier,0)) as money) ,2),2) * case when PD_Limit_description = 'Null' or PD_Limit_description = 'No Coverage' or PD_Limit_description is Null then 1 + zz_LiabilityOnlyModifier else 1 end,2)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground - Not In Motion' 
			then round(cast(zz_LiabBaseRate * (cast(zz_CMIndexLiability as float)/100) as money),0)
			
			when coveragecode_id = 90064 and PD_Limit = 'Ground & Taxi (excluding In Flight)' 
			then round(cast(zz_LiabBaseRate * (cast(zz_CMIndexLiability as float)/100) as money),0)
			
			--90157
			when coveragecode_id=90157
			then .4 * round(round(round(zz_HullBaseRate * (cast(zz_CMIndexHull as float)/100) * (1+isnull(zz_Ground_Modifier,0)) ,2) * round((1 + isnull(zz_PilotMinGearHrsModifier,0) + isnull(zz_PilotMinTotalHrsModifier,0) + isnull(zz_PilotMMHrsModifier,0)	+ isnull(zz_PilotMEHrsModifier,0)
									+ isnull(zz_PilotIFRModifier,0) + isnull(zz_HullModifier,0) + isnull(zz_PilotAgeMaxModifier,0) - 1 + isnull(zz_AircraftModelModifierHull,0) + isnull(zz_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90158
			when coveragecode_id=90158
			then .6 * round(round(round(zz_HullBaseRate * (cast(zz_CMIndexHull as float)/100) * (1+isnull(zz_Ground_Modifier,0)) ,2) * round((1 + isnull(zz_PilotMinGearHrsModifier,0) + isnull(zz_PilotMinTotalHrsModifier,0) + isnull(zz_PilotMMHrsModifier,0)	+ isnull(zz_PilotMEHrsModifier,0)
									+ isnull(zz_PilotIFRModifier,0) + isnull(zz_HullModifier,0) + isnull(zz_PilotAgeMaxModifier,0) - 1 + isnull(zz_AircraftModelModifierHull,0) + isnull(zz_StdDiscountHull,0)),2),2) * round(hull_value / 100,2),0) 
			
			--90066
			when coveragecode_id=90066 
			then zz_MedPayBaseRate * zz_CMIndexMedPay/100
			
			END zz_prem_tech_annual --calculate the manual premium
,cast(datediff(dd,min_birth_date,date_pol_eff) as float)/365 as a
,datediff(yy,min_birth_date,date_pol_eff) as b
,*
into #temp06
from #temp05 

alter table #temp06
alter column adjustment_factor float

------------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#temp07') is not null drop table #temp07
select 
	* 
	,case when adjustment_type = 'Rate' 
			then round(isnull(adjustment_factor,0) * isnull(r_prem_tech_annual,0),0)
			when adjustment_type = 'dollar'
			then isnull(adjustment_factor,0)
			end as adjustment --calculate the adjustment amount
	,case when adjustment_type = 'Dollar'
			then isnull(r_prem_tech_annual,0) + isnull(adjustment_factor,0) 
			when adjustment_type = 'Rate' 
			then (1 + isnull(adjustment_factor,0)) * isnull(r_prem_tech_annual,0)
			end as r_prem_annual  --adding adjustment amount to the manual premium
	,case when adjustment_type = 'Dollar'
			then isnull(rr_prem_tech_annual,0) + isnull(adjustment_factor,0) 
			when adjustment_type = 'Rate' 
			then (1 + isnull(adjustment_factor,0)) * isnull(rr_prem_tech_annual,0)
			end as rr_prem_annual  --adding adjustment amount to the manual premium
	,case when adjustment_type = 'Dollar'
			then isnull(rrr_prem_tech_annual,0) + isnull(adjustment_factor,0) 
			when adjustment_type = 'Rate' 
			then (1 + isnull(adjustment_factor,0)) * isnull(rrr_prem_tech_annual,0)
			end as rrr_prem_annual  --adding adjustment amount to the manual premium
	,case when adjustment_type = 'Dollar'
			then isnull(zz_prem_tech_annual,0) + isnull(adjustment_factor,0) 
			when adjustment_type = 'Rate' 
			then (1 + isnull(adjustment_factor,0)) * isnull(zz_prem_tech_annual,0)
			end as zz_prem_annual  --adding adjustment amount to the manual premium
into #temp07 
from #temp06 

update #temp07
set r_prem_annual = round(r_prem_annual, 0)
update #temp07
set rr_prem_annual = round(rr_prem_annual, 0)
update #temp07
set rrr_prem_annual = round(rrr_prem_annual, 0)
update #temp07
set zz_prem_annual = round(zz_prem_annual, 0)
update #temp07
set r_prem_tech_annual = isnull(r_prem_tech_annual, 0)
update #temp07
set rr_prem_tech_annual = isnull(rr_prem_tech_annual, 0)
update #temp07
set rrr_prem_tech_annual = isnull(rrr_prem_tech_annual, 0)
update #temp07
set zz_prem_tech_annual = isnull(zz_prem_tech_annual, 0)


if OBJECT_ID('tempdb.dbo.#temp08') is not null drop table #temp08
select 
	*
	,case when coveragecode_id = 90009 and PD_Limit = 'Ground - Not in Motion' then 0
											when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' then 0
											when coveragecode_id = 90009 and r_max_base_deductible is not null and hull_value <> 0 then (selected_deductible - r_max_base_deductible)/(hull_value)*r_prem_tech_annual
											when coveragecode_id = 90009 and r_max_base_deductible is null or r_max_base_deductible = 0 then 0
											else 0
											end r_deductible_premtechannual --calculate deductible amount based off maunal premium
	,case when coveragecode_id = 90009 and PD_Limit = 'Ground - Not in Motion' then 0
										when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' then 0
										when coveragecode_id = 90009 and r_max_base_deductible is not null and hull_value <> 0 then (selected_deductible - r_max_base_deductible)/(hull_value)*r_prem_annual
										when coveragecode_id = 90009 and r_max_base_deductible is null or r_max_base_deductible = 0 then 0
										else 0
										end r_deductible_premannual --calculate deductible amount based off adjusted manual premium
	,case when coveragecode_id = 90009 and PD_Limit = 'Ground - Not in Motion' then 0
											when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' then 0
											when coveragecode_id = 90009 and rr_max_base_deductible is not null and hull_value <> 0 then (selected_deductible - rr_max_base_deductible)/(hull_value)*rr_prem_tech_annual
											when coveragecode_id = 90009 and rr_max_base_deductible is null or rr_max_base_deductible = 0 then 0
											else 0
											end rr_deductible_premtechannual --calculate deductible amount based off maunal premium
	,case when coveragecode_id = 90009 and PD_Limit = 'Ground - Not in Motion' then 0
										when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' then 0
										when coveragecode_id = 90009 and rr_max_base_deductible is not null and hull_value <> 0 then (selected_deductible - rr_max_base_deductible)/(hull_value)*rr_prem_annual
										when coveragecode_id = 90009 and rr_max_base_deductible is null or rr_max_base_deductible = 0 then 0
										else 0
										end rr_deductible_premannual --calculate deductible amount based off adjusted manual premium
	,case when coveragecode_id = 90009 and PD_Limit = 'Ground - Not in Motion' then 0
											when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' then 0
											when coveragecode_id = 90009 and rrr_max_base_deductible is not null and hull_value <> 0 then (selected_deductible - rrr_max_base_deductible)/(hull_value)*rrr_prem_tech_annual
											when coveragecode_id = 90009 and rrr_max_base_deductible is null or rrr_max_base_deductible = 0 then 0
											else 0
											end rrr_deductible_premtechannual --calculate deductible amount based off maunal premium
	,case when coveragecode_id = 90009 and PD_Limit = 'Ground - Not in Motion' then 0
										when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' then 0
										when coveragecode_id = 90009 and rrr_max_base_deductible is not null and hull_value <> 0 then (selected_deductible - rrr_max_base_deductible)/(hull_value)*rrr_prem_annual
										when coveragecode_id = 90009 and rrr_max_base_deductible is null or rrr_max_base_deductible = 0 then 0
										else 0
										end rrr_deductible_premannual --calculate deductible amount based off adjusted manual premium
	,case when coveragecode_id = 90009 and PD_Limit = 'Ground - Not in Motion' then 0
										when coveragecode_id = 90009 and PD_Limit = 'Ground & Taxi (excluding In Flight)' then 0
										when coveragecode_id = 90009 and zz_max_base_deductible is not null and hull_value <> 0 then (selected_deductible - zz_max_base_deductible)/(hull_value)*zz_prem_annual
										when coveragecode_id = 90009 and zz_max_base_deductible is null or zz_max_base_deductible = 0 then 0
										else 0
										end zz_deductible_premannual --calculate deductible amount based off adjusted manual premium
into #temp08
from #temp07


if OBJECT_ID('tempdb.dbo.#temp09') is not null drop table #temp09
select 
	*
	,case 	when coveragecode_id = 90009 and r_prem_tech_annual <> 0 and adjustment = 0 then r_deductible_premannual / r_prem_tech_annual
			when coveragecode_id = 90009 and adjustment <> 0 and r_prem_tech_annual = 0  then r_deductible_premannual / adjustment
			when coveragecode_id = 90009 and (isnull(r_prem_tech_annual,0) <> 0 and isnull(adjustment,0) <> 0) and (r_prem_tech_annual + adjustment) <> 0 then r_deductible_premannual / (r_prem_tech_annual + adjustment) 
			else 0 end as r_deductible_factor --calculate the deductible factor
	,case 	when coveragecode_id = 90009 and rr_prem_tech_annual <> 0 and adjustment = 0 then rr_deductible_premannual / rr_prem_tech_annual
			when coveragecode_id = 90009 and adjustment <> 0 and rr_prem_tech_annual = 0  then rr_deductible_premannual / adjustment
			when coveragecode_id = 90009 and (isnull(rr_prem_tech_annual,0) <> 0 and isnull(adjustment,0) <> 0) and (rr_prem_tech_annual + adjustment) <> 0 then rr_deductible_premannual / (rr_prem_tech_annual + adjustment) 
			else 0 end as rr_deductible_factor --calculate the deductible factor
	,case 	when coveragecode_id = 90009 and rrr_prem_tech_annual <> 0 and adjustment = 0 then rrr_deductible_premannual / rrr_prem_tech_annual
			when coveragecode_id = 90009 and adjustment <> 0 and rrr_prem_tech_annual = 0  then rrr_deductible_premannual / adjustment
			when coveragecode_id = 90009 and (isnull(rrr_prem_tech_annual,0) <> 0 and isnull(adjustment,0) <> 0) and (rrr_prem_tech_annual + adjustment) <> 0 then rrr_deductible_premannual / (rrr_prem_tech_annual + adjustment) 
			else 0 end as rrr_deductible_factor --calculate the deductible factor
	,case 	when coveragecode_id = 90009 and zz_prem_tech_annual <> 0 and adjustment = 0 then zz_deductible_premannual / zz_prem_tech_annual
			when coveragecode_id = 90009 and adjustment <> 0 and zz_prem_tech_annual = 0  then zz_deductible_premannual / adjustment
			when coveragecode_id = 90009 and (isnull(zz_prem_tech_annual,0) <> 0 and isnull(adjustment,0) <> 0) and (zz_prem_tech_annual + adjustment) <> 0 then zz_deductible_premannual / (zz_prem_tech_annual + adjustment) 
			else 0 end as zz_deductible_factor --calculate the deductible factor
into #temp09
from #temp08


if OBJECT_ID('tempdb.dbo.#temp10') is not null drop table #temp10
select
	*
	,isnull(r_prem_tech_annual,0) * (1 - r_deductible_factor) as r_prem_tech_annual_ded --calculate the manual premium with deductible factor applied
	,adjustment * (1 - r_deductible_factor) as r_adjustment_ded --calculate the adjustment with deductible factor applied
	,isnull(rr_prem_tech_annual,0) * (1 - rr_deductible_factor) as rr_prem_tech_annual_ded --calculate the manual premium with deductible factor applied
	,adjustment * (1 - rr_deductible_factor) as rr_adjustment_ded --calculate the adjustment with deductible factor applied
	,isnull(rrr_prem_tech_annual,0) * (1 - rrr_deductible_factor) as rrr_prem_tech_annual_ded --calculate the manual premium with deductible factor applied
	,adjustment * (1 - rrr_deductible_factor) as rrr_adjustment_ded --calculate the adjustment with deductible factor applied
	,isnull(zz_prem_tech_annual,0) * (1 - zz_deductible_factor) as zz_prem_tech_annual_ded --calculate the manual premium with deductible factor applied
	,adjustment * (1 - zz_deductible_factor) as zz_adjustment_ded --calculate the adjustment with deductible factor applied
into #temp10
from #temp09

-----------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#temp11') is not null drop table #temp11
select
	id_trans
	,company_code as Company
	,[Company Code] as company_code
	,business_unit
	,reserving
	,'Aviation' as line
	,'Aircraft' as product
	,case when state_insd = 'NULL' then null 
			else state_insd
			end state_insd
	,state_risk
	,client_id
	,policy_id
	,lead(policy_id) over (partition by client_id order by client_id desc,policy_id desc ) PrevPolID
	,lead(pol_num_full_clean) over (partition by client_id order by client_id desc,pol_num_full_clean desc ) PrevPolNum
	,pol_num
	,policyimage_num
	,pol_ed as pol_edition
	,pol_num_full_clean
	,PolicyType
	,policytermversion_dscr
	,policy_city
	,policy_county
	,policy_state
	,policy_zip
	,unit_num
	,faano
	,aircraft_type_rating
	,gear_type_dscr
	,wing_type_dscr
	,model
	,model_code
	,airport_name
	,agency_id as agent_num
	,agencyproducer_id as producer_num
	,agency_name as agent_name
	,agencyproducer_name as producer_name
	,agency_city
	,agency_state
	,insd_name_hist
	,underwriter_name
	,ind_pri_xs
	,SpecialUse_Code
	,Primary_use_rating
--	,Primary_use_rating_True
	,coveragecode_id as covg
	,Coverage_group as covg_group_desc
	,covg_description as covg_desc
	,PD_Limit
	,limit_dscr
	,claim_limit_perperson
	,claim_limit_peroccur
	,claim_deductible
	,claim_limit_dscr
	,CSL_Occurance_Limit
	,CSL_Passenger_Limit
	,Med_Occurance_Limit
	,Med_Passenger_Limit
	,Med_Passenger_Limit_description
	,case when prem_chg_fullterm<0 then -1 else 1 end trans_mod
	,date_pol_eff
	,date_pol_exp
	,Calendar_Effective_Date as date_cal_eff
	,Calendar_Expiration_Date as date_cal_exp
	,date_book_val_max
	,Transaction_type
	,case when Calendar_Effective_Date = Calendar_Expiration_Date then cast(datediff(dd, date_pol_eff, date_pol_exp) as float)
			else cast(datediff(dd, Calendar_Effective_Date, Calendar_Expiration_Date) as float)
			end transaction_term
	,cast(datediff(dd, date_pol_eff, dateadd(yy, 1, date_pol_eff)) as float) term_year
	,cast(datediff(dd, date_pol_eff, date_pol_exp) as float) term
	,round(cast(datediff(dd, date_pol_eff, date_pol_exp) AS MONEY) / cast(datediff(dd, date_pol_eff, dateadd(yy, 1, date_pol_eff)) AS MONEY), 3) Term_years
	,datepart(yy,date_pol_eff)*100 + datepart(mm,date_pol_eff) mth_pol_eff
	,datepart(yy,date_pol_exp)*100 + datepart(mm,date_pol_exp) mth_pol_exp
	,datepart(yy,Calendar_Effective_Date)*100 + datepart(mm,Calendar_Effective_Date) mth_cal_eff
	,datepart(yy,Calendar_Expiration_Date)*100 + datepart(mm,Calendar_Expiration_Date) mth_cal_exp
	,datepart(yy,date_pol_eff)*10 + case when datepart(mm,date_pol_eff) in (1,2,3) then 1 when datepart(mm,date_pol_eff) in (4,5,6) then 2 when datepart(mm,date_pol_eff) in (7,8,9) then 3 else 4 end qtr_pol_eff
	,datepart(yy,date_pol_exp)*10 + case when datepart(mm,date_pol_exp) in (1,2,3) then 1 when datepart(mm,date_pol_exp) in (4,5,6) then 2 when datepart(mm,date_pol_exp) in (7,8,9) then 3 else 4 end qtr_pol_exp
	,datepart(yy,Calendar_Effective_Date)*10 + case when datepart(mm,Calendar_Effective_Date) in (1,2,3) then 1 when datepart(mm,Calendar_Effective_Date) in (4,5,6) then 2 when datepart(mm,Calendar_Effective_Date) in (7,8,9) then 3 else 4 end qtr_cal_eff
	,datepart(yy,Calendar_Expiration_Date)*10 + case when datepart(mm,Calendar_Expiration_Date) in (1,2,3) then 1 when datepart(mm,Calendar_Expiration_Date) in (4,5,6) then 2 when datepart(mm,Calendar_Expiration_Date) in (7,8,9) then 3 else 4 end qtr_cal_exp
	,datepart(yy,date_pol_eff) yr_pol
	,datepart(yy,Calendar_Effective_Date) yr_cal_eff
	,case when ([date_pol_eff] between '7/1/21' and '6/30/22') and company_code = 'Hallmark Insurance Company' then '2104'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company_code = 'Hallmark American Insurance Company' then '2104'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company_code = 'American Hallmark Insurance Co of TX' then '2105'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company_code = 'Pinnacle National Insurance Company' then '2106'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company_code = 'State National Insurance Company' then '2107'
	   
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company_code = 'Hallmark Insurance Company' then '2204'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company_code = 'Hallmark American Insurance Company' then '2204'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company_code = 'American Hallmark Insurance Co of TX' then '2205'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company_code = 'Pinnacle National Insurance Company' then '2206'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company_code = 'State National Insurance Company' then '2207'

	    when ([date_pol_eff] between '7/1/23' and '6/30/24') and company_code = 'Hallmark Insurance Company' then '2304'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company_code = 'Hallmark American Insurance Company' then '2304'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company_code = 'American Hallmark Insurance Co of TX' then '2305'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company_code = 'Pinnacle National Insurance Company' then '2306'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company_code = 'State National Insurance Company' then '2307'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company_code ='National Specialty Insurance Company' then '2308'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company_code ='HDI Global Select Insurance Company' then '2309'

	   	 when ([date_pol_eff] between '7/1/24' and '6/30/25') and company_code = 'Hallmark Insurance Company' then '2404'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company_code = 'Hallmark American Insurance Company' then '2404'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company_code = 'American Hallmark Insurance Co of TX' then '2405'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company_code = 'Pinnacle National Insurance Company' then '2406'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company_code = 'State National Insurance Company' then '2407'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company_code ='National Specialty Insurance Company' then '2408'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company_code ='HDI Global Select Insurance Company' then '2409'  
	   else 'Error' end as Treaty
	,date_cncl
	,aircraft_type_description
	,hull_value
	,min_age
	,max_age
	,Entity_Type as ENTITY_TYPE
	,Min_Total_Hours
	,Min_ME_Total
	,Min_FW_TJ
	,Min_FW_TP
	,Min_RG
	,Min_TW
	,Min_RW_Total
	,Min_RW_Turb
	,Min_RW_Pist
	,Min_SEA_AMPH
	,Min_Glider
	,Min_Last_12
	,Min_Last_90
	,Min_MM_Hours
	,[Min_Last_MM_Training Date]
	,Min_12_Month_Hours
	,Min_Last_90_Day_Hours
	,r_versionid
	,r_AircraftModelModifierHull
	,r_AircraftModelModifierLiab
	,r_SeatIndex
	,r_PrimaryPilotRating
	,r_airport_modifier
	,r_CMIndexHull
	,r_CMIndexLiability
	,r_CMIndexMedPay
	,r_StdDiscountHull
	,r_StdDiscountLiab
	,r_IsManual as r_ismanual
	,r_LiabilityOnlyModifier
	,r_MinimumPremium
	,r_PilotMinTotalHrsModifier
	,r_PilotMMHrsModifier
	,r_PilotMEHrsModifier
	,r_PilotAgeMinModifier
	,r_PilotAgeMaxModifier
	,r_HullModifier
	,r_Ground_Modifier
	,r_HullBaseRate
	,r_LiabBaseRate
	,r_LiabBaseAddtlSeat
	,r_MedPayBaseRate
	,r_PilotIFRModifier
	,r_PilotMinGearHrsModifier
	,r_coastal_factor
	,r_AircraftTypeModifier
	,r_BaseModelDeductible
	,r_BaseAgeDeductible
	,r_BaseTypeDeductible
	,r_max_base_deductible
	,rr_versionid
	,rr_AircraftModelModifierHull
	,rr_AircraftModelModifierLiab
	,rr_SeatIndex
	,rr_PrimaryPilotRating
	,rr_airport_modifier
	,rr_CMIndexHull
	,rr_CMIndexLiability
	,rr_CMIndexMedPay
	,rr_StdDiscountHull
	,rr_StdDiscountLiab
	,rr_IsManual as rr_ismanual
	,rr_LiabilityOnlyModifier
	,rr_MinimumPremium
	,rr_PilotMinTotalHrsModifier
	,rr_PilotMMHrsModifier
	,rr_PilotMEHrsModifier
	,rr_PilotAgeMinModifier
	,rr_PilotAgeMaxModifier
	,rr_HullModifier
	,rr_Ground_Modifier
	,rr_HullBaseRate
	,rr_LiabBaseRate
	,rr_LiabBaseAddtlSeat
	,rr_MedPayBaseRate
	,rr_PilotIFRModifier
	,rr_PilotMinGearHrsModifier
	,rr_coastal_factor
	,rr_AircraftTypeModifier
	,rr_BaseModelDeductible
	,rr_BaseAgeDeductible
	,rr_BaseTypeDeductible
	,rr_max_base_deductible
	,rrr_versionid
	,rrr_AircraftModelModifierHull
	,rrr_AircraftModelModifierLiab
	,rrr_SeatIndex
	,rrr_PrimaryPilotRating
	,rrr_airport_modifier
	,rrr_CMIndexHull
	,rrr_CMIndexLiability
	,rrr_CMIndexMedPay
	,rrr_StdDiscountHull
	,rrr_StdDiscountLiab
	,rrr_IsManual as rrr_ismanual
	,rrr_LiabilityOnlyModifier
	,rrr_MinimumPremium
	,rrr_PilotMinTotalHrsModifier
	,rrr_PilotMMHrsModifier
	,rrr_PilotMEHrsModifier
	,rrr_PilotAgeMinModifier
	,rrr_PilotAgeMaxModifier
	,rrr_HullModifier
	,rrr_Ground_Modifier
	,rrr_HullBaseRate
	,rrr_LiabBaseRate
	,rrr_LiabBaseAddtlSeat
	,rrr_MedPayBaseRate
	,rrr_PilotIFRModifier
	,rrr_PilotMinGearHrsModifier
	,rrr_coastal_factor
	,rrr_AircraftTypeModifier
	,rrr_BaseModelDeductible
	,rrr_BaseAgeDeductible
	,rrr_BaseTypeDeductible
	,rrr_max_base_deductible
	,zz_versionid
	,zz_AircraftModelModifierHull
	,zz_AircraftModelModifierLiab
	,zz_SeatIndex
	,zz_PrimaryPilotRating
	,zz_airport_modifier
	,zz_CMIndexHull
	,zz_CMIndexLiability
	,zz_CMIndexMedPay
	,zz_StdDiscountHull
	,zz_StdDiscountLiab
	,zz_IsManual as zz_ismanual
	,zz_LiabilityOnlyModifier
	,zz_MinimumPremium
	,zz_PilotMinTotalHrsModifier
	,zz_PilotMMHrsModifier
	,zz_PilotMEHrsModifier
	,zz_PilotAgeMinModifier
	,zz_PilotAgeMaxModifier
	,zz_HullModifier
	,zz_Ground_Modifier
	,zz_HullBaseRate
	,zz_LiabBaseRate
	,zz_LiabBaseAddtlSeat
	,zz_MedPayBaseRate
	,zz_PilotIFRModifier
	,zz_PilotMinGearHrsModifier
	,zz_coastal_factor
	,zz_AircraftTypeModifier
	,zz_BaseModelDeductible
	,zz_BaseAgeDeductible
	,zz_BaseTypeDeductible
	,zz_max_base_deductible
	,selected_deductible
	,r_deductible_premannual
	,rr_deductible_premannual
	,rrr_deductible_premannual
	,zz_deductible_premannual
	,r_deductible_factor
	,rr_deductible_factor
	,rrr_deductible_factor
	,zz_deductible_factor
	,adjustment_type
	,adjustment_factor
	,adjustment
	,premium_diff_chg_written_calc
	,premium_diff_chg_written as prem_written
	,prem_chg_fullterm as prem_fullterm
	,premium_fullterm as premt_fullterm
	--,prem_chg_written as prem_written
	,premium_written as premt_written
	,prem_annual
	,premium_chg_annual
	,round(isnull(r_prem_tech_annual,0),0) as r_premt_tech_annual --manual premium
	,round(isnull(rr_prem_tech_annual,0),0) as rr_premt_tech_annual --manual premium
	,round(isnull(rrr_prem_tech_annual,0),0) as rrr_premt_tech_annual --manual premium
	,round(isnull(zz_prem_tech_annual,0),0) as zz_premt_tech_annual --manual premium
	,r_prem_tech_annual_ded --manual premium with deductible factor
	,rr_prem_tech_annual_ded --manual premium with deductible factor
	,rrr_prem_tech_annual_ded --manual premium with deductible factor
	,zz_prem_tech_annual_ded --manual premium with deductible factor
	,r_adjustment_ded --adjustment with deductible factor
	,rr_adjustment_ded --adjustment with deductible factor
	,rrr_adjustment_ded --adjustment with deductible factor
	,zz_adjustment_ded --adjustment with deductible factor
	,r_MinimumPremium as r_prem_minimum_annual
	,isnull(comm_written,0) as comm_written
	,cncl_status
	,cancelled_policyimage_num
into #temp11
from #temp10

-------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#temp12') is not null drop table #temp12
select *
	,case when premt_fullterm =0 or term=0 then 0 when adjustment_type = 'Dollar' then ((premt_fullterm + r_deductible_premannual) / (term/term_year) - isnull(adjustment_factor,0) ) else  ((premt_fullterm + r_deductible_premannual) / (term/term_year ) / (1 + isnull(adjustment_factor,0) )) end premt_tech_annual
	,iif(term=0,0,case when prem_fullterm = 0 then premt_fullterm/(term/term_year) else prem_fullterm/(term/term_year) end) premt_annual
	,case when r_premt_tech_annual <> 0 then 0
			when r_premt_tech_annual = 0 and r_HullBaseRate is null and covg = '90009' then 2
			when r_premt_tech_annual = 0 and r_HullBaseRate = 0 and covg = '90009' then 1
			when r_premt_tech_annual = 0 and r_LiabBaseRate is null and covg = '90064' then 2
			when r_premt_tech_annual = 0 and r_LiabBaseRate = 0 and covg = '90064' then 1
			when r_premt_tech_annual = 0 and r_MedPayBaseRate is null and covg = '90066' then 2
			when r_premt_tech_annual = 0 and r_MedPayBaseRate = 0 and covg = '90066' then 1
			end zero_tech	
into #temp12
FROM #temp11


update #temp12
set r_ismanual =  case when zero_tech<> 0 then 1 else 0 end
update #temp12
set rr_ismanual =  case when zero_tech<> 0 then 1 else 0 end
update #temp12
set rrr_ismanual =  case when zero_tech<> 0 then 1 else 0 end
update #temp12
set zz_ismanual =  case when zero_tech<> 0 then 1 else 0 end


if OBJECT_ID('tempdb.dbo.#temp13') is not null drop table #temp13
select 
	*
	,case when covg in (90006,90165) then prem_annual else (isnull(r_prem_tech_annual_ded,0) + r_adjustment_ded) * trans_mod end as r_premt_annual --calculate final premium
	,case when covg in (90006,90165) then prem_annual else (isnull(rr_prem_tech_annual_ded,0) + rr_adjustment_ded) * trans_mod end as rr_premt_annual --calculate final premium
	,case when covg in (90006,90165) then prem_annual else (isnull(rrr_prem_tech_annual_ded,0) + rrr_adjustment_ded) * trans_mod end as rrr_premt_annual --calculate final premium
	,case when covg in (90006,90165) then prem_annual else (isnull(zz_prem_tech_annual_ded,0) + zz_adjustment_ded) * trans_mod end as zz_premt_annual --calculate final premium
into #temp13
from #temp12

update #temp13 
set prem_annual = case when prem_written=0 then 0 else prem_annual end

-- FLAG_R DEFINITION
-- first two digits
-- 00	-- unratable/uninteresting, due to coverage (TRIA, add'l insd, waiver subro, assessments) 
-- 01	-- unratable - HXS flagged as "Rated" = 0
-- 02	-- unratable - missing rater/rating parameter
-- 11	-- correctly rates up, nothing special
-- 12	-- correctly rates up, (a) rated
-- 21	-- does not correctly rate, nothing special
-- 22	-- does not correctly rate, (a) rated
-- 23	-- does not correctly rate in total - unmod manual is correct, loss rating is not
-- third/fourth digits (for rr, rrr)
-- 0	-- can't due to missing data
-- 1	-- can, correct
-- 2	-- can, not correct


if OBJECT_ID('tempdb.dbo.#temp14') is not null drop table #temp14
select * 
	,prem_written as r_prem_written
	,premium_chg_annual as r_prem_annual
	,case when covg not in (90009,90064,90066) then 0000 
			when premt_annual = 0 or premt_annual is null then 0000
			when premt_annual is not null and premt_annual <> 0 and abs(abs(r_premt_annual/premt_annual) - 1)<=.005 then 1111
			else 2122
			end flag_r_trans
into #temp14
from #temp13

drop table dbo.test_FlagRTransPol
select  * into dbo.test_FlagRTransPol  from #temp14 
--select distinct aircraft_type_rating, aircraft_type_description from dbo.test_FlagRTransPol
--order by aircraft_type_rating
--
--select top 100 * from dbo.test_FlagRTransPol where mth_pol_eff = 202402 and flag_r_trans = 2122 and client_id = 48113206
--
update #temp14
set r_premt_annual = round(r_premt_annual, 0)
update #temp14
set rr_premt_annual = round(rr_premt_annual, 0)
update #temp14
set rrr_premt_annual = round(rrr_premt_annual, 0)
update #temp14
set zz_premt_annual = round(zz_premt_annual, 0)

---------------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#temp15') is not null drop table #temp15
select
	*
	,case when zero_tech = 0 and premt_tech_annual <> 0 and prem_annual <> 0 then prem_annual / (premt_tech_annual)
			when zero_tech <> 0 or premt_tech_annual = 0 or prem_annual = 0 then 1
			end STT --STT is null when zero_tech is null
	,case when zero_tech = 0 and r_premt_tech_annual <> 0 and prem_annual <> 0 then prem_annual /  (r_premt_tech_annual)
			when zero_tech <> 0 or r_premt_tech_annual = 0 or prem_annual = 0 then 1
			end r_STT
	,case when zero_tech = 0 and rr_premt_tech_annual <> 0 and prem_annual <> 0 then prem_annual / (rr_premt_tech_annual)
			when zero_tech <> 0 or rr_premt_tech_annual = 0 or prem_annual = 0 then 1
			end rr_STT
	,case when zero_tech = 0 and rrr_premt_tech_annual <> 0 and prem_annual <> 0 then prem_annual / (rrr_premt_tech_annual)
			when zero_tech <> 0 or rrr_premt_tech_annual = 0 or prem_annual = 0 then 1
			end rrr_STT
	,case when zero_tech = 0 and zz_premt_tech_annual <> 0 and prem_annual <> 0 then prem_annual / (zz_premt_tech_annual)
			when zero_tech <> 0 or zz_premt_tech_annual = 0 or prem_annual = 0 then 1
			end zz_STT
into #temp15
from #temp14


--delete from #temp15
--where prem_fullterm = 0 and premt_fullterm = 0

-----------------------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#temp16') is not null drop table #temp16
select
	*
	,prem_written / isnull(STT,1) as premium_tech_written
	,prem_written / r_STT as r_premium_tech_written
	,prem_written / rr_STT as rr_premium_tech_written
	,prem_written / rrr_STT as rrr_premium_tech_written
	,prem_written / zz_STT as zz_premium_tech_written
	,premium_chg_annual / isnull(STT,1) prem_tech_annual
	,premium_chg_annual / r_STT r_prem_tech_annual
	,premium_chg_annual / rr_STT rr_prem_tech_annual
	,premium_chg_annual / rrr_STT rrr_prem_tech_annual
	,premium_chg_annual / zz_STT zz_prem_tech_annual

into #temp16
from #temp15




-----------------------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#temp17') is not null drop table #temp17
select
	*
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_written
			else 0
			end r_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_written
			else 0
			end rr_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_written
			else 0
			end rrr_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_written
			else 0
			end zz_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then premium_chg_annual
			else 0
			end r_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then premium_chg_annual
			else 0
			end rr_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then premium_chg_annual
			else 0
			end rrr_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then premium_chg_annual
			else 0
			end zz_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_premium_tech_written
			else 0
			end r_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_premium_tech_written
			else 0
			end rr_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_premium_tech_written
			else 0
			end rrr_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_premium_tech_written
			else 0
			end zz_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_annual
			else 0
			end r_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_annual
			else 0
			end rr_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_annual
			else 0
			end rrr_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_annual
			else 0
			end zz_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_premium_tech_written * 0.65 else 0 end as r_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_premium_tech_written * 0.65 else 0 end as rr_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_premium_tech_written * 0.65 else 0 end as rrr_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_premium_tech_written * 0.65 else 0 end as zz_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_annual * 0.65 else 0 end as r_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_annual * 0.65 else 0 end as rr_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_annual * 0.65 else 0 end as rrr_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_annual * 0.65 else 0 end as zz_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_premium_tech_written * 0.65 else 0 end as r_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_premium_tech_written * 0.65 else 0 end as rr_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_premium_tech_written * 0.65 else 0 end as rrr_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_premium_tech_written * 0.65 else 0 end as zz_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_annual * 0.65 else 0 end as r_blpadq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_annual * 0.65 else 0 end as rr_blpadq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_annual * 0.65 else 0 end as rrr_blpadq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_annual * 0.65 else 0 end as zz_blpadq_tech_annual
into #temp17
from #temp16




update #temp17
set
	prem_tech_annual = ROUND(prem_tech_annual,0)
	,prem_written = ROUND(prem_written,0)
	,prem_annual = ROUND(prem_annual,0)
	,r_premium_tech_written = ROUND(r_premium_tech_written,0)
	,rr_premium_tech_written = ROUND(rr_premium_tech_written,0)
	,rrr_premium_tech_written = ROUND(rrr_premium_tech_written,0)
	,zz_premium_tech_written = ROUND(zz_premium_tech_written,0)
	,r_prem_written = ROUND(r_prem_written,0)
	,r_prem_tech_annual = ROUND(r_prem_tech_annual,0) 
	,rr_prem_tech_annual = ROUND(rr_prem_tech_annual,0) 
	,rrr_prem_tech_annual = ROUND(rrr_prem_tech_annual,0) 
	,zz_prem_tech_annual = ROUND(zz_prem_tech_annual,0)
	,r_adq_written = ROUND(r_adq_written,0)
	,rr_adq_written = ROUND(rr_adq_written,0)
	,rrr_adq_written = ROUND(rrr_adq_written,0)
	,zz_adq_written = ROUND(zz_adq_written,0)
	,r_adq_annual = ROUND(r_adq_annual,0)
	,rr_adq_annual = ROUND(rr_adq_annual,0)
	,rrr_adq_annual = ROUND(rrr_adq_annual,0)
	,zz_adq_annual = ROUND(zz_adq_annual,0)
	,r_adq_tech_written = ROUND(r_adq_tech_written,0)
	,rr_adq_tech_written = ROUND(rr_adq_tech_written,0)
	,rrr_adq_tech_written = ROUND(rrr_adq_tech_written,0)
	,zz_adq_tech_written = ROUND(zz_adq_tech_written,0)
	,r_adq_tech_annual = ROUND(r_adq_tech_annual,0) 
	,rr_adq_tech_annual = ROUND(rr_adq_tech_annual,0) 
	,rrr_adq_tech_annual = ROUND(rrr_adq_tech_annual,0) 
	,zz_adq_tech_annual = ROUND(zz_adq_tech_annual,0) 
	,r_padq_tech_written = ROUND(r_padq_tech_written,0)
	,rr_padq_tech_written = ROUND(rr_padq_tech_written,0)
	,rrr_padq_tech_written = ROUND(rrr_padq_tech_written,0)
	,zz_padq_tech_written = ROUND(zz_padq_tech_written,0)	
	,r_padq_tech_annual = ROUND(r_padq_tech_annual,0) 
	,rr_padq_tech_annual = ROUND(rr_padq_tech_annual,0) 
	,rrr_padq_tech_annual = ROUND(rrr_padq_tech_annual,0) 
	,zz_padq_tech_annual = ROUND(zz_padq_tech_annual,0) 
	,r_blpadq_tech_written = ROUND(r_blpadq_tech_written,0)
	,rr_blpadq_tech_written = ROUND(rr_blpadq_tech_written,0)
	,rrr_blpadq_tech_written = ROUND(rrr_blpadq_tech_written,0)
	,zz_blpadq_tech_written = ROUND(zz_blpadq_tech_written,0)
	,r_blpadq_tech_annual = ROUND(r_blpadq_tech_annual,0)
	,rr_blpadq_tech_annual = ROUND(rr_blpadq_tech_annual,0) 
	,rrr_blpadq_tech_annual = ROUND(rrr_blpadq_tech_annual,0) 
	,zz_blpadq_tech_annual = ROUND(zz_blpadq_tech_annual,0) 

	---------go back here


-----------------------------------------------------------------------------------------------------------------------------------------------------------------
if OBJECT_ID('dbo.test_aim_diamond_STT') is not null drop table dbo.test_aim_diamond_STT
--
select * into dbo.test_aim_diamond_STT from #temp17

    ALTER TABLE dbo.test_aim_diamond_STT ADD
        row_hash     BINARY(32)   NULL,
        created_date DATETIME2(0) NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0) NOT NULL DEFAULT GETDATE();

    UPDATE dbo.test_aim_diamond_STT
    SET row_hash = CONVERT(BINARY(32), HASHBYTES('SHA2_256',
        ISNULL(CAST(prem_written               AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(prem_annual                AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(r_premium_tech_written     AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(rr_premium_tech_written    AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(rrr_premium_tech_written   AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(zz_premium_tech_written    AS NVARCHAR(30)), '')));

-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
--Apollo Part
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#reserving') is not null drop table #reserving
Create table #reserving(
	reserving varchar(25)
);

Insert into #reserving(reserving)
values('ACH')
Insert into #reserving(reserving)
values('ACL')

-----------------------------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#term01') is not null drop table #term01

SELECT a.[ID]
      ,a.[WritingCo]
      ,a.[Policyno]
      ,a.[PolCov]
      ,a.[Endorsement]
      ,a.[EffDate]
      ,a.[endorse beg]
      ,a.[endorse end]
      ,a.[endorseType]
      ,a.[BillDate]
      ,a.[PdToDate]
      ,a.[TermDate]
	  ,datediff(DD, a.EffDate, a.PdToDate) as Term
	  ,datediff(DD, isnull(a.[endorse beg],a.EffDate), isnull(a.[endorse end],a.PdToDate)) as Transaction_term
      ,a.[FAAno]
	  ,r.reserving
      ,a.[City]
      ,a.[IssueState]
      ,a.[AgreedValue]
	  , SUM(a.[7F]+a.[7G]) AS ACH_WP
	  , sum(a.[7C]+a.[7D]+a.[7DL]+a.[7E]) as Liab_WP
	  , sum(a.[7C]+a.[7D]+a.[7DL]+a.[7E]+a.[7F]+a.[7G]) as TOT_WP
	  , SUM(a.[7F]+a.[7G]) * a.CommRate as Commission_ACH
	  , sum(a.[7C]+a.[7D]+a.[7DL]+a.[7E]) * a.CommRate as Commission_ACL
      ,a.[7Tax]
      ,a.[Reversal]
      ,a.[MakeModel]
      ,a.[PolicyType]
      ,a.[AgentNum]
      ,a.[CommRate]
      ,a.[Treaty]
      ,a.[Rewrite]
      ,a.[Claim]
      ,a.[posted]
      ,a.[wing]
into #term01
FROM [Pricing_aim].[dbo].[PolTblNew] a
left join #reserving as r on a.FAAno is not null
where [EffDate] >= '2011-01-01'  --and EffDate > '2023-05-31' --'2021-01-01'  
group by 
		a.[ID]
      ,a.[WritingCo]
      ,a.[Policyno]
      ,a.[PolCov]
      ,a.[Endorsement]
      ,a.[EffDate]
      ,a.[endorse beg]
      ,a.[endorse end]
      ,a.[endorseType]
      ,a.[BillDate]
      ,a.[PdToDate]
      ,a.[TermDate]
      ,a.[FAAno]
      ,a.[City]
      ,a.[IssueState]
      ,a.[AgreedValue]
	  ,a.[7Tax]
      ,a.[Reversal]
      ,a.[MakeModel]
      ,a.[PolicyType]
      ,a.[AgentNum]
      ,a.[CommRate]
      ,a.[Treaty]
      ,a.[Rewrite]
      ,a.[Claim]
      ,a.[posted]
      ,a.[wing]
	  ,r.reserving

delete from #term01 
where ACH_WP = 0 and reserving = 'ACH'

delete from #term01 
where Liab_WP = 0 and reserving = 'ACL'

----------------------------------------------------------------------------------

--check dupes
if OBJECT_ID('tempdb.dbo.#term02') is not null drop table #term02

select  
 t.ID as trans_id
, t.[WritingCo]
, t.[Policyno]
, t.[PolCov]
, t.[Endorsement]
, t.[EffDate]
, t.[endorse beg]
, t.[endorse end]
, t.[endorseType]
, t.[BillDate]
, t.[PdToDate]
, t.[TermDate]
, t.Term
, t.Transaction_term
, t.[FAAno]
, case when cast(t.Term as float) <> 0 then cast(t.Transaction_term as float)/cast(t.Term as float) else 0 end as factor 
, t.reserving
, t.[City]
, t.[IssueState]
, t.[AgreedValue]
, case when t.reserving = 'ACL' then Liab_WP
		when t.reserving = 'ACH' then ACH_WP
		end Premium_written
, case when t.reserving = 'ACH' then t.Commission_ACH
		when t.reserving = 'ACL' then t.Commission_ACL
		end Commission
, t.[7Tax]
, t.[Reversal]
, t.[MakeModel]
, t.[PolicyType]
, t.[AgentNum]
, t.[Treaty]
, t.[Rewrite]
, t.[Claim]
, t.[posted]
, t.[wing]
, tp.polid
, tp.statid
, tp.entityid
, tp.prodid
, tp.priorityid
, tp.policyno as [Policy No]
, tp.efdate
, tp.exdate
, tp.primaryuseid
, tp.ppolid
, tpp.policyNo ppolicyno
, tp.primaryriskstate 
into #term02
FROM #term01 t 
left join [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS TP on t.Policyno = tp.policyno
left join [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS TPP on t.Policyno = case when len(tpp.policyno) >7 then concat(left(tpp.policyno,11),right('00' +cast(right(tpp.policyno,2)-1 as varchar(2)),2)) else null end



----------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#apollo01') IS NOT NULL	DROP TABLE #apollo01
select 
a.policyno + cast(a.statid as varchar(5)) + cast(isnull(a.faano,'APL') as varchar(25)) + cast(datepart(mm,a.efdate) as varchar(2)) + '-' + cast(datepart(dd,a.efdate) as varchar(2)) + '-' + cast(datepart(YY,a.efdate) as varchar(4)) + cast(isnull(a.aircrafttype,1) as varchar(25)) [Lookup]
,a.polid
,a.policyno
,cast(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(policyno ,'-',''),'a',1),'b',2),'c',3),'d',4),'e',5),'f',6),'g',7),'h',8),'i',9),'j',10),'k',11),'l',12),'m',13),'n',14),'o',15),'p',16),'q',17),'r',18),'s',19),'t',20),'u',21),'v',22),'w',23),'x',24),'y',25),'z',26) as float) pol_num_full_clean
--,cast(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(a.ppolicyno ,'-',''),'a',1),'b',2),'c',3),'d',4),'e',5),'f',6),'g',7),'h',8),'i',9),'j',10),'k',11),'l',12),'m',13),'n',14),'o',15),'p',16),'q',17),'r',18),'s',19),'t',20),'u',21),'v',22),'w',23),'x',24),'y',25),'z',26) as float) PreviousPolNumFullClean
,a.statid
,a.faano
,a.coverage as Coverage_group
,case when a.coverage = 'GRO-Flight' then 'Ground & Flight'
	when a.coverage = 'GRO-NIM' then 'Ground - Not In Motion'
	when a.coverage = 'GRO-Taxi' then 'Ground & Taxi (excluding In Flight)'
	end as limit_dscr
,a.agency_city
,a.agency_name
,a.agency_num
,a.agency_state
,a.airplane_airport
,a.airplane_county
,a.airplane_zip
,a.modelid
,a.Manufacturer as make_dscr
,a.Model as Model_Code
,CONCAT(a.Model,' ',a.ModelName) as model
,a.policy_airport
,a.policy_city
,a.policy_county
--,a.locstate as state_risk
,a.policy_state as state_risk
,a.policy_zip
,a.AssignedUnderwriter
,a.aircrafttype as aircraft_type_rating
,a.geartype as gear_type_rating
,a.liaboccurlimit as CSL_Occurance_Limit
,a.passengerlimittext as CSL_Passenger_Limit
,a.medpaylimit as Med_Passenger_Limit_description
,case when a.hullvalue = 0 then 'Null' else 'Has Hull' end PD_Limit_description
,a.NoOfSeats as seating_capacity_dscr
,a.hullvalue as hull_value
,a.hullage as model_age
,a.pilotmaxage as max_age
,a.pilotminage as min_age
,a.pilotminmmhrs as Min_MM_Hours
,a.pilotmintwhrs as Min_TW
,a.pilotminrghrs as Min_RG
,a.pilotminrwhrs as Min_RW_Total
,a.pilotminmehrs as Min_ME_Total
,a.pilotmingearhrs as Gearhour
,a.pilotminIFR
,a.pilotmintotalhrs as Min_Total_Hours
,a.ismanual
,a.efdate as eff_date
,a.exdate
,a.Conforming
,b.aircraft_type_dscr as aircraft_type_description
,a.carrier as company_code
,a.Insured as insd_name_hist
,a.insd_state as state_insd
,a.date_book_val_max
,case when a.geartype = 'T' THEN 'Tricycle'
		when a.geartype = 'C' then 'Tailwheel'
		when a.geartype = 'F' then 'Floats'
		when a.geartype = 'R' then 'Retractable'
		when a.geartype = 'S' then 'Skids-RW'
		when a.geartype = 'CR' then 'Retract Tailwheel'
		when a.geartype = 'A' then 'Amphibious'
		end gear_type_dscr
,a.flag_r as flag_r_trans
,a.r_AircraftModelModifierHull
,a.r_AircraftModelModifierLiab
,a.r_CMIndexHull
,a.r_CMIndexLiab
,a.r_CMIndexMedPay
,a.r_StdDiscountHull
,a.r_StdDiscountLiab
,a.r_LiabOnly
,a.r_PilotMinTotalHrs
,a.r_PilotAgeMin
,a.r_PilotAgeMax
,a.r_MMHrs
,a.r_MEHrs
,max(a.r_GearHrs) as r_GearHrs
,a.r_HullMod
,a.r_GroundOnly
,a.r_IFR
,a.r_HullBase
,a.r_MedPayBase
,a.r_LiabBase
,a.r_LiabBase_addtlseat
,a.r_PilotAge
,a.r_LocModifier
,max(a.r_PilotOtherModifier) as r_PilotOtherModifier
,a.r_LocAirportModifier
,a.r_MinPrem
,a.rr_AircraftModelModifierHull
,a.rr_AircraftModelModifierLiab
,a.rr_CMIndexHull
,a.rr_CMIndexLiab
,a.rr_CMIndexMedPay
,a.rr_StdDiscountHull
,a.rr_StdDiscountLiab
,a.rr_LiabOnly
,a.rr_PilotMinTotalHrs
,a.rr_PilotAgeMin
,a.rr_PilotAgeMax
,a.rr_MMHrs
,a.rr_MEHrs
,max(a.rr_GearHrs) as rr_GearHrs
,a.rr_HullMod
,a.rr_GroundOnly
,a.rr_IFR
,a.rr_HullBase
,a.rr_MedPayBase
,a.rr_LiabBase
,a.rr_LiabBase_addtlseat
,a.rr_PilotAge
,a.rr_LocModifier
,max(a.rr_PilotOtherModifier) as rr_PilotOtherModifier
,a.rr_LocAirportModifier
,a.rr_MinPrem
,a.rrr_AircraftModelModifierHull
,a.rrr_AircraftModelModifierLiab
,a.rrr_CMIndexHull
,a.rrr_CMIndexLiab
,a.rrr_CMIndexMedPay
,a.rrr_StdDiscountHull
,a.rrr_StdDiscountLiab
,a.rrr_LiabOnly
,a.rrr_PilotMinTotalHrs
,a.rrr_PilotAgeMin
,a.rrr_PilotAgeMax
,a.rrr_MMHrs
,a.rrr_MEHrs
,max(a.rrr_GearHrs) as rrr_GearHrs
,a.rrr_HullMod
,a.rrr_GroundOnly
,a.rrr_IFR
,a.rrr_HullBase
,a.rrr_MedPayBase
,a.rrr_LiabBase
,a.rrr_LiabBase_addtlseat
,a.rrr_PilotAge
,a.rrr_LocModifier
,max(a.rrr_PilotOtherModifier) as rrr_PilotOtherModifier
,a.rrr_LocAirportModifier
,a.rrr_MinPrem
,a.zz_AircraftModelModifierHull
,a.zz_AircraftModelModifierLiab
,a.zz_CMIndexHull
,a.zz_CMIndexLiab
,a.zz_CMIndexMedPay
,a.zz_StdDiscountHull
,a.zz_StdDiscountLiab
,a.zz_LiabOnly
,a.zz_PilotMinTotalHrs
,a.zz_PilotAgeMin
,a.zz_PilotAgeMax
,a.zz_MMHrs
,a.zz_MEHrs
,max(a.zz_GearHrs) as zz_GearHrs
,a.zz_HullMod
,a.zz_GroundOnly
,a.zz_IFR
,a.zz_HullBase
,a.zz_MedPayBase
,a.zz_LiabBase
,a.zz_LiabBase_addtlseat
,a.zz_PilotAge
,a.zz_LocModifier
,max(a.zz_PilotOtherModifier) as zz_PilotOtherModifier
,a.zz_LocAirportModifier
,a.zz_MinPrem
into #apollo01
from [Pricing_AIM].[dbo].[aim_r_ac_final_2] a
left join [Pricing_AIM].[dbo].[AircraftType] b on a.aircrafttype = b.AircraftID
where a.efdate >= '2011-01-01' --'2021-01-01' 
group by
a.polid
,a.policyno
--,a.ppolicyno
,a.statid
,a.faano
,a.coverage
,a.agency_city
,a.agency_name
,a.agency_num
,a.agency_state
,a.airplane_airport
,a.airplane_county
,a.airplane_zip
,a.modelid
,a.Manufacturer
,a.Model
,a.ModelName
,a.policy_airport
,a.policy_city
,a.policy_county
--,a.locstate
,a.policy_state
,a.policy_zip
,a.AssignedUnderwriter
,a.aircrafttype 
,a.geartype 
,a.liaboccurlimit 
,a.passengerlimittext 
,a.medpaylimit
,a.NoOfSeats
,a.hullvalue
,a.hullage
,a.pilotmaxage 
,a.pilotminage 
,a.pilotminmmhrs 
,a.pilotmintwhrs 
,a.pilotminrghrs 
,a.pilotminrwhrs 
,a.pilotminmehrs 
,a.pilotmingearhrs 
,a.pilotminIFR
,a.pilotmintotalhrs 
,a.ismanual
,a.efdate 
,a.exdate
,a.Conforming
,b.aircraft_type_dscr
,a.carrier
,a.Insured 
,a.insd_state 
,a.date_book_val_max
,a.flag_r
,a.r_AircraftModelModifierHull
,a.r_AircraftModelModifierLiab
,a.r_CMIndexHull
,a.r_CMIndexLiab
,a.r_CMIndexMedPay
,a.r_StdDiscountHull
,a.r_StdDiscountLiab
,a.r_LiabOnly
,a.r_PilotMinTotalHrs
,a.r_PilotAgeMin
,a.r_PilotAgeMax
,a.r_MMHrs
,a.r_MEHrs
,a.r_HullMod
,a.r_GroundOnly
,a.r_IFR
,a.r_HullBase
,a.r_MedPayBase
,a.r_LiabBase
,a.r_LiabBase_addtlseat
,a.r_PilotAge
,a.r_LocModifier
,a.r_LocAirportModifier
,a.r_MinPrem
,a.rr_AircraftModelModifierHull
,a.rr_AircraftModelModifierLiab
,a.rr_CMIndexHull
,a.rr_CMIndexLiab
,a.rr_CMIndexMedPay
,a.rr_StdDiscountHull
,a.rr_StdDiscountLiab
,a.rr_LiabOnly
,a.rr_PilotMinTotalHrs
,a.rr_PilotAgeMin
,a.rr_PilotAgeMax
,a.rr_MMHrs
,a.rr_MEHrs
,a.rr_HullMod
,a.rr_GroundOnly
,a.rr_IFR
,a.rr_HullBase
,a.rr_MedPayBase
,a.rr_LiabBase
,a.rr_LiabBase_addtlseat
,a.rr_PilotAge
,a.rr_LocModifier
,a.rr_LocAirportModifier
,a.rr_MinPrem
,a.rrr_AircraftModelModifierHull
,a.rrr_AircraftModelModifierLiab
,a.rrr_CMIndexHull
,a.rrr_CMIndexLiab
,a.rrr_CMIndexMedPay
,a.rrr_StdDiscountHull
,a.rrr_StdDiscountLiab
,a.rrr_LiabOnly
,a.rrr_PilotMinTotalHrs
,a.rrr_PilotAgeMin
,a.rrr_PilotAgeMax
,a.rrr_MMHrs
,a.rrr_MEHrs
,a.rrr_HullMod
,a.rrr_GroundOnly
,a.rrr_IFR
,a.rrr_HullBase
,a.rrr_MedPayBase
,a.rrr_LiabBase
,a.rrr_LiabBase_addtlseat
,a.rrr_PilotAge
,a.rrr_LocModifier
,a.rrr_LocAirportModifier
,a.rrr_MinPrem
,a.zz_AircraftModelModifierHull
,a.zz_AircraftModelModifierLiab
,a.zz_CMIndexHull
,a.zz_CMIndexLiab
,a.zz_CMIndexMedPay
,a.zz_StdDiscountHull
,a.zz_StdDiscountLiab
,a.zz_LiabOnly
,a.zz_PilotMinTotalHrs
,a.zz_PilotAgeMin
,a.zz_PilotAgeMax
,a.zz_MMHrs
,a.zz_MEHrs
,a.zz_HullMod
,a.zz_GroundOnly
,a.zz_IFR
,a.zz_HullBase
,a.zz_MedPayBase
,a.zz_LiabBase
,a.zz_LiabBase_addtlseat
,a.zz_PilotAge
,a.zz_LocModifier
,a.zz_LocAirportModifier
,a.zz_MinPrem

--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#apollo01a') IS NOT NULL	DROP TABLE #apollo01a

select
	ROW_NUMBER () over (partition by Lookup order by Lookup) as row_number
	,*
into #apollo01a
from #apollo01

delete from #apollo01a
where row_number <> 1

----------------------------------------------------------------------------------
--need to create a new table for policy lvl info so faano is not used to join the tables
IF OBJECT_ID('tempdb..#policylvl') IS NOT NULL	DROP TABLE #policylvl
select
	--Lookup
	polid
	,Policyno
	,pol_num_full_clean
	--,statid
	,agency_city
	,agency_name
	,agency_num
	,agency_state
	,policy_airport as airplane_airport
	,policy_county as airplane_county
	,policy_zip as airplane_zip
	,policy_airport
	,policy_city
	,policy_county
	,state_risk
	,policy_zip
	,AssignedUnderwriter
	,company_code
	,insd_name_hist
	,state_insd
	,date_book_val_max
into #policylvl
from #apollo01a
group by
	polid
	,Policyno
	,pol_num_full_clean
	--,statid
	,agency_city
	,agency_name
	,agency_num
	,agency_state
	--,airplane_airport
	--,airplane_county
	--,airplane_zip
	,policy_airport
	,policy_city
	,policy_county
	,state_risk
	,policy_zip
	,AssignedUnderwriter
	,company_code
	,insd_name_hist
	,state_insd
	,date_book_val_max



IF OBJECT_ID('tempdb..#apollo02') IS NOT NULL	DROP TABLE #apollo02
select
	a.Lookup
	,t.trans_id
	,t.WritingCo
	,t.polid
	,t.ppolid
	,t.Policyno
	,cast(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(t.ppolicyno ,'-',''),'a',1),'b',2),'c',3),'d',4),'e',5),'f',6),'g',7),'h',8),'i',9),'j',10),'k',11),'l',12),'m',13),'n',14),'o',15),'p',16),'q',17),'r',18),'s',19),'t',20),'u',21),'v',22),'w',23),'x',24),'y',25),'z',26) as float) PreviousPolNumFullClean
	,RIGHT(t.policyno,2) as pol_ed
	,c.pol_num_full_clean
	,a.statid
	,t.Endorsement
	,t.FAAno
	,a.modelid
	,a.make_dscr
	,a.Model_Code
	,a.model
	,t.reserving
	,a.Coverage_group
	,case when t.reserving = 'ACH' then 90009
			when t.reserving = 'ACL' then 90064
			end coveragecode_id
	,case when t.reserving = 'ACH' then 'Physical Damage Total'
			when t.reserving = 'ACL' then 'Liability'
			end coveragecode_desc
	,a.limit_dscr
	,c.agency_city
	,c.agency_name
	,c.agency_num
	,c.agency_state
	,case when t.primaryuseid = 1 then 'Pleasure & Business'
		when t.primaryuseid = 2 then 'Airport GL'
		when t.primaryuseid = 3 then 'Special Use'
		when t.primaryuseid = 4 then 'Instruction & Rental'
		when t.primaryuseid = 5 then 'Charter / Air Taxi'
		else 'Pleasure & Business'
		end aircraftuse_dscr
	,c.airplane_airport
	,t.City as airplane_city
	,c.airplane_county
	,t.IssueState as airplane_state
	,c.airplane_zip
	,c.policy_airport
	,c.policy_city
	,c.policy_county
	,c.state_risk
	,c.policy_zip
	,c.AssignedUnderwriter
	,'None' as ENTITY_TYPE
	,'Endorsement' as Transaction_Type
	--,a.Yr
	,a.aircraft_type_rating
	,a.aircraft_type_description as AircraftTypeName
	,cast(a.aircraft_type_rating AS VARCHAR(2)) + a.aircraft_type_description AircraftTypeNameDisplay
	,a.gear_type_rating as gear
	,t.AgreedValue as HullValue_AgreedValue
	,t.Premium_written as prem_written
	,case when t.factor = 0 then 0 else t.Premium_written / t.factor end as prem_annual
	,t.Commission
	,t.Term
	,t.Transaction_term
	,t.factor
	,t.[7Tax] as Tax
	,t.MakeModel
	,t.PolicyType
	,t.AgentNum
	,t.Treaty
	,t.wing
	,t.efdate
	,t.exdate
	,'2022-04-29 00:00:00.000' as Calendar_Effective_Date
	,'2022-04-29 00:00:00.000' as Calendar_Expiration_Date
	,t.primaryuseid primaryuseid 
--	,t.primaryuseid primaryuseid_true
	,t.primaryriskstate
	,a.CSL_Occurance_Limit
	,a.CSL_Passenger_Limit
	,a.Med_Passenger_Limit_description
	,a.PD_Limit_description
	,a.seating_capacity_dscr
	,a.hull_value
	,a.model_age
	,a.max_age
	,a.min_age
	,a.Min_MM_Hours
	,a.Min_TW
	,a.Min_RG
	,a.Min_RW_Total
	,a.Min_ME_Total
	,a.Gearhour
	,a.pilotminIFR
	,a.Min_Total_Hours
	,a.ismanual
	,a.Conforming
	,a.aircraft_type_description
	,c.company_code
	,c.insd_name_hist
	,c.state_insd
	,c.date_book_val_max
	,a.gear_type_dscr
	,a.flag_r_trans
	,a.r_AircraftModelModifierHull
	,a.r_AircraftModelModifierLiab
	,a.r_CMIndexHull
	,a.r_CMIndexLiab
	,a.r_CMIndexMedPay
	,a.r_StdDiscountHull
	,a.r_StdDiscountLiab
	,a.r_LiabOnly
	,a.r_PilotMinTotalHrs
	,a.r_PilotAgeMin
	,a.r_PilotAgeMax
	,a.r_MMHrs
	,a.r_MEHrs
	,a.r_GearHrs
	,a.r_HullMod
	,a.r_GroundOnly
	,a.r_IFR
	,a.r_HullBase
	,a.r_MedPayBase
	,a.r_LiabBase
	,a.r_LiabBase_addtlseat
	,a.r_PilotAge
	,a.r_LocModifier
	,a.r_PilotOtherModifier
	,a.r_LocAirportModifier
	,a.r_MinPrem
	,a.rr_AircraftModelModifierHull
	,a.rr_AircraftModelModifierLiab
	,a.rr_CMIndexHull
	,a.rr_CMIndexLiab
	,a.rr_CMIndexMedPay
	,a.rr_StdDiscountHull
	,a.rr_StdDiscountLiab
	,a.rr_LiabOnly
	,a.rr_PilotMinTotalHrs
	,a.rr_PilotAgeMin
	,a.rr_PilotAgeMax
	,a.rr_MMHrs
	,a.rr_MEHrs
	,a.rr_GearHrs
	,a.rr_HullMod
	,a.rr_GroundOnly
	,a.rr_IFR
	,a.rr_HullBase
	,a.rr_MedPayBase
	,a.rr_LiabBase
	,a.rr_LiabBase_addtlseat
	,a.rr_PilotAge
	,a.rr_LocModifier
	,a.rr_PilotOtherModifier
	,a.rr_LocAirportModifier
	,a.rr_MinPrem
	,a.rrr_AircraftModelModifierHull
	,a.rrr_AircraftModelModifierLiab
	,a.rrr_CMIndexHull
	,a.rrr_CMIndexLiab
	,a.rrr_CMIndexMedPay
	,a.rrr_StdDiscountHull
	,a.rrr_StdDiscountLiab
	,a.rrr_LiabOnly
	,a.rrr_PilotMinTotalHrs
	,a.rrr_PilotAgeMin
	,a.rrr_PilotAgeMax
	,a.rrr_MMHrs
	,a.rrr_MEHrs
	,a.rrr_GearHrs
	,a.rrr_HullMod
	,a.rrr_GroundOnly
	,a.rrr_IFR
	,a.rrr_HullBase
	,a.rrr_MedPayBase
	,a.rrr_LiabBase
	,a.rrr_LiabBase_addtlseat
	,a.rrr_PilotAge
	,a.rrr_LocModifier
	,a.rrr_PilotOtherModifier
	,a.rrr_LocAirportModifier
	,a.rrr_MinPrem
	,a.zz_AircraftModelModifierHull
	,a.zz_AircraftModelModifierLiab
	,a.zz_CMIndexHull
	,a.zz_CMIndexLiab
	,a.zz_CMIndexMedPay
	,a.zz_StdDiscountHull
	,a.zz_StdDiscountLiab
	,a.zz_LiabOnly
	,a.zz_PilotMinTotalHrs
	,a.zz_PilotAgeMin
	,a.zz_PilotAgeMax
	,a.zz_MMHrs
	,a.zz_MEHrs
	,a.zz_GearHrs
	,a.zz_HullMod
	,a.zz_GroundOnly
	,a.zz_IFR
	,a.zz_HullBase
	,a.zz_MedPayBase
	,a.zz_LiabBase
	,a.zz_LiabBase_addtlseat
	,a.zz_PilotAge
	,a.zz_LocModifier
	,a.zz_PilotOtherModifier
	,a.zz_LocAirportModifier
	,a.zz_MinPrem
into #apollo02
from #term02 as t
left join #apollo01a as a on t.Policyno = a.policyno and t.FAAno = a.faano  
left join #policylvl as c on t.polid = c.polid

----------------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#rerating') is not null drop table #rerating

select * 
into #rerating
FROM (

select policyno + cast(statid as varchar(5)) + cast(isnull(faano,'APL') as varchar(25)) + cast(datepart(mm,EfDate) as varchar(2)) + '-' + cast(datepart(dd,EfDate) as varchar(2)) + '-' + cast(datepart(YY,EfDate) as varchar(4)) + cast(isnull(AircraftType,1) as varchar(25)) [Lookup] 
,reserving
,sum(tblcoveragesprem) tblcoveragesprem
,sum(r_techprem_final) techprem
,sum(rr_techprem_final) rr_techprem
,sum(rrr_techprem_final) rrr_techprem
,sum(zz_techprem_final) zz_techprem


FROM [Pricing_AIM].[dbo].[aim_r_ac_final_2]
group by policyno + cast(statid as varchar(5)) + cast(isnull(faano,'APL') as varchar(25)) + cast(datepart(mm,EfDate) as varchar(2)) + '-' + cast(datepart(dd,EfDate) as varchar(2)) + '-' + cast(datepart(YY,EfDate) as varchar(4)) + cast(isnull(AircraftType,1) as varchar(25))
,reserving

union all
select policyno + cast(statid as varchar(5)) + cast('APL' as varchar(25)) + cast(datepart(mm,EfDate) as varchar(2)) + '-' + cast(datepart(dd,EfDate) as varchar(2)) + '-' + cast(datepart(YY,EfDate) as varchar(4)) + cast(isnull(999,1) as varchar(25)) [Lookup] 
,reserving
,sum(tblcoveragesprem) tblcoveragesprem
,sum(r_techprem_final) techprem
,sum(rr_techprem_final) rr_techprem
,sum(rrr_techprem_final) rrr_techprem
,sum(zz_techprem_final) zz_techprem


FROM pricing_aim.dbo.aim_r_ap_final_2
group by policyno + cast(statid as varchar(5)) + cast('APL' as varchar(25)) + cast(datepart(mm,EfDate) as varchar(2)) + '-' + cast(datepart(dd,EfDate) as varchar(2)) + '-' + cast(datepart(YY,EfDate) as varchar(4)) + cast(isnull(999,1) as varchar(25))
,reserving
)a1



if OBJECT_ID('tempdb.dbo.#reratefactor') is not null drop table #reratefactor

select [Lookup]
,reserving
,case when isnull(techprem,0)=0 then 1 else tblcoveragesprem/techprem end Schedule_Factor 
,case when isnull(techprem,0)=0 then 1 else rr_techprem/techprem end rr_factor
,case when isnull(techprem,0)=0 then 1 else rrr_techprem/techprem end rrr_factor
,case when isnull(techprem,0)=0 then 1 else zz_techprem/techprem end zz_factor
into #reratefactor
FROM #rerating

-----------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#apollo03') is not null drop table #apollo03

select a.*
,datepart(yy,a.EfDate)*100 + datepart(mm,a.EfDate) mth_pol_eff
,datepart(yy,a.ExDate)*100 + datepart(mm,a.ExDate) mth_pol_exp
,datepart(yy,a.Calendar_Effective_Date)*100 + datepart(mm,a.Calendar_Effective_Date) mth_cal_eff
,datepart(yy,a.Calendar_Expiration_Date)*100 + datepart(mm,a.Calendar_Expiration_Date) mth_cal_exp
,datepart(yy,a.EfDate)*10 + case when datepart(mm,a.EfDate) in (1,2,3) then 1 when datepart(mm,a.EfDate) in (4,5,6) then 2 when datepart(mm,a.EfDate) in (7,8,9) then 3 else 4 end qtr_pol_eff
,datepart(yy,a.ExDate)*10 + case when datepart(mm,a.ExDate) in (1,2,3) then 1 when datepart(mm,a.ExDate) in (4,5,6) then 2 when datepart(mm,a.ExDate) in (7,8,9) then 3 else 4 end qtr_pol_exp
,datepart(yy,a.Calendar_Effective_Date)*10 + case when datepart(mm,a.Calendar_Effective_Date) in (1,2,3) then 1 when datepart(mm,a.Calendar_Effective_Date) in (4,5,6) then 2 when datepart(mm,a.Calendar_Effective_Date) in (7,8,9) then 3 else 4 end qtr_cal_eff
,datepart(yy,a.Calendar_Expiration_Date)*10 + case when datepart(mm,a.Calendar_Expiration_Date) in (1,2,3) then 1 when datepart(mm,a.Calendar_Expiration_Date) in (4,5,6) then 2 when datepart(mm,a.Calendar_Expiration_Date) in (7,8,9) then 3 else 4 end qtr_cal_exp
,datepart(yy,a.EfDate) yr_pol
,datepart(yy,a.Calendar_Effective_Date) yr_cal_eff
,cast(datediff(dd, a.EfDate, dateadd(yy, 1, a.EfDate)) as float) term_year
,round(cast(datediff(dd, a.EfDate, a.ExDate) AS MONEY) / cast(datediff(dd, a.EfDate, dateadd(yy, 1, a.EfDate)) AS MONEY), 3) Term_years
,b.Schedule_Factor
,b.rr_factor
,b.rrr_factor
,b.zz_factor
,1 STT
,case when isnull(b.Schedule_Factor,1)<.1 then 1 else isnull(b.Schedule_Factor,1) end r_STT
,case when isnull(b.Schedule_Factor,1)<.1 then 1 else isnull(b.Schedule_Factor,1) end  / case when isnull(b.rr_factor,1) = 0 then 1 else isnull(b.rr_factor,1) end rr_STT
,case when isnull(b.Schedule_Factor,1)<.1 then 1 else isnull(b.Schedule_Factor,1) end  / case when isnull(b.rrr_factor,1) = 0 then 1 else isnull(b.rrr_factor,1) end rrr_STT
,case when isnull(b.Schedule_Factor,1)<.1 then 1 else isnull(b.Schedule_Factor,1) end  / case when isnull(b.zz_factor,1) = 0 then 1 else isnull(b.zz_factor,1) end zz_STT
,prem_written as premt_written
,prem_annual as premt_annual
,0 as zero_tech
,ismanual as r_ismanual
,ismanual as rr_ismanual
,ismanual as rrr_ismanual
,ismanual as zz_ismanual
into #apollo03
FROM #apollo02 a
left join #reratefactor b on a.[lookup]=b.[lookup] and a.reserving=b.reserving
order by a.[lookup]

update #apollo03 -- limit the stt factors b/c some of them have ridiculous high value (ex. 'GA92-37908-00')
set
	Schedule_Factor = case when Schedule_Factor < 0.25 then 0.25 
							when Schedule_Factor > 4 then 4
							else Schedule_Factor end
	,rr_factor = case when rr_factor < 0.25 then 0.25 
							when rr_factor > 4 then 4
							else rr_factor end
	,rrr_factor = case when rrr_factor < 0.25 then 0.25 
							when rrr_factor > 4 then 4
							else rrr_factor end
	,zz_factor = case when zz_factor < 0.25 then 0.25 
							when zz_factor > 4 then 4
							else zz_factor end
	,r_STT = case when r_STT < 0.25 then 0.25 
							when r_STT > 4 then 4
							else r_STT end
	,rr_STT = case when rr_STT < 0.25 then 0.25 
							when rr_STT > 4 then 4
							else rr_STT end
	,rrr_STT = case when rrr_STT < 0.25 then 0.25 
							when rrr_STT > 4 then 4
							else rrr_STT end
	,zz_STT = case when zz_STT < 0.25 then 0.25 
							when zz_STT > 4 then 4
							else zz_STT end
	,zero_tech =  case when premt_annual = 0 then 1 else 0 end



if OBJECT_ID('tempdb.dbo.#apollo04') is not null drop table #apollo04
select
	*
	,prem_written prem_tech_written
	,prem_written / r_STT  r_prem_tech_written
	,prem_written / rr_STT  rr_prem_tech_written
	,prem_written / rrr_STT  rrr_prem_tech_written
	,prem_written / zz_STT  zz_prem_tech_written
	,prem_written as r_prem_written
	,prem_written / case when isnull(Schedule_Factor,1)<.1 then 1 else isnull(Schedule_Factor,1) end  * isnull(rr_factor,1) rr_prem_written
	,prem_written / case when isnull(Schedule_Factor,1)<.1 then 1 else isnull(Schedule_Factor,1) end  * isnull(rrr_factor,1) rrr_prem_written
	,prem_written / case when isnull(Schedule_Factor,1)<.1 then 1 else isnull(Schedule_Factor,1) end  * isnull(zz_factor,1) zz_prem_written
into #apollo04
from #apollo03

alter table #apollo04
add prem_tech_annual float
,r_prem_tech_annual float
,rr_prem_tech_annual float
,rrr_prem_tech_annual float
,zz_prem_tech_annual float
,r_prem_annual float
,rr_prem_annual float
,rrr_prem_annual float
,zz_prem_annual float

Update #apollo04
set prem_tech_annual = case when factor = 0 then 0 else prem_tech_written/factor end
,r_prem_tech_annual = case when factor = 0 then 0 else r_prem_tech_written/factor end
,rr_prem_tech_annual = case when factor = 0 then 0 else rr_prem_tech_written/factor end
,rrr_prem_tech_annual = case when factor = 0 then 0 else rrr_prem_tech_written/factor end
,zz_prem_tech_annual = case when factor = 0 then 0 else zz_prem_tech_written/factor end
,r_prem_annual = case when factor = 0 then 0 else r_prem_tech_written/factor end
,rr_prem_annual = case when factor = 0 then 0 else rr_prem_tech_written/factor end
,rrr_prem_annual = case when factor = 0 then 0 else rrr_prem_tech_written/factor end
,zz_prem_annual = case when factor = 0 then 0 else zz_prem_tech_written/factor end
,premt_annual =  case when prem_annual = 0 then 0 when abs(premt_annual/prem_annual)<=.02 then 0 else premt_annual end
,premt_written =  case when prem_written = 0 then 0 when abs(premt_written/prem_written)<=.02 then 0 else premt_written end

----------------------------------------------------------------------------
if OBJECT_ID('tempdb.dbo.#apollo05') is not null drop table #apollo05
select
	*
	,case when prem_annual < 0 then -1 else 1 end trans_mod
	,r_prem_annual - r_prem_tech_annual as adjustment
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_written
			else 0
			end r_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_written
			else 0
			end rr_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_written
			else 0
			end rrr_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_written
			else 0
			end zz_adq_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_annual
			else 0
			end r_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_annual
			else 0
			end rr_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_annual
			else 0
			end rrr_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_annual
			else 0
			end zz_adq_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_written
			else 0
			end r_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_written
			else 0
			end rr_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_written
			else 0
			end rrr_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_written
			else 0
			end zz_adq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_annual
			else 0
			end r_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_annual
			else 0
			end rr_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_annual
			else 0
			end rrr_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_annual
			else 0
			end zz_adq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_written * 0.65 else 0 end as r_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_written * 0.65 else 0 end as rr_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_written * 0.65 else 0 end as rrr_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_written * 0.65 else 0 end as zz_padq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_annual * 0.65 else 0 end as r_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_annual * 0.65 else 0 end as rr_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_annual * 0.65 else 0 end as rrr_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_annual * 0.65 else 0 end as zz_padq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_written * 0.65 else 0 end as r_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_written * 0.65 else 0 end as rr_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_written * 0.65 else 0 end as rrr_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_written * 0.65 else 0 end as zz_blpadq_tech_written
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then r_prem_tech_annual * 0.65 else 0 end as r_blpadq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rr_prem_tech_annual * 0.65 else 0 end as rr_blpadq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then rrr_prem_tech_annual * 0.65 else 0 end as rrr_blpadq_tech_annual
	,case when substring(cast(flag_r_trans as nvarchar),2,1) = '1' or substring(cast(flag_r_trans as nvarchar),2,1) = '2' then zz_prem_tech_annual * 0.65 else 0 end as zz_blpadq_tech_annual
into #apollo05
from #apollo04

update #apollo05
set
	prem_written = ROUND(prem_written,0)
	,prem_annual = ROUND(prem_annual,0)
	,prem_tech_written = ROUND(prem_tech_written,0)
	,r_prem_tech_written = ROUND(r_prem_tech_written,0)
	,rr_prem_tech_written = ROUND(rr_prem_tech_written,0)
	,rrr_prem_tech_written = ROUND(rrr_prem_tech_written,0)
	,zz_prem_tech_written = ROUND(zz_prem_tech_written,0)
	,r_prem_written = ROUND(r_prem_written,0)
	,rr_prem_written = ROUND(rr_prem_written,0)
	,rrr_prem_written = ROUND(rrr_prem_written,0)
	,zz_prem_written = ROUND(zz_prem_written,0)
	,r_prem_tech_annual = ROUND(r_prem_tech_annual,0)
	,rr_prem_tech_annual = ROUND(rr_prem_tech_annual,0)
	,rrr_prem_tech_annual = ROUND(rrr_prem_tech_annual,0)
	,zz_prem_tech_annual = ROUND(zz_prem_tech_annual,0)
	,r_prem_annual = ROUND(r_prem_annual,0)
	,rr_prem_annual = ROUND(rr_prem_annual,0)
	,rrr_prem_annual = ROUND(rrr_prem_annual,0)
	,zz_prem_annual = ROUND(zz_prem_annual,0)
	,r_adq_written = ROUND(r_adq_written,0)
	,rr_adq_written = ROUND(rr_adq_written,0)
	,rrr_adq_written = ROUND(rrr_adq_written,0)
	,zz_adq_written = ROUND(zz_adq_written,0)
	,r_adq_annual = ROUND(r_adq_annual,0)
	,rr_adq_annual = ROUND(rr_adq_annual,0)
	,rrr_adq_annual = ROUND(rrr_adq_annual,0)
	,zz_adq_annual = ROUND(zz_adq_annual,0)
	,r_adq_tech_written = ROUND(r_adq_tech_written,0)
	,rr_adq_tech_written = ROUND(rr_adq_tech_written,0)
	,rrr_adq_tech_written = ROUND(rrr_adq_tech_written,0)
	,zz_adq_tech_written = ROUND(zz_adq_tech_written,0)
	,r_adq_tech_annual = ROUND(r_adq_tech_annual,0)
	,rr_adq_tech_annual = ROUND(rr_adq_tech_annual,0)
	,rrr_adq_tech_annual = ROUND(rrr_adq_tech_annual,0)
	,zz_adq_tech_annual = ROUND(zz_adq_tech_annual,0)
	,r_padq_tech_written = ROUND(r_padq_tech_written,0)
	,rr_padq_tech_written = ROUND(rr_padq_tech_written,0)
	,rrr_padq_tech_written = ROUND(rrr_padq_tech_written,0)
	,zz_padq_tech_written = ROUND(zz_padq_tech_written,0)	
	,r_padq_tech_annual = ROUND(r_padq_tech_annual,0)
	,rr_padq_tech_annual = ROUND(rr_padq_tech_annual,0)
	,rrr_padq_tech_annual = ROUND(rrr_padq_tech_annual,0)
	,zz_padq_tech_annual = ROUND(zz_padq_tech_annual,0)
	,r_blpadq_tech_written = ROUND(r_blpadq_tech_written,0)
	,rr_blpadq_tech_written = ROUND(rr_blpadq_tech_written,0)
	,rrr_blpadq_tech_written = ROUND(rrr_blpadq_tech_written,0)
	,zz_blpadq_tech_written = ROUND(zz_blpadq_tech_written,0)
	,r_blpadq_tech_annual = ROUND(r_blpadq_tech_annual,0)
	,rr_blpadq_tech_annual = ROUND(rr_blpadq_tech_annual,0)
	,rrr_blpadq_tech_annual = ROUND(rrr_blpadq_tech_annual,0)
	,zz_blpadq_tech_annual = ROUND(zz_blpadq_tech_annual,0)


if OBJECT_ID('tempdb.dbo.#apollo06') is not null drop table #apollo06
select
	*
into #apollo06
from #apollo05
where Policyno like 'GA%'


update #apollo06
set r_adq_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else r_adq_written
						end
,rr_adq_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rr_adq_written
						end
,rrr_adq_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rrr_adq_written
						end
,zz_adq_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else zz_adq_written
						end
,r_adq_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else r_adq_annual
						end
,rr_adq_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rr_adq_annual
						end
,rrr_adq_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rrr_adq_annual
						end
,zz_adq_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else zz_adq_annual
						end
,r_adq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else r_adq_tech_written
						end
,rr_adq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rr_adq_tech_written
						end
,rrr_adq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rrr_adq_tech_written
						end
,zz_adq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else zz_adq_tech_written
						end
,r_adq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else r_adq_tech_annual
						end
,rr_adq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rr_adq_tech_annual
						end
,rrr_adq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rrr_adq_tech_annual
						end
,zz_adq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else zz_adq_tech_annual
						end
,r_padq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else r_padq_tech_written
						end
,rr_padq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rr_padq_tech_written
						end
,rrr_padq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rrr_padq_tech_written
						end
,zz_padq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else zz_padq_tech_written
						end
,r_padq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else r_padq_tech_annual
						end
,rr_padq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rr_padq_tech_annual
						end
,rrr_padq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rrr_padq_tech_annual
						end
,zz_padq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else zz_padq_tech_annual
						end
,r_blpadq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else r_blpadq_tech_written
						end
,rr_blpadq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rr_blpadq_tech_written
						end
,rrr_blpadq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else rrr_blpadq_tech_written
						end
,zz_blpadq_tech_written = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_written
						else zz_blpadq_tech_written
						end
,r_blpadq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else r_blpadq_tech_annual
						end
,rr_blpadq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rr_blpadq_tech_annual
						end
,rrr_blpadq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else rrr_blpadq_tech_annual
						end
,zz_blpadq_tech_annual = case when FAAno <> 'PLVL' and flag_r_trans is null and efdate is null then prem_annual
						else zz_blpadq_tech_annual
						end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------
--drop table Pricing_aim.dbo.aim_apollo_STT

--select * into Pricing_aim.dbo.aim_apollo_STT from #apollo06


--check prem
--select sum(prem_written) from #apollo06 --group by policyno order by policyno
--select sum(a.[7C]+a.[7D]+a.[7DL]+a.[7E]+a.[7F]+a.[7G]) as TOT_WP
--FROM [Pricing_aim].[dbo].[PolTblNew] a
--where [EffDate] >= '2011-01-01' and policyno like 'GA%'--'2021-01-01' 
--
--select policyno, sum(prem_written) from #apollo06 group by policyno order by policyno
--select policyno, sum(a.[7C]+a.[7D]+a.[7DL]+a.[7E]+a.[7F]+a.[7G]) as TOT_WP
--FROM [Pricing_aim].[dbo].[PolTblNew] a
--where [EffDate] >= '2011-01-01' and policyno like 'GA%'--'2021-01-01' 
--group by Policyno order by policyno

-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
--Combine Diamond and Apollo
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#Diamond01') is not null drop table #Diamond01 
select
	Company
	,business_unit
	,reserving
	,'Diamond' as system
	,'Aircraft' as line
	,product
	,state_insd
	,state_risk
	,a.policy_id
	,case when b.rewrittenfrom_policy_id <> 0 then b.rewrittenfrom_policy_id else min(PrevPolID) over (partition by a.client_id ,a.policy_id) end PreviousPolicy_ID
	,case when b.rewrittenfrom_policy_id <> 0 
		then cast(CONCAT(case when left(b.rewrittenfrom_policy,5) ='GA100' then 10 when left(b.rewrittenfrom_policy,5) = 'HLMGA' then 20 when left(b.rewrittenfrom_policy,5) = 'HDIGA' then 30 else 40 end  ,right(b.rewrittenfrom_policy,9)) as bigint) *100 + max(c.renewal_ver) over (partition by b.rewrittenfrom_policy)
--		then b.rewrittenfrom_policy
 		else min(PrevPolNum) over (partition by a.client_id ,a.pol_num_full_clean) end PreviousPolNumFullClean	
	,pol_num
	,convert(nvarchar,a.policyimage_num) as policyimage_num
	,convert(nvarchar,pol_edition) as pol_edition
	,convert(nvarchar,pol_num_full_clean) as pol_num_full_clean
	,PolicyType
	,policytermversion_dscr
	,convert(nvarchar,faano) as faano 
	,agent_num
	,producer_num
	,agent_name
	,producer_name
	,insd_name_hist 
	,underwriter_name
	,ind_pri_xs
	,SpecialUse_Code
	,Primary_use_rating
--	,primary_use_rating_true
	,covg
	,covg_group_desc
	,covg_desc
	,PD_Limit
	,limit_dscr 
	,CSL_Occurance_Limit
	,CSL_Passenger_Limit
	,Med_Passenger_Limit --data type conversion issue
	,trans_mod
	,date_pol_eff
	,date_pol_exp
	,date_cal_eff
	,date_cal_exp
	,date_book_val_max
	,Transaction_type
	,transaction_term
	,term_year
	,term
	,Term_years
	,mth_pol_eff
	,mth_pol_exp
	,mth_cal_eff
	,mth_cal_exp
	,qtr_pol_eff
	,qtr_pol_exp
	,qtr_cal_eff
	,qtr_cal_exp
	,yr_pol
	,yr_cal_eff
	,case when ([date_pol_eff] between '7/1/21' and '6/30/22') and company = 'Hallmark Insurance Company' then '2104'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company = 'Hallmark American Insurance Company' then '2104'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company = 'American Hallmark Insurance Co of TX' then '2105'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company = 'Pinnacle National Insurance Company' then '2106'
	   when ([date_pol_eff] between '7/1/21' and '6/30/22') and company = 'State National Insurance Company' then '2107'
	   
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company = 'Hallmark Insurance Company' then '2204'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company = 'Hallmark American Insurance Company' then '2204'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company = 'American Hallmark Insurance Co of TX' then '2205'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company = 'Pinnacle National Insurance Company' then '2206'
	   when ([date_pol_eff] between '7/1/22' and '6/30/23') and company = 'State National Insurance Company' then '2207'

	    when ([date_pol_eff] between '7/1/23' and '6/30/24') and company = 'Hallmark Insurance Company' then '2304'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company = 'Hallmark American Insurance Company' then '2304'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company = 'American Hallmark Insurance Co of TX' then '2305'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company = 'Pinnacle National Insurance Company' then '2306'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company = 'State National Insurance Company' then '2307'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company ='National Specialty Insurance Company' then '2308'
	   when ([date_pol_eff] between '7/1/23' and '6/30/24') and company ='HDI Global Select Insurance Company' then '2309'

	   	 when ([date_pol_eff] between '7/1/24' and '6/30/25') and company = 'Hallmark Insurance Company' then '2404'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company = 'Hallmark American Insurance Company' then '2404'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company = 'American Hallmark Insurance Co of TX' then '2405'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company = 'Pinnacle National Insurance Company' then '2406'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company = 'State National Insurance Company' then '2407'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company ='National Specialty Insurance Company' then '2408'
	   when ([date_pol_eff] between '7/1/24' and '6/30/25') and company ='HDI Global Select Insurance Company' then '2409'  

	   	 when ([date_pol_eff] between '7/1/25' and '6/30/26') and company = 'Hallmark Insurance Company' then '2504'
	   when ([date_pol_eff] between '7/1/25' and '6/30/26') and company = 'Hallmark American Insurance Company' then '2504'
	   when ([date_pol_eff] between '7/1/25' and '6/30/26') and company = 'American Hallmark Insurance Co of TX' then '2505'
	   when ([date_pol_eff] between '7/1/25' and '6/30/26') and company = 'Pinnacle National Insurance Company' then '2506'
	   when ([date_pol_eff] between '7/1/25' and '6/30/26') and company = 'State National Insurance Company' then '2507'
	   when ([date_pol_eff] between '7/1/25' and '6/30/26') and company ='National Specialty Insurance Company' then '2508'
	   when ([date_pol_eff] between '7/1/25' and '6/30/26') and company ='HDI Global Select Insurance Company' then '2509'  
	  
	   else 'Error' end as Treaty
	,date_cncl 
	,aircraft_type_description
	,hull_value
	,min_age
	,max_age
	,aircraft_type_rating as AircraftType
	,Min_Total_Hours as pilotmintotalhrs
	,gear_type_dscr as Gear
	,wing_type_dscr as Wing
	,model
	,model_code
	,ENTITY_TYPE
	,airport_name as AirportName
	,policy_city
	,policy_state
	,policy_zip
	,policy_county
	,agency_city
	,agency_state
	,r_versionid
	,r_AircraftModelModifierHull
	,r_AircraftModelModifierLiab
	,r_SeatIndex
	,r_PrimaryPilotRating
	,r_CMIndexHull
	,r_CMIndexLiability
	,r_CMIndexMedPay
	,r_StdDiscountHull
	,r_StdDiscountLiab
	,r_ismanual
	,r_LiabilityOnlyModifier
	,r_MinimumPremium
	,r_PilotMinTotalHrsModifier
	,r_PilotMMHrsModifier
	,r_PilotMEHrsModifier
	,r_PilotAgeMinModifier
	,r_PilotAgeMaxModifier
	,r_HullModifier
	,r_Ground_Modifier
	,r_HullBaseRate
	,r_LiabBaseRate
	,r_LiabBaseAddtlSeat
	,r_MedPayBaseRate
	,r_PilotIFRModifier
	,r_PilotMinGearHrsModifier
	,r_coastal_factor
	,r_AircraftTypeModifier
	,rr_versionid
	,rr_AircraftModelModifierHull
	,rr_AircraftModelModifierLiab
	,rr_SeatIndex
	,rr_PrimaryPilotRating
	,rr_CMIndexHull
	,rr_CMIndexLiability
	,rr_CMIndexMedPay
	,rr_StdDiscountHull
	,rr_StdDiscountLiab
	,rr_ismanual
	,rr_LiabilityOnlyModifier
	,rr_MinimumPremium
	,rr_PilotMinTotalHrsModifier
	,rr_PilotMMHrsModifier
	,rr_PilotMEHrsModifier
	,rr_PilotAgeMinModifier
	,rr_PilotAgeMaxModifier
	,rr_HullModifier
	,rr_Ground_Modifier
	,rr_HullBaseRate
	,rr_LiabBaseRate
	,rr_LiabBaseAddtlSeat
	,rr_MedPayBaseRate
	,rr_PilotIFRModifier
	,rr_PilotMinGearHrsModifier
	,rr_coastal_factor
	,rr_AircraftTypeModifier
	,rrr_versionid
	,rrr_AircraftModelModifierHull
	,rrr_AircraftModelModifierLiab
	,rrr_SeatIndex
	,rrr_PrimaryPilotRating
	,rrr_CMIndexHull
	,rrr_CMIndexLiability
	,rrr_CMIndexMedPay
	,rrr_StdDiscountHull
	,rrr_StdDiscountLiab
	,rrr_ismanual
	,rrr_LiabilityOnlyModifier
	,rrr_MinimumPremium
	,rrr_PilotMinTotalHrsModifier
	,rrr_PilotMMHrsModifier
	,rrr_PilotMEHrsModifier
	,rrr_PilotAgeMinModifier
	,rrr_PilotAgeMaxModifier
	,rrr_HullModifier
	,rrr_Ground_Modifier
	,rrr_HullBaseRate
	,rrr_LiabBaseRate
	,rrr_LiabBaseAddtlSeat
	,rrr_MedPayBaseRate
	,rrr_PilotIFRModifier
	,rrr_PilotMinGearHrsModifier
	,rrr_coastal_factor
	,rrr_AircraftTypeModifier
	,zz_versionid
	,zz_AircraftModelModifierHull
	,zz_AircraftModelModifierLiab
	,zz_SeatIndex
	,zz_PrimaryPilotRating
	,zz_CMIndexHull
	,zz_CMIndexLiability
	,zz_CMIndexMedPay
	,zz_StdDiscountHull
	,zz_StdDiscountLiab
	,zz_ismanual
	,zz_LiabilityOnlyModifier
	,zz_MinimumPremium
	,zz_PilotMinTotalHrsModifier
	,zz_PilotMMHrsModifier
	,zz_PilotMEHrsModifier
	,zz_PilotAgeMinModifier
	,zz_PilotAgeMaxModifier
	,zz_HullModifier
	,zz_Ground_Modifier
	,zz_HullBaseRate
	,zz_LiabBaseRate
	,zz_LiabBaseAddtlSeat
	,zz_MedPayBaseRate
	,zz_PilotIFRModifier
	,zz_PilotMinGearHrsModifier
	,zz_coastal_factor
	,zz_AircraftTypeModifier
	,adjustment_type
	,adjustment
	,premt_annual
	--,premt_written
	,zero_tech
	,comm_written
	,prem_written
	,prem_annual
	,STT
	,r_STT
	,rr_STT
	,rrr_STT
	,zz_STT
	,premium_tech_written as prem_tech_written
	,r_premium_tech_written as r_prem_tech_written
	,rr_premium_tech_written as rr_prem_tech_written
	,rrr_premium_tech_written as rrr_prem_tech_written
	,zz_premium_tech_written as zz_prem_tech_written
	,r_prem_written
	,r_prem_written rr_prem_written
	,r_prem_written rrr_prem_written
	,r_prem_written zz_prem_written
	,r_prem_tech_annual
	,rr_prem_tech_annual
	,rrr_prem_tech_annual
	,zz_prem_tech_annual
	,r_prem_annual
	,r_prem_annual rr_prem_annual
	,r_prem_annual rrr_prem_annual
	,r_prem_annual zz_prem_annual
	,r_adq_written
	,rr_adq_written
	,rrr_adq_written
	,zz_adq_written
	,r_adq_annual
	,rr_adq_annual
	,rrr_adq_annual
	,zz_adq_annual
	,r_adq_tech_written
	,rr_adq_tech_written
	,rrr_adq_tech_written
	,zz_adq_tech_written
	,r_adq_tech_annual
	,rr_adq_tech_annual
	,rrr_adq_tech_annual
	,zz_adq_tech_annual
	,r_padq_tech_written
	,rr_padq_tech_written
	,rrr_padq_tech_written 
	,zz_padq_tech_written 
	,r_padq_tech_annual
	,rr_padq_tech_annual
	,rrr_padq_tech_annual
	,zz_padq_tech_annual
	,r_blpadq_tech_written
	,rr_blpadq_tech_written
	,rrr_blpadq_tech_written
	,zz_blpadq_tech_written 
	,r_blpadq_tech_annual
	,rr_blpadq_tech_annual
	,rrr_blpadq_tech_annual
	,zz_blpadq_tech_annual
	,flag_r_trans
into #Diamond01
from #temp17 a
left join [AHI-S06].[Diamond].[dbo].[Policy] b on a.policy_id = b.policy_id
left join [AHI-S06].diamond.dbo.policyimage c on c.policy_id = nullif(b.rewrittenfrom_policy_id,0) and b.lastimage_num = c.policyimage_num


update #Diamond01
set Med_Passenger_Limit = case when Med_Passenger_Limit = '1,000' then 1000
								when Med_Passenger_Limit = '1,500' then 1500
								when Med_Passenger_Limit = '10,000 PP' then 10000
								when Med_Passenger_Limit = '2,500' then 2500
								when Med_Passenger_Limit = '3,000 PP' then 3000
								when Med_Passenger_Limit = '5,000' then 5000
								when Med_Passenger_Limit = 'No Coverage' then null
								end,
PreviousPolicy_ID = case when PreviousPolicy_ID = policy_id then NULL 
else PreviousPolicy_ID end,
PreviousPolNumFullClean = case when PreviousPolNumFullClean = pol_num_full_clean then NULL 
else PreviousPolNumFullClean end
--select top 100 * from [Diamond].[dbo].policyimage
------------------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#Aapollo01') is not null drop table #Aapollo01
select 
	company_code as Company
	,'AIM' as business_unit
	,reserving
	,'Apollo' as system
	,'Aircraft' as line
	,'Aircraft' as product
	,state_insd
	,state_risk
	,polid as policy_id
	,ppolid as PreviousPolicy_ID
	,PreviousPolNumFullClean
	,Policyno as pol_num
	----,SUBSTRING(Policyno, 0, LEN(Policyno) + 1 - 3) as pol_num
	,Endorsement as policyimage_num
	,pol_ed as pol_edition
	--,convert(varchar,pol_ed) as pol_edition
	,convert(varchar,pol_num_full_clean) as pol_num_full_clean
	,'Policy' as PolicyType
	,'12 Month' as policytermversion_dscr
	,convert(varchar,faano) as faano
	,agency_num as agent_num
	,agency_num as producer_num
	,agency_name as agent_name
	,agency_name as producer_name
	,insd_name_hist
	,AssignedUnderwriter as underwriter_name
	,'Primary' as ind_pri_xs
	,primaryuseid as SpecialUse_Code
	,primaryuseid as Primary_use_rating
--	,primaryuseid_true as Primary_use_rating_true
	,coveragecode_id as covg
	,Coverage_group as covg_group_desc
	,coveragecode_desc as covg_desc
	,limit_dscr as PD_Limit
	,limit_dscr
	,CSL_Occurance_Limit
	,CSL_Passenger_Limit
	,Med_Passenger_Limit_description as Med_Passenger_Limit
	,trans_mod
	,EfDate as date_pol_eff
	,ExDate as date_pol_exp
	,Calendar_Effective_Date as date_cal_eff
	,Calendar_Expiration_Date as date_cal_exp
	,date_book_val_max
	,Transaction_type
	,Transaction_term as transaction_term
	,term_year
	,Term as term
	,Term_years
	,mth_pol_eff
	,mth_pol_exp
	,mth_cal_eff
	,mth_cal_exp
	,qtr_pol_eff
	,qtr_pol_exp
	,qtr_cal_eff
	,qtr_cal_exp
	,yr_pol
	,yr_cal_eff
	,Treaty
	,'2999-12-31' as date_cncl
	,AircraftTypeName as aircraft_type_description
	,HullValue_AgreedValue hull_value
	,min_age
	,max_age
	,aircraft_type_rating as AircraftType
	,Min_Total_Hours as pilotmintotalhrs
	,gear_type_dscr as Gear
	,wing as Wing
	,model
	,model_code
	,ENTITY_TYPE
	,policy_airport as AirportName
	,policy_city
	,state_risk as policy_state
	,policy_zip
	,policy_county
	,agency_city
	,agency_state
	,0 as r_versionid
	,r_AircraftModelModifierHull
	,r_AircraftModelModifierLiab
	,0 as r_SeatIndex
	,0 as r_PrimaryPilotRating
	,r_CMIndexHull
	,r_CMIndexLiab as r_CMIndexLiability
	,r_CMIndexMedPay
	,r_StdDiscountHull
	,r_StdDiscountLiab
	,r_ismanual
	,r_LiabOnly as r_LiabilityOnlyModifier
	,r_MinPrem as r_MinimumPremium
	,r_PilotMinTotalHrs as r_PilotMinTotalHrsModifier
	,r_MMHrs as r_PilotMMHrsModifier
	,r_MEHrs as r_PilotMEHrsModifier
	,r_PilotAgeMin as r_PilotAgeMinModifier
	,r_PilotAgeMax as r_PilotAgeMaxModifier
	,r_HullMod as r_HullModifier
	,r_GroundOnly as r_Ground_Modifier
	,r_HullBase as r_HullBaseRate
	,r_LiabBase as r_LiabBaseRate
	,r_LiabBase_addtlSeat as r_LiabBaseAddtlSeat
	,r_MedPayBase as r_MedPayBaseRate
	,r_IFR as r_PilotIFRModifier
	,r_GearHrs as r_PilotMinGearHrsModifier
	,r_LocAirportModifier as r_coastal_factor
	,0 as r_AircraftTypeModifier
	,0 as rr_versionid
	,rr_AircraftModelModifierHull
	,rr_AircraftModelModifierLiab
	,0 as rr_SeatIndex
	,0 as rr_PrimaryPilotRating
	,rr_CMIndexHull
	,rr_CMIndexLiab as rr_CMIndexLiability
	,rr_CMIndexMedPay
	,rr_StdDiscountHull
	,rr_StdDiscountLiab
	,rr_ismanual
	,rr_LiabOnly as rr_LiabilityOnlyModifier
	,rr_MinPrem as rr_MinimumPremium
	,rr_PilotMinTotalHrs as rr_PilotMinTotalHrsModifier
	,rr_MMHrs as rr_PilotMMHrsModifier
	,rr_MEHrs as rr_PilotMEHrsModifier
	,rr_PilotAgeMin as rr_PilotAgeMinModifier
	,rr_PilotAgeMax as rr_PilotAgeMaxModifier
	,rr_HullMod as rr_HullModifier
	,rr_GroundOnly as rr_Ground_Modifier
	,rr_HullBase as rr_HullBaseRate
	,rr_LiabBase as rr_LiabBaseRate
	,rr_LiabBase_addtlSeat as rr_LiabBaseAddtlSeat
	,rr_MedPayBase as rr_MedPayBaseRate
	,rr_IFR as rr_PilotIFRModifier
	,rr_GearHrs as rr_PilotMinGearHrsModifier
	,rr_LocAirportModifier as rr_coastal_factor
	,0 as rr_AircraftTypeModifier
	,0 as rrr_versionid
	,rrr_AircraftModelModifierHull
	,rrr_AircraftModelModifierLiab
	,0 as rrr_SeatIndex
	,0 as rrr_PrimaryPilotRating
	,rrr_CMIndexHull
	,rrr_CMIndexLiab as rrr_CMIndexLiability
	,rrr_CMIndexMedPay
	,rrr_StdDiscountHull
	,rrr_StdDiscountLiab
	,rrr_ismanual
	,rrr_LiabOnly as rrr_LiabilityOnlyModifier
	,rrr_MinPrem as rrr_MinimumPremium
	,rrr_PilotMinTotalHrs as rrr_PilotMinTotalHrsModifier
	,rrr_MMHrs as rrr_PilotMMHrsModifier
	,rrr_MEHrs as rrr_PilotMEHrsModifier
	,rrr_PilotAgeMin as rrr_PilotAgeMinModifier
	,rrr_PilotAgeMax as rrr_PilotAgeMaxModifier
	,rrr_HullMod as rrr_HullModifier
	,rrr_GroundOnly as rrr_Ground_Modifier
	,rrr_HullBase as rrr_HullBaseRate
	,rrr_LiabBase as rrr_LiabBaseRate
	,rrr_LiabBase_addtlSeat as rrr_LiabBaseAddtlSeat
	,rrr_MedPayBase as rrr_MedPayBaseRate
	,rrr_IFR as rrr_PilotIFRModifier
	,rrr_GearHrs as rrr_PilotMinGearHrsModifier
	,rrr_LocAirportModifier as rrr_coastal_factor
	,0 as rrr_AircraftTypeModifier
	,0 as zz_versionid
	,zz_AircraftModelModifierHull
	,zz_AircraftModelModifierLiab
	,0 as zz_SeatIndex
	,0 as zz_PrimaryPilotRating
	,zz_CMIndexHull
	,zz_CMIndexLiab as zz_CMIndexLiability
	,zz_CMIndexMedPay
	,zz_StdDiscountHull
	,zz_StdDiscountLiab
	,zz_ismanual
	,zz_LiabOnly as zz_LiabilityOnlyModifier
	,zz_MinPrem as zz_MinimumPremium
	,zz_PilotMinTotalHrs as zz_PilotMinTotalHrsModifier
	,zz_MMHrs as zz_PilotMMHrsModifier
	,zz_MEHrs as zz_PilotMEHrsModifier
	,zz_PilotAgeMin as zz_PilotAgeMinModifier
	,zz_PilotAgeMax as zz_PilotAgeMaxModifier
	,zz_HullMod as zz_HullModifier
	,zz_GroundOnly as zz_Ground_Modifier
	,zz_HullBase as zz_HullBaseRate
	,zz_LiabBase as zz_LiabBaseRate
	,zz_LiabBase_addtlSeat as zz_LiabBaseAddtlSeat
	,zz_MedPayBase as zz_MedPayBaseRate
	,zz_IFR as zz_PilotIFRModifier
	,zz_GearHrs as zz_PilotMinGearHrsModifier
	,zz_LocAirportModifier as zz_coastal_factor
	,0 as zz_AircraftTypeModifier
	,'Dollar' as adjustment_type
	,adjustment
	,premt_annual
	--,premt_written
	,zero_tech
	,Commission as comm_written
	,prem_written
	,prem_annual
	,STT
	,r_STT
	,rr_STT
	,rrr_STT
	,zz_STT
	,prem_tech_written
	,r_prem_tech_written
	,rr_prem_tech_written
	,rrr_prem_tech_written
	,zz_prem_tech_written
	,r_prem_written
	,rr_prem_written
	,rrr_prem_written
	,zz_prem_written
	,r_prem_tech_annual
	,rr_prem_tech_annual
	,rrr_prem_tech_annual
	,zz_prem_tech_annual
	,r_prem_annual
	,rr_prem_annual
	,rrr_prem_annual
	,zz_prem_annual
	,r_adq_written
	,rr_adq_written
	,rrr_adq_written
	,zz_adq_written
	,r_adq_annual
	,rr_adq_annual
	,rrr_adq_annual
	,zz_adq_annual
	,r_adq_tech_written
	,rr_adq_tech_written
	,rrr_adq_tech_written
	,zz_adq_tech_written
	,r_adq_tech_annual
	,rr_adq_tech_annual
	,rrr_adq_tech_annual
	,zz_adq_tech_annual
	,r_padq_tech_written
	,rr_padq_tech_written
	,rrr_padq_tech_written 
	,zz_padq_tech_written 
	,r_padq_tech_annual
	,rr_padq_tech_annual
	,rrr_padq_tech_annual
	,zz_padq_tech_annual
	,r_blpadq_tech_written
	,rr_blpadq_tech_written
	,rrr_blpadq_tech_written
	,zz_blpadq_tech_written 
	,r_blpadq_tech_annual
	,rr_blpadq_tech_annual
	,rrr_blpadq_tech_annual
	,zz_blpadq_tech_annual
	,flag_r_trans
into #Aapollo01
from #Apollo06

update #Aapollo01
set pol_edition = case when pol_num = 'GA99-A0E78-00q' then 0
						else pol_edition
						end

update #Aapollo01
set pol_num = case when pol_num = 'GA99-A0E78-00q' then 'GA99-A0E78-00'
						else pol_num
						end

------------------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#Data') is not null drop table #Data
select * 
into #Data
from #Diamond01
UNION ALL 
select * from #Aapollo01



-----------------------------------------------------------------------------------------------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#datafinal') is not null drop table #datafinal


select b.Client_id ,a.*,b.legacy_policynumber,
cast(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(b.legacy_policynumber ,'-',''),'a',1),'b',2),'c',3),'d',4),'e',5),'f',6),'g',7),'h',8),'i',9),'j',10),'k',11),'l',12),'m',13),'n',14),'o',15),'p',16),'q',17),'r',18),'s',19),'t',20),'u',21),'v',22),'w',23),'x',24),'y',25),'z',26) as float)  legacy_PolicyNumberFullClean
,b.rewrittenfrom_policy_id,b.rewrittenfrom_policy,b.rewrittenfrom_policyimage_num 
into #datafinal
from #data a
left join [AHI-S06].[Diamond].[dbo].[Policy] b on a.policy_id = b.policy_id

update a
set a.PreviousPolicy_ID = case when a.PreviousPolicy_ID is null and a.legacy_policynumber is not null then b.policy_id 
else a.PreviousPolicy_ID end,
a.PreviousPolNumFullClean = case when a.PreviousPolNumFullClean is null and a.legacy_PolicyNumberFullCLean is not null then b.pol_num_full_clean 
else a.PreviousPolNumFullClean end
from #datafinal a
left join #datafinal b on a.legacy_policynumber = b.pol_num

alter table #datafinal add FuturePolicy_ID int, FuturePolNumFullClean int

update a set FuturePolicy_ID = b.policy_id
from #datafinal a
left join #datafinal b on b.PreviousPolicy_ID = a.policy_id

if OBJECT_ID('dbo.test_aim_STT') is not null drop table dbo.test_aim_STT

select * into dbo.test_aim_STT from #datafinal

    ALTER TABLE dbo.test_aim_STT ADD
        row_hash     BINARY(32)   NULL,
        created_date DATETIME2(0) NOT NULL DEFAULT GETDATE(),
        last_updated DATETIME2(0) NOT NULL DEFAULT GETDATE();

    UPDATE dbo.test_aim_STT
    SET row_hash = CONVERT(BINARY(32), HASHBYTES('SHA2_256',
        ISNULL(CAST(prem_written           AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(prem_annual            AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(r_prem_tech_written    AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(rr_prem_tech_written   AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(rrr_prem_tech_written  AS NVARCHAR(30)), '') + '|' +
        ISNULL(CAST(zz_prem_tech_written   AS NVARCHAR(30)), '')));


drop table
#date_chks
,#pilot_count
,#temp_certifications
,#temp_certifications_pivot
,#temp_pilot_hours
,#temp_pilot_hours_a
,#temp_pilot_hours_b
,#temp_pilot_hours_min_max_a
,#temp_pilot_hours_min_max_b
,#occurance_limit_CSL
,#passenger_limit_CSL
,#passenger_limit_med
,#occurance_limit_med
,#pd_coverage
,#pd_nim_ded
,#pd_in_motion_ded
,#airport
,#InsuredandCompany
,#Company
,#agency
,#PolicyAddress
,#Entity
,#underwriter
,#policyimage
,#pol_air00
,#pol_air
,#aircraft
,#covg_prem
,#temp00
,#version
,#AircraftModelModifierHull
,#AircraftModelModifierHull_ex_gear
,#AircraftModelModifierLiab
,#AircraftModelModifierLiab_ex_gear
,#SeatIndex
,#SeatIndex_second
,#PrimaryPilotRating
,#PrimaryPilotRating_second
,#PrimaryPilotRating_third
,#PrimaryPilotRating_fourth
,#LocAirportModifier
,#LocAirportModifier_second
,#LocStateModifier
,#LocStateModifier_second
,#CMIndexHull
,#CMIndexHull_second
,#CMIndexLiability
,#CMIndexLiability_second
,#CMIndexLiability_third
,#CMIndexMedPay
,#StdDiscountHull
,#StdDiscountLiab
,#IsManual
,#IsManual_second
,#IsManual_third
,#IsManual_fourth
,#LiabilityOnlyModifier
,#MinimumPremium
,#minimumpremium_second
,#PilotMinTotalHrsModifier
,#PilotMinTotalHrsModifier_second
,#PilotMMHrsModifier
,#PilotMMHrsModifier_second
,#PilotMMHrsModifier_third
,#PilotMEHrsModifier
,#PilotMEHrsModifier_second
,#PilotMEHrsModifier_third
,#PilotAgeMinModifier
,#PilotAgeMinModifier_second
,#PilotAgeMinModifier_third
,#PilotAgeMinModifier_fourth
,#PilotAgeMaxModifier
,#PilotAgeMaxModifier_second
,#PilotAgeMaxModifier_third
,#PilotAgeMaxModifier_fourth
,#PilotGearHrsModifier
,#PilotGearHrsModifier_second
,#PilotGearHrsModifier_third
,#HullModifier
,#HullModifier_second
,#HullModifier_third
,#HullModifier_fourth
,#GroundOnlyModifier
,#PilotIFRModifier
,#PilotIFRModifier_second
,#PilotIFRModifier_third
,#HullBaseRate
,#HullBaseRate_second
,#LiabBaseRate
,#LiabBaseRate_second
,#LiabBaseAddtlSeat
,#LiabBaseAddtlSeat_second
,#MedPayBaseRate
,#MedPayBaseRate_second
,#MedPayBaseRate_third
,#Coastal
,#Aircraft_Type_Modifier
,#Aircraft_Type_Modifier_second
,#ded_base_model_1
,#ded_base_model_2
,#ded_base_model_3
,#ded_base_age_1
,#ded_base_type_1
,#ded_base_type_2
,#ded_base_type_3
,#temp01
,#temp02
,#temp03
,#temp04
,#temp05
,#temp06
,#temp07
,#temp08
,#temp09
,#temp10
,#temp11
,#temp12
,#temp13
,#temp14
,#temp15
,#temp16
,#temp17
,#reserving
,#reserving
,#term01
,#term02
,#apollo01
,#apollo01a
,#policylvl
,#apollo02
,#rerating
,#reratefactor
,#apollo03
,#apollo04
,#apollo05
,#apollo06
,#Diamond01
,#Aapollo01
,#Data
,#datafinal


DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID)
exec UPDATE_QUERY_TIMES @PROC_NAME, @StartTime
 
END TRY 
BEGIN CATCH 
SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE 
END CATCH
GO


