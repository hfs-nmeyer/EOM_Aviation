


--getting policy information, renewals, rewrites, etc
drop table #temp01,#temp02, #temp02_a,#temp03,#temp04

--apollo information

select polid
,Policyno
,left(Policyno,10) pol_num
,pol_ed
,efdate	
,exdate
,sum(prem_written)  prem_written
,sum(prem_annual)  prem_annual
into #temp01
FROM pricing_aim.dbo.rr_aim_apollo
group by polid
,Policyno
,pol_ed
,pol_num_full_clean
,efdate	
,exdate
,left(Policyno,10)


--Apollo renewal mapping
select a.*
,b.pol_num pol_num_future
,b.pol_ed pol_ed_future 
,b.polid  pol_id_future
into #temp02
FROM #temp01 a 
left join #temp01 b on a.pol_num=b.pol_num and a.pol_ed+1=b.pol_ed
order by a.pol_num, a.pol_ed



--Diamond policy information

select 
client_id
,a.policy_id
,a.policy
,a.renewal_ver
,eff_date
,exp_date
,cancelled
,cancelledon_date
,rewrittenfrom_policy_id
,rewrittenfrom_policy
,legacy_policynumber
,firstwritten_date
,policyimage_num
,sum(premium_chg_written) premium_chg_written
,sum(premium_chg_fullterm) premium_chg_fullterm
into #temp03
FROM [AHI-S06].diamond.dbo.vpolicyimagexml a
left join [AHI-S06].diamond.dbo.ratingversion b on a.ratingversion_id=b.ratingversion_id
left join [AHI-S06].diamond.dbo.version c on c.version_id=b.version_id
left join [AHI-S06].diamond.dbo.companystatelob d on d.companystatelob_id=c.companystatelob_id
left join [AHI-S06].diamond.dbo.companylob e on e.companylob_id=d.companylob_id
left join [AHI-S06].diamond.dbo.lob f on f.lob_id=e.lob_id
left join [AHI-S06].diamond.dbo.policy g on g.policy_id=a.policy_id 
where f.lob_id in (30,31) and policystatuscode_id in (1,3,20)
group by 
client_id
,a.policy_id
,a.policy
,a.renewal_ver
,eff_date
,exp_date
,cancelled
,cancelledon_date
,rewrittenfrom_policy_id
,rewrittenfrom_policy
,legacy_policynumber
,firstwritten_date
,policyimage_num

--mapping apollo to diamond


select polid	
,Policyno	
,pol_num	
,pol_ed	
,efdate	
,exdate	
,prem_written	
,prem_annual
,isnull(b.policy ,a.pol_num_future)   pol_num_future	
,isnull(b.renewal_ver,a.pol_ed_future) pol_ed_future
,isnull(b.policy_id,a.pol_id_future) pol_id_future
,'also' status_pol_rn
,'also' status_pol_rl
into #temp02_a
FROM #temp02 a
left join #temp03 b on a.Policyno=b.legacy_policynumber and b.renewal_ver=1
order by pol_num
,pol_ed

update #temp02_a
set status_pol_rl = case when pol_num_future is null then 'Lost' else 'Ren' end

update #temp02_a
set status_pol_rn = case when pol_ed ='00' then 'New' else 'Ren' end



--mapping the rewritten policies to version rewritten from
select 
a.client_id
,a.policy_id	
,a.policy	
,a.renewal_ver	
,a.eff_date	
,a.exp_date	
,a.cancelled	
,a.cancelledon_date	
,a.firstwritten_date	
,a.rewrittenfrom_policy_id	
,a.rewrittenfrom_policy	
,a.legacy_policynumber
,sum(a.premium_chg_written) premium_written
,sum(a.premium_chg_fullterm) premium_fullterm
,max(b.policyimage_num) rewrite_policyimage_num
,max(cast(b.renewal_ver as int))	 rewrite_renewal_ver
,max(b.eff_date	) rewrite_eff_date
,max(b.exp_date	) rewrite_exp_date
,max(cast(b.cancelled	 as int)) rewrite_cancelled
,max(b.cancelledon_date) rewrite_cancelledon_date
,sum(b.premium_chg_written) rewrite_premium_written
,sum(b.premium_chg_fullterm) rewrite_premium_fullterm
into #temp04
 FROM #temp03 a
