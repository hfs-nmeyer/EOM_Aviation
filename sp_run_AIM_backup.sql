USE [Pricing_AIM]
GO

/****** Object:  StoredProcedure [dbo].[run_AIM_Backup]    Script Date: 5/18/2026 2:15:41 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[run_AIM_Backup]
AS
BEGIN TRY	
declare @startTime datetime = getdate()


--Saves the prior months tables
DECLARE @current AS VARCHAR(4), @prior AS VARCHAR(4), @2prior AS VARCHAR(4)
Declare @string as varchar(max)
SET @prior =  concat(RIGHT('00' + CONVERT(NVARCHAR(2), month(dateadd(month, -2, getdate()))), 2), right(year(dateadd(month, -2, getdate())),2))
SET @2prior =  concat(RIGHT('00' + CONVERT(NVARCHAR(2), month(dateadd(month, -3, getdate()))), 2), right(year(dateadd(month, -3, getdate())),2))


--These tables never saved prior versions. Probably due to space
--pricing_aim.dbo.aim_r_ac_final_2
--pricing_aim.dbo.aim_r_ap_final_2
--Pricing_AIM.[dbo].[DiamondEarnedPremium_Aviation_JChenVScopy]


--Delete the prior 2 months' tables
set @string = 
replace('
IF OBJECT_ID(''pricing_aim.dbo.pnl_ep_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.pnl_ep_XXXX
IF OBJECT_ID(''pricing_aim.dbo.pnl_wp_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.pnl_wp_XXXX
IF OBJECT_ID(''pricing_aim.dbo.aim_loss_ulae_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.aim_loss_ulae_XXXX
IF OBJECT_ID(''pricing_aim.dbo.AIMLoss_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.AIMLoss_XXXX
IF OBJECT_ID(''pricing_aim.dbo.DiaAPCovg_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.DiaAPCovg_XXXX
IF OBJECT_ID(''pricing_aim.dbo.diamond_data_aim_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.diamond_data_aim_XXXX
IF OBJECT_ID(''pricing_aim.dbo.aim_diamond_STT_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.aim_diamond_STT_XXXX
IF OBJECT_ID(''pricing_aim.dbo.aim_STT_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.aim_STT_XXXX
','XXXX',@2prior)

exec(@string)

--Incase we need to reset the prior month's tables
set @string = replace('
IF OBJECT_ID(''pricing_aim.dbo.pnl_ep_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.pnl_ep_XXXX
IF OBJECT_ID(''pricing_aim.dbo.pnl_wp_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.pnl_wp_XXXX
IF OBJECT_ID(''pricing_aim.dbo.aim_loss_ulae_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.aim_loss_ulae_XXXX
IF OBJECT_ID(''pricing_aim.dbo.AIMLoss_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.AIMLoss_XXXX
IF OBJECT_ID(''pricing_aim.dbo.DiaAPCovg_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.DiaAPCovg_XXXX
IF OBJECT_ID(''pricing_aim.dbo.diamond_data_aim_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.diamond_data_aim_XXXX
IF OBJECT_ID(''pricing_aim.dbo.aim_diamond_STT_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.aim_diamond_STT_XXXX
IF OBJECT_ID(''pricing_aim.dbo.aim_STT_XXXX'') IS NOT NULL
	drop table pricing_aim.dbo.aim_STT_XXXX
','XXXX',@prior)

exec(@string)

--Save the prior month's tables
set @string = replace('
select * into pricing_aim.dbo.pnl_ep_XXXX from pricing_aim.dbo.pnl_ep
select * into pricing_aim.dbo.pnl_wp_XXXX from pricing_aim.dbo.pnl_wp
select * into pricing_aim.dbo.aim_loss_ulae_XXXX from pricing_aim.dbo.aim_loss_ulae
select * into pricing_aim.dbo.AIMLoss_XXXX from pricing_aim.dbo.AIMLoss
select * into pricing_aim.dbo.DiaAPCovg_XXXX from pricing_aim.dbo.DiaAPCovg
select * into pricing_aim.dbo.diamond_data_aim_XXXX from pricing_aim.dbo.diamond_data_aim
select * into pricing_aim.dbo.aim_diamond_STT_XXXX from pricing_aim.dbo.aim_diamond_STT
select * into pricing_aim.dbo.aim_STT_XXXX from pricing_aim.dbo.aim_STT
','XXXX',@prior)

exec(@string)

DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID)
exec UPDATE_QUERY_TIMES @PROC_NAME, @StartTime
 
END TRY 
BEGIN CATCH 
SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE 
END CATCH
GO


