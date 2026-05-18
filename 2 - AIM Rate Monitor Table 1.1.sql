--Check if tables are updated
select max(eff_date) from pricing_aim.dbo.aim_status_pol
select max(mth_cal_eff) from pricing_aim.dbo.aim_STT



if object_id('tempdb.dbo.#diamond_mapping') is not null drop table #diamond_mapping
select distinct policy_id, renewal_ver, revised_pol_id, revised_pol_renewal_ver into #diamond_mapping from pricing_aim.dbo.aim_status_pol_policy_mapping

if (select count(*) from (
	select system, polid, pol_ed, count(*) ct from pricing_aim.dbo.aim_status_pol group by system, polid, pol_ed having count(*) > 1) a) > 0
	throw 50001,'Duplicate',1

if (select count(*) from (
	select policy_id, renewal_ver, count(*) ct from	#diamond_mapping group by policy_id, renewal_ver having count(*) > 1) a) > 0
	throw 50001,'Duplicate',1

--if (select count(*) from (
--	select revised_pol_id, revised_pol_renewal_ver, count(*) ct from #diamond_mapping group by revised_pol_id, revised_pol_renewal_ver having count(*) > 1) a) > 0
--	throw 50001,'Duplicate',1


if object_id('tempdb.dbo.#temp01') is not null drop table #temp01
--There is a duplication issue in here of 64 records, will need to figure it out eventiually but more interested in getting this through currently
select a.*
,isnull(c.polid,a.policy_id)	 pol_id_ac
,isnull(c.pol_ed,a.pol_edition)	 pol_ed_ac
,cast(isnull(c.eff_date,a.date_pol_eff) as date) eff_date_ac	
,cast(isnull(c.exp_date,a.date_pol_exp) as date)	 exp_date_ac
,datepart(yy,isnull(c.eff_date,a.date_pol_eff))*100+ datepart(mm,isnull(c.eff_date,a.date_pol_eff)) mth_pol_eff_ac
,datepart(yy,isnull(c.exp_date,a.date_pol_exp))*100+ datepart(mm,isnull(c.exp_date,a.date_pol_exp)) mth_pol_exp_ac
,year(isnull(c.eff_date,a.date_pol_eff)) * 10 + ceiling((month(isnull(c.eff_date,a.date_pol_eff)) - 1) / 3) + 1 qtr_pol_eff_ac
,year(isnull(c.eff_date,a.date_pol_eff)) * 10 + ceiling((month(isnull(c.eff_date,a.date_pol_eff)) - 1) / 3) + 1 qtr_pol_exp_ac
,year(isnull(c.eff_date,a.date_pol_eff)) yr_pol_ac
,year(isnull(c.exp_date,a.date_pol_exp)) yr_pol_exp_ac
,1 yr_pol_exp
,c.status_pol_rn	
,c.status_pol_rl	
,c.pol_id_future	 pol_id_ac_future
,c.pol_ed_future	 pol_ed_ac_future
,c.system_future
,cast(isnull(c.polid,a.policy_id) as float) * 100 + cast(isnull(c.pol_ed,a.pol_edition) as float) pol_num_full_clean_ac
,isnull(cast(c.pol_id_future as float)*100 + cast(c.pol_ed_future as float),0) pol_num_full_clean_future_ac
into #temp01
FROM pricing_aim.dbo.aim_STT a
left join #diamond_mapping b on a.policy_id=b.policy_id and a.system='Diamond' and b.renewal_ver=a.pol_edition
left join pricing_aim.dbo.aim_status_pol c on c.system=a.system and c.polid=isnull(b.revised_pol_id,a.policy_id) and c.pol_ed=isnull(b.revised_pol_renewal_ver,a.pol_edition)
where a.policy_id is not null



if object_id('tempdb.dbo.#temp02') is not null drop table #temp02
select pol_id_ac
	  ,pol_num_full_clean_ac
	  ,pol_num_full_clean_future_ac
	  ,cast(eff_date_ac as date) eff_date_ac
      ,cast(exp_date_ac as date) exp_date_ac
      ,mth_pol_eff_ac
      ,mth_pol_exp_ac
      ,status_pol_rl
      ,status_pol_rn
	  ,row_number() over (partition by pol_num_full_clean_future_ac order by status_pol_rl desc) selector_future
	  ,row_number() over (partition by pol_num_full_clean_ac order by status_pol_rn desc) selector_current
into #temp02
FROM #temp01
group by pol_id_ac
	  ,pol_num_full_clean_ac
	  ,cast(eff_date_ac as date)
      ,cast(exp_date_ac as date) 
	  ,mth_pol_eff_ac
      ,mth_pol_exp_ac
      ,status_pol_rl
      ,status_pol_rn
	  ,pol_num_full_clean_future_ac

if object_id('pricing_aim.dbo.rate_monitor_data') is not null drop table pricing_aim.dbo.rate_monitor_data

select 
	  a.*
	,cast(b.eff_date_ac as date) future_date_pol_eff
	,cast(b.exp_date_ac as date)  future_date_pol_exp 
	,b.mth_pol_eff_ac future_mth_eff
	,b.mth_pol_exp_ac future_mth_exp
	,b.status_pol_rl future_status_pol_rl
	,b.status_pol_rn future_status_pol_rn
	,b.pol_num_full_clean_ac pol_num_full_clean_future
	,cast(c.eff_date_ac as date) prior_date_pol_eff
	,cast(c.exp_date_ac as date) prior_date_pol_exp 
	,c.mth_pol_eff_ac prior_mth_eff
	,c.mth_pol_exp_ac prior_mth_exp
	,c.status_pol_rl prior_status_pol_rl
	,c.status_pol_rn prior_status_pol_rn
	,c.pol_num_full_clean_ac prior_pol_num_full_clean
	,year(dateadd(month, -1, getdate())) * 100 + month(dateadd(month, -1, getdate())) mth_val
	into pricing_aim.dbo.rate_monitor_data
	from #temp01 a
left join #temp02 b on b.pol_num_full_clean_ac=a.pol_num_full_clean_future_ac and b.selector_current=1
left join #temp02 c on c.pol_num_full_clean_future_ac=a.pol_num_full_clean_ac and c.selector_future=1


update pricing_aim.dbo.rate_monitor_data
set mth_pol_eff = mth_pol_eff_ac
,mth_pol_exp = mth_pol_exp_ac
,date_pol_exp = exp_date_ac
,date_pol_eff = eff_date_ac
,pol_edition=pol_ed_ac
,policy_id=pol_id_ac
,yr_pol = yr_pol_ac
,yr_pol_exp= yr_pol_exp_ac
,qtr_pol_eff = qtr_pol_eff_ac
,qtr_pol_exp = qtr_pol_exp_ac 


SELECT mth_val
	,sum(expr_flag_where) expr_flag_where
	,sum(expr_pol_ct) expr_pol_ct
	,CASE 
		WHEN prem_written = 0
			AND status_pol_rl = 'Ren'
			THEN 'No Covg'
		ELSE status_pol_rl
		END status_pol_rl
	,mth_pol_exp
	,sum(prem_written) AS prem_written
	,sum(r_adq_written) AS r_adq_written
	,sum(r_adq_tech_written) AS r_adq_tech_written
	,sum(rr_adq_tech_written) AS rr_adq_tech_written
	,sum(rr_adq_tech_annual) AS rr_adq_tech_annual
	,sum(rr_padq_tech_annual) AS rr_padq_tech_annual
	,sum(rr_blpadq_tech_annual) AS rr_blpadq_tech_annual
	,sum([ren flag where]) [ren flag where]
	,sum([ren pol ct]) [ren pol ct]
	,CASE 
		WHEN [ren prem written] = 0
			AND [ren status] = 'Renewal'
			THEN 'No Covg'
		ELSE [ren status]
		END [ren status]
	,isnull([ren mth pol eff], 0) [ren mth pol eff]
	,sum([ren prem written]) [ren prem written]
	,sum([ren r_adq written]) [ren r_adq written]
	,sum([ren r_adq tech written]) [ren r_adq tech written]
	,sum([ren rr_adq tech written]) [ren rr_adq tech written]
	,sum([ren rr_adq tech annual]) [ren rr_adq tech annual]
	,sum([ren rr_padq tech annual]) [ren rr_padq tech annual]
	,sum([ren rr_blpadq tech annual]) [ren rr_blpadq tech annual]
FROM (
	SELECT mth_val
		,pol_num_full_exp
		,sum(expr_flag_where) expr_flag_where
		,sum(expr_pol_ct) expr_pol_ct
		,isnull(status_pol_rl, 'null') status_pol_rl
		,mth_pol_exp
		,sum(prem_written) AS prem_written
		,sum(r_adq_written) AS r_adq_written
		,sum(r_adq_tech_written) AS r_adq_tech_written
		,sum(rr_adq_tech_written) AS rr_adq_tech_written
		,sum(rr_adq_tech_annual) AS rr_adq_tech_annual
		,sum(rr_padq_tech_annual) AS rr_padq_tech_annual
		,sum(rr_blpadq_tech_annual) AS rr_blpadq_tech_annual
		,sum([ren flag where]) [ren flag where]
		,sum([ren pol ct]) [ren pol ct]
		,pol_num_full_clean_future
		,isnull([ren status], 'null') [ren status]
		,isnull([ren mth pol eff], 0) [ren mth pol eff]
		,sum([ren prem written]) [ren prem written]
		,sum([ren r_adq written]) [ren r_adq written]
		,sum([ren r_adq tech written]) [ren r_adq tech written]
		,sum([ren rr_adq tech written]) [ren rr_adq tech written]
		,sum([ren rr_adq tech annual]) [ren rr_adq tech annual]
		,sum([ren rr_padq tech annual]) [ren rr_padq tech annual]
		,sum([ren rr_blpadq tech annual]) [ren rr_blpadq tech annual]
	FROM (
		SELECT a.mth_val
			,a.pol_num_full_clean_ac pol_num_full_exp
			,count(DISTINCT a.pol_num_full_clean) expr_flag_where
			,count(DISTINCT a.pol_num_full_clean) expr_pol_ct
			,a.status_pol_rl
			,a.mth_pol_exp_ac mth_pol_exp
			,sum(a.prem_written) AS prem_written
			,sum(a.r_adq_written) AS r_adq_written
			,sum(a.r_adq_tech_written) AS r_adq_tech_written
			,sum(a.rr_adq_tech_written) AS rr_adq_tech_written
			,sum(a.rr_adq_tech_annual) AS rr_adq_tech_annual
			,sum(a.rr_padq_tech_annual) AS rr_padq_tech_annual
			,sum(a.rr_blpadq_tech_annual) AS rr_blpadq_tech_annual
			,0 [ren flag where]
			,0 [ren pol ct]
			,pol_num_full_clean_future
			,isnull(future_status_pol_rn, 'null') [ren status]
			,isnull(future_mth_eff, 0) [ren mth pol eff]
			,0 [ren prem written]
			,0 [ren r_adq written]
			,0 [ren r_adq tech written]
			,0 [ren rr_adq tech written]
			,0 [ren rr_adq tech annual]
			,0 [ren rr_padq tech annual]
			,0 [ren rr_blpadq tech annual]
		FROM pricing_aim.dbo.rate_monitor_data a
		WHERE a.yr_pol >= 2017
			AND 1 = CASE 
				WHEN a.reserving IN ('ACL')
					THEN 1
				ELSE 0
				END
			AND 1 = 1
			AND 1 = 1
			AND 1 = 1
			AND 1 = 1
			AND 1 = 1
		GROUP BY a.mth_val
			,a.status_pol_rl
			,a.mth_pol_exp_ac
			,isnull(future_mth_eff, 0)
			,isnull(future_status_pol_rn, 'null')
			,a.pol_num_full_clean_ac
			,pol_num_full_clean_future
		
		UNION ALL
		
		SELECT a.mth_val
			,a.prior_pol_num_full_clean
			,0 [expr flag where]
			,0 [expr pol ct]
			,isnull(prior_status_pol_rl, 'Null') [expr status]
			,prior_mth_exp [expr mth pol ex]
			,0 [expr prem written]
			,0 [expr r_adq written]
			,0 [expr r_adq tech written]
			,0 [expr rr_adq tech written]
			,0 [expr rr_adq tech annual]
			,0 [expr rr_padq tech annual]
			,0 [expr rr_blpadq tech annual]
			,count(DISTINCT a.pol_num_full_clean) [ren flag where]
			,count(DISTINCT a.pol_num_full_clean) [ren pol ct]
			,a.pol_num_full_clean_ac
			,a.status_pol_rn
			,a.mth_pol_eff_ac
			,sum(a.prem_written) AS prem_written
			,sum(a.r_adq_written) AS r_adq_written
			,sum(a.r_adq_tech_written) AS r_adq_tech_written
			,sum(a.rr_adq_tech_written) AS rr_adq_tech_written
			,sum(a.rr_adq_tech_annual) AS rr_adq_tech_annual
			,sum(a.rr_padq_tech_annual) AS rr_padq_tech_annual
			,sum(a.rr_blpadq_tech_annual) AS rr_blpadq_tech_annual
		FROM pricing_aim.dbo.rate_monitor_data a
		WHERE a.yr_pol >= 2017
			AND 1 = CASE 
				WHEN a.reserving IN ('ACL')
					THEN 1
				ELSE 0
				END
			AND 1 = 1
			AND 1 = 1
			AND 1 = 1
			AND 1 = 1
			AND 1 = 1
		GROUP BY a.mth_val
			,a.status_pol_rn
			,a.mth_pol_eff_ac
			,isnull(prior_status_pol_rl, 'Null')
			,a.pol_num_full_clean_ac
			,a.prior_pol_num_full_clean
			,prior_status_pol_rl
			,prior_mth_exp
		) a1
	GROUP BY mth_val
		,isnull(status_pol_rl, 'null')
		,mth_pol_exp
		,isnull([ren status], 'null')
		,isnull([ren mth pol eff], 0)
		,pol_num_full_clean_future
		,pol_num_full_exp
	) a2
GROUP BY mth_val
	,CASE 
		WHEN prem_written = 0
			AND status_pol_rl = 'Ren'
			THEN 'No Covg'
		ELSE status_pol_rl
		END
	,mth_pol_exp
	,CASE 
		WHEN [ren prem written] = 0
			AND [ren status] = 'Renewal'
			THEN 'No Covg'
		ELSE [ren status]
		END
	,isnull([ren mth pol eff], 0)
/*
select  * from #temp01
where client_id = 38718986

select  * from #temp02
where pol_id_ac in ('43187518','38855341')

select  * from #temp03
where client_id = 38718986

select top 10 * from #temp01
select top 10 * from #temp02
select top 10 * from #temp03

'ABIDE AVIATION, LLC AND BRYAN LINDSEY'


select expr_insd_name
,expr_pol_num_full
,expr_date_pol_eff
,expr_date_pol_exp
,expr_prem_written
,expr_r_adq_written
,expr_r_adq_tech_written
,expr_rr_adq_tech_written
,case when expr_prem_written = 0 and expr_status = 'Ren' then 'No Covg' else expr_status end expr_status
	
,ren_insd_name
,ren_pol_num_full
,ren_date_pol_eff
,ren_date_pol_exp
,ren_prem_written
,ren_r_adq_written
,ren_r_adq_tech_written
,ren_rr_adq_tech_written
,case when ren_status ='Ren' and ren_prem_written=0 then 'No Covg' else ren_status end ren_status 
from (
Select expr_insd_name
,expr_pol_num_full
,expr_date_pol_eff
,expr_date_pol_exp	
,sum(expr_prem_written) expr_prem_written
,sum(expr_r_adq_written) expr_r_adq_written
,sum(expr_r_adq_tech_written) expr_r_adq_tech_written
,sum(expr_rr_adq_tech_written) expr_rr_adq_tech_written

,expr_status
,ren_insd_name
,ren_pol_num_full
,ren_date_pol_eff
,ren_date_pol_exp
,sum(ren_prem_written) ren_prem_written
,sum(ren_r_adq_written) ren_r_adq_written
,sum(ren_r_adq_tech_written) ren_r_adq_tech_written
,sum(ren_rr_adq_tech_written) ren_rr_adq_tech_written
,ren_status
 FROM (
SELECT a.insd_name_hist AS expr_insd_name 
,a.pol_num_full_clean_ac AS expr_pol_num_full	
,a.date_pol_eff AS expr_date_pol_eff
,a.date_pol_exp AS expr_date_pol_exp	
,sum(a.prem_written) AS expr_prem_written	
,sum(a.r_adq_written) AS expr_r_adq_written

,sum(a.r_adq_tech_written) AS expr_r_adq_tech_written	
,sum(a.rr_adq_tech_written) AS expr_rr_adq_tech_written
,a.status_pol_rl AS expr_status	
,insd_name_hist AS ren_insd_name	
,pol_num_full_clean_future AS ren_pol_num_full

,future_date_pol_eff AS ren_date_pol_eff
, future_date_pol_exp AS ren_date_pol_exp
, 0 AS ren_prem_written 
,0 AS ren_r_adq_written
, 0 AS ren_r_adq_tech_written
, 0 AS ren_rr_adq_tech_written
,future_status_pol_rn AS ren_status
 from pricing_aim.dbo.rate_monitor_data a 
 where a.mth_pol_exp = 202402 and 1 =  case when a.reserving in ('ACL')  then 1 else 0 end  and 1 =  1  and 1 =  1  and 1 =  1  and 1 =  1  and 1 =  1 
group by a.insd_name_hist 
,a.pol_num_full_clean_ac 
,a.date_pol_eff 
,a.date_pol_exp 
,a.status_pol_rl 
,insd_name_hist 
,pol_num_full_clean_future 
,future_date_pol_eff  
,future_date_pol_exp 
,future_status_pol_rn

SELECT insd_name_hist 
,prior_pol_num_full_clean 
,prior_date_pol_eff 
,prior_date_pol_exp 
,0
,0
,0
,0
,prior_status_pol_rl

,insd_name_hist 
,pol_num_full_clean_ac
,date_pol_eff
,date_pol_exp
,sum(prem_written)
,sum(r_adq_written)
,sum(r_adq_tech_written)
,sum(rr_adq_tech_written)
,status_pol_rn
 from pricing_aim.dbo.rate_monitor_data a 
 where a.mth_pol_eff = 202402 and 1 =  case when a.reserving in ('ACL')  then 1 else 0 end  and 1 =  1  and 1 =  1  and 1 =  1  and 1 =  1  and 1 =  1 
group by prior_pol_num_full_clean
,insd_name_hist 
,prior_date_pol_eff
,prior_date_pol_exp
,prior_status_pol_rl
,insd_name_hist
,pol_num_full_clean_ac 
,date_pol_eff
,date_pol_exp 
,status_pol_rn
)a1 group by expr_insd_name
,expr_pol_num_full
,expr_date_pol_eff
,expr_date_pol_exp
,expr_status
,ren_insd_name
,ren_pol_num_full
,ren_date_pol_eff
,ren_date_pol_exp
,ren_status )a2
*/