left join #temp03 b on a.rewrittenfrom_policy=b.policy and b.cancelledon_date between b.eff_date and b.exp_date and a.eff_date=b.cancelledon_date
group by 
a.client_id
,a.policy_id	
,a.policy	
,a.renewal_ver	
,a.eff_date	
,a.exp_date	
,a.cancelled	
,a.cancelledon_date	
,a.firstwritten_date	
,a.rewrittenfrom_policy_id	
,a.rewrittenfrom_policy	
,a.legacy_policynumber

drop table #temp05

SELECT *
	,datediff(dd, eff_date, exp_date) written_term
	,datediff(dd, rewrite_eff_date, rewrite_cancelledon_date) exp_term
	,11111 as revised_pol_id
	,0 as revised_pol_renewal_ver
	,'2019-01-01' as revised_eff_date
	,'2019-01-01' as revised_exp_date
	into #temp05
FROM #temp04

update #temp05
set revised_pol_id = case when written_term<365 and exp_term<365 then rewrittenfrom_policy_id else policy_id end
update #temp05
set revised_eff_date = case when written_term<365 and exp_term<365 then rewrite_eff_date else eff_date end
update #temp05
set revised_exp_date = exp_date
update #temp05
set revised_pol_renewal_ver = case when written_term<365 and exp_term<365 then rewrite_renewal_ver else renewal_ver end

drop table #temp06

SELECT 
client_id
,revised_pol_id
	,cancelled
	,revised_pol_renewal_ver
	,min(revised_eff_date) revised_eff_date
	,max(revised_exp_date) revised_exp_date
	,max(legacy_policynumber) legacy_policynumber
	,sum(premium_written) prem_written
	,sum(premium_fullterm) prem_fullterm
	into #temp06
FROM #temp05
group by client_id,revised_pol_id
	,revised_pol_renewal_ver,cancelled

	drop table #final

select * into #final 
FROM (
select 'Apollo' System
,NULL as client_id
,polid
,pol_ed	
,efdate eff_date	
,exdate exp_date	
,status_pol_rn	
,status_pol_rl
,pol_id_future
,pol_ed_future
,case when isnull(pol_id_future,0)>=30000000 then 'Diamond' else 'Apollo' end system_future
FROM #temp02_a

union all

select 'Diamond' System
,a.client_id
,a.revised_pol_id
,a.revised_pol_renewal_ver
,a.revised_eff_date
,a.revised_exp_date
,case when a.legacy_policynumber like '%-%' then 'Ren' when a.revised_pol_renewal_ver > 1 then 'Ren' else 'New' end status_pol_rn
,case when a.cancelled = 1 then 'Cncl Pre' when cast(a.revised_exp_date as date)>=DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0) then 'Inf' when b.revised_pol_id is null then 'Lost' else 'Ren' end status_pol_rl
,b.revised_pol_id pol_id_future
,b.revised_pol_renewal_ver pol_ed_future
,'Diamond' system_future
FROM #temp06 a
left join #temp06 b on a.client_id=b.client_id and a.revised_pol_renewal_ver+1=b.revised_pol_renewal_ver
)a



drop table #final_2

select *
,row_number() over (partition by  System,polid,pol_ed,eff_date order by pol_id_future desc) selector
into #final_2
FROM #final

drop table  pricing_aim.dbo.aim_status_pol

select distinct * into pricing_aim.dbo.aim_status_pol FROM #final_2 where selector=1

drop table pricing_aim.dbo.aim_status_pol_policy_mapping

select * into pricing_aim.dbo.aim_status_pol_policy_mapping FROM #temp05
