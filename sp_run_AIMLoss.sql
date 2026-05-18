USE [Pricing_AIM]
GO

/****** Object:  StoredProcedure [dbo].[run_AIMLoss]    Script Date: 5/18/2026 2:26:33 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[run_AIMLoss]
AS
BEGIN TRY	

declare @startTime datetime = getdate()


-------------------------------------------------------------------------------
--modify apollo's loss table to be like auto loss table
if OBJECT_ID('tempdb.dbo.#apolloloss') is not null drop table #apolloloss
select
	'Apollo' as system
	,a.[Claim No] as clm_ft_num
	,a.[Claim No] as claim_number
	,a.Clmid as claimcontrol_id
	,1 as claimant_num
	,1 as claimfeature_num
	,a.Reserving as reserving
	,a.[policy no] as policy
	,a.polid as policy_id
	,'ApolloData' Company
	,RIGHT(a.[policy no],2) as policyimage_num
	,a.AircraftID as aircraft_num
	,a.Claim_state as state_risk
	,a.AY as yr_loss
	,a.qtr_loss
	,a.mth_loss
	,a.DOL as date_loss
	,a.[Close Date] date_occ_close
	,a.[Close Date] date_ft_close
	,datepart(yy,a.TRANS_DATE)*100 + datepart(mm,a.TRANS_DATE) mth_cal_earn
	,a.mth_val
	,a.qtr_val
	,left(a.qtr_val,4) as yr_val
	,case when right(a.mth_val,1) = '3' or right(a.mth_val,1) = '6' or right(a.mth_val,1) = '9' then 1
			when right(a.mth_val,2) = '12' then 1
			else 0 
			end qtr_ind
	,case when right(a.mth_val,2) = '12' then 1
			else 0 
			end yr_ind
	--,'' as mth_cal_earn
	--,'' as qtr_cal_earn
	--,'' as yr_cal_earn
	,a.mth_rept as rept_mth_occ
	,a.qtr_rept as rept_qtr_occ
	,left(a.qtr_rept,4) as rept_yr_occ
	,a.REPORTED_DATE as occ_rept_date
	,a.REPORTED_DATE as occ_rept_date_act
	,a.mth_rept as rept_mth_ft
	,a.qtr_rept as rept_qtr_ft
	,left(a.qtr_rept,4) as rept_yr_ft
	,a.REPORTED_DATE as ft_rept_date
	,a.Reserving as covg
	,case when a.Reserving = 'ACH' then 'PD'
			when a.Reserving = 'ACL' then 'AircraftLiability'
			when a.Reserving = 'APL' then 'Airport Operations Occurrence'
			end coveragecode
	,case when a.D55_CAT_CODE = 'NULL' or a.D55_CAT_CODE is null then 0
			else 1
			end CAT_indicator
	,a.D55_CAT_CODE as ISOCatNumber
	--,'' as active_claim_feature_count
	,a.clm_status1 as clm_ft_status1
	,a.clm_status2 as clm_ft_status2
	,a.clm_status3 as clm_ft_status3
	,DATEPART(yy,a.date_close_act_kpi) * 100 + DATEPART(mm,a.date_close_act_kpi) as mth_ft_close_act
	,a.clm_status1 as clm_occ_status1
	,a.clm_status2 as clm_occ_status2
	,a.clm_status3 as clm_occ_status3
	,DATEPART(yy,a.date_close_act_kpi) * 100 + DATEPART(mm,a.date_close_act_kpi) as mth_occ_close_act
	,a.date_close_act_kpi date_close_act
	,DATEPART(yy,a.date_reopen_act_kpi) * 100 + DATEPART(mm,a.date_reopen_act_kpi) as mth_occ_reopen_act
	,a.date_reopen_act_kpi date_reopen_act
	,(left(a.mth_val,4)*1-left(a.mth_loss,4)*1)*12 + right(a.mth_val,2)*1 - right(a.mth_loss,2)  mth_age
	,(left(a.qtr_val,4)*1-left(a.qtr_loss,4)*1)*4 + right(a.qtr_val,1)*1 - right(a.qtr_loss,1) qtr_age
	,a.paid_loss as paid_l
	,a.incd_loss as incd_l
	,a.paid_ulae as paid_nlgl
	,a.incd_ulae as incd_nlgl
	,a.paid_alae as paid_a
	,a.incd_alae as incd_a
	,0 as subro
	,0 as salvage
	,(a.net_paid_loss - a.paid_loss) as recovery
	,(a.paid_loss + a.paid_alae) as paid_la
	,(a.paid_loss + a.paid_lae) as paid_llae
	,(a.incd_loss + a.incd_alae) as incd_la
	,(a.incd_loss + a.incd_lae) as incd_llae
	,a.net_paid_loss as net_paid_l
	,a.net_incd_loss as net_incd_l
	,a.net_paid_la
	,(a.net_paid_loss + a.net_paid_lae) as net_paid_llae
	,a.net_incd_la
	,(a.net_incd_loss + a.net_incd_lae) as net_incd_llae
into #apolloloss
from Pricing_AIM.[dbo].[aim_loss_ulae] as a
--left join #apolloinfo as b on a.[policy no] = b.pol_num

--update #apolloloss
--set ISOCatNumber = case when ISOCatNumber is null then 'NULL'	
--							else ISOCatNumber
--							end

alter table #apolloloss
alter column ISOCatNumber varchar(30)


if OBJECT_ID('tempdb.dbo.#apolloloss01') is not null drop table #apolloloss01
select
	a.*
	--,b.CLSId
	,case when b.CLSId in (2,3,13,14) then 1
			else 0
			end is_represented
into #apolloloss01
from #apolloloss as a
left join [HSQ-DB01].[Icarus].[dbo].[Claim Hdr] as b on a.claimcontrol_id = b.clmid and a.[claim_number] = b.[Claim No]

update #apolloloss01
set ISOCatNumber = case when ISOCatNumber = 'NULL' then null
						else ISOCatNumber
						end

-----------------------------------------------------------------------------
--modify diamond loss table

DECLARE @current AS VARCHAR(4), @year AS VARCHAR(2)
Declare @string as varchar(max)
SET @current =  concat(RIGHT('00' + CONVERT(NVARCHAR(2), month(dateadd(month, -1, getdate()))), 2), right(year(dateadd(month, -1, getdate())),2))
SET @year = right(@current, 2)

set @string = replace(replace('
if OBJECT_ID(''Pricing_AIM.[dbo].aim_loss_Diamond'') is not null drop table Pricing_AIM.[dbo].aim_loss_Diamond
select * into Pricing_AIM.[dbo].aim_loss_Diamond from pricing_hspl.[dbo].[auto_hspl_loss_15YY_XXXX]
where reserving in (''APL'',''ACL'',''ACH'')
','XXXX', @current),'YY',@year)

exec(@string)


if OBJECT_ID('tempdb.dbo.#diamondloss') is not null drop table #diamondloss
select 
	'Diamond' as system
	,clm_ft_num
	,claim_number
	,claimcontrol_id
	,claimant_num
	,claimfeature_num
	,reserving
	,policy
	,policy_id
	,company
	,policyimage_num
	,vehicle_num as aircraft_num
	,state_risk
	,yr_loss
	,qtr_loss
	,mth_loss
	,date_loss
	,date_occ_close_act date_occ_close
	,date_ft_close_act date_ft_close
	,mth_cal_earn
	,mth_val
	,qtr_val
	,yr_val
	,qtr_ind
	,yr_ind
	--,'' as mth_cal_earn
	--,'' as qtr_cal_earn
	--,'' as yr_cal_earn
	,rept_mth_occ
	,rept_qtr_occ
	,rept_yr_occ
	,occ_rept_date
	,ent_date occ_rept_date_act
	,rept_mth_ft
	,rept_qtr_ft
	,rept_yr_ft
	,ft_rept_date
	,covg
	,coveragecode
	,CAT_indicator
	,ISOCatNumber
	--,'' as active_claim_feature_count
	,clm_ft_status1
	,clm_ft_status2
	,clm_ft_status3
	,mth_ft_close_act
	,clm_occ_status1
	,clm_occ_status2
	,clm_occ_status3
	,mth_occ_close_act
	,date_occ_close_act date_close_act
	,datepart(yy,date_occ_reopen_act) * 100 + datepart(mm,date_occ_reopen_act) mth_occ_reopen_act
	,date_occ_reopen_act date_reopen_act
	,mth_age
	,qtr_age
	,paid_l
	,incd_l
	,paid_nlgl
	,incd_nlgl
	,paid_a
	,incd_a
	,subro
	,salvage
	,recovery
	,paid_la
	,paid_llae
	,incd_la
	,incd_llae
	,net_paid_l
	,net_incd_l
	,net_paid_la
	,net_paid_llae
	,net_incd_la
	,net_incd_llae
	,is_represented
into #diamondloss
from Pricing_AIM.[dbo].aim_loss_Diamond

update #diamondloss
set ISOCatNumber = case when ISOCatNumber = 'NULL' then null
						else ISOCatNumber
						end
	,mth_occ_close_act = case when mth_occ_close_act is null then 999912
								else mth_occ_close_act
								end
	,date_close_act = case when date_close_act is null then '9999-12-31'
								else date_close_act
								end
	,date_reopen_act = case when date_reopen_act is null then '9999-12-31'
								else date_reopen_act
								end
	,mth_ft_close_act = case when mth_ft_close_act is null then 999912
								else mth_ft_close_act
								end

-----------------------------------------------------------------------------
--combine apollo and diamond loss tables

if OBJECT_ID('pricing_AIM.dbo.AIMLoss') is not null drop table Pricing_AIM.[dbo].AIMLoss


select * 
into pricing_AIM.dbo.AIMLoss
from #apolloloss01
UNION ALL 
select * from #diamondloss

--select * 
--into pricing_AIM.dbo.AIMLoss0725
--from #apolloloss01
--UNION ALL 
--select * from #diamondloss

drop table
#apolloloss
,#apolloloss01
,#diamondloss



DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID)
exec UPDATE_QUERY_TIMES @PROC_NAME, @StartTime
 
END TRY 
BEGIN CATCH 
SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE 
END CATCH
GO


