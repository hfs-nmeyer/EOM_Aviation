USE [Pricing_AIM]
GO

/****** Object:  StoredProcedure [dbo].[run_AIM_Apollo_Loss]    Script Date: 5/18/2026 2:21:12 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[run_AIM_Apollo_Loss]
AS
BEGIN TRY	
declare @startTime datetime = getdate()

--SERVER: HSQ-DB01
--USE NPC_AIM

declare @ed date = dateadd(d,-1,datefromparts(year(GETDATE()),month(GETDATE()),1))
-- Date is Inclusive, use 3/31
----------------------------------------------------------------------------------------------------
-- USER-CREATED TABLES
----------------------------------------------------------------------------------------------------
-- Create valuations for building a triangle

--- All Dates Collect Inforce Dates and Start Dates 
declare @i int = 0
declare @j int = 1999
declare @cmnd varchar(max)

IF OBJECT_ID('tempdb..#triangle') IS NOT NULL
		DROP TABLE #triangle
create table #triangle (mth_val integer)

while @j< 2026 begin
set @i = 1
while @i<(case when @j=datepart(yy,getdate()) then datepart(mm,getdate()) else 13 end) begin 
set @cmnd = 'insert into #triangle (mth_val) values (''XX'')'
set @cmnd = Replace(replace(@cmnd,'XX',@i),@i,@j*100+@i) 
Exec (@cmnd)
set @i += 1
end
set @j +=1
end 


IF OBJECT_ID('tempdb..#tblCoverages') IS NOT NULL
		DROP TABLE #tblCoverages
SELECT 
		PolID
	,	AircraftID
	,	SUM(CASE
			WHEN CVID IN (33,34,35,39)			--AIRCRAFT_HULL COVERAGES
			THEN 1
			ELSE 0
		END)									AS AIRCRAFT_HULL_CVG 
	,	SUM(CASE
			WHEN CVID IN (33,34,35,39)			--AIRCRAFT_HULL COVERAGES
			THEN 
				CASE
					WHEN Premium IS NULL
					THEN 0
					ELSE Premium
				END
			ELSE 0
		END)									AS AIRCRAFT_HULL_PREMIUM 
	,	SUM(CASE
			WHEN CVID IN (26,28,31,40)			--AIRCRAFT_LIAB COVERAGES
			THEN 1
			ELSE 0
		END)										AS AIRCRAFT_LIAB_CVG
	,	SUM(CASE
			WHEN CVID IN (26,28,31,40)			--AIRCRAFT_LIAB COVERAGES
			THEN 
				CASE
					WHEN Premium IS NULL
					THEN 0
					ELSE Premium
				END
			ELSE 0
		END)								AS AIRCRAFT_LIAB_PREMIUM
	,	SUM(CASE
			WHEN CVID IN (16,23)			--AIRPORT_LIAB COVERAGES
			THEN 1
			ELSE 0
		END)										AS AIRPORT_LIAB_CVG
	,	SUM(CASE
			WHEN CVID IN (16,23)			--AIRPORTT_LIAB COVERAGES
			THEN 
				CASE
					WHEN Premium IS NULL
					THEN 0
					ELSE Premium
				END
			ELSE 0
		END)								AS AIRPORT_LIAB_PREMIUM
	,	SUM(CASE
			WHEN CVID IN (32)				--MEDPAY COVERAGES
			THEN 1
			ELSE 0
		END)									AS MEDPAY_CVG
	,	SUM(CASE
			WHEN CVID IN (32)				--MEDPAY COVERAGES
			THEN 
				CASE
					WHEN Premium IS NULL
					THEN 0
					ELSE Premium
				END
			ELSE 0
		END)									AS MEDPAY_PREMIUM
INTO #tblCoverages 
FROM
[HSQ-DB01].[NPC_AIM].dbo.tblCoverages
GROUP BY PolID
	,	AircraftID


--POLICY DATA

IF OBJECT_ID('tempdb..#AIRCRAFT_Policy_Sub') IS NOT NULL
		DROP TABLE #AIRCRAFT_Policy_Sub
SELECT	TA.PolID
	,	TP.PolicyNo
	,	CONVERT(VARCHAR(12),TP.EfDate, 101) AS EfDate
	,	CONVERT(VARCHAR(12),TP.ExDate, 101) AS ExDate
	,	MONTH(TP.efdate)											AS EfDateMonth		
	,	Year(TP.efdate)												AS EfDateYear
	,	TP.StatID
	,	TPS.[Status]
	,	TA.[Action]
	,	TA.AircraftID
	,	TA.FAANo
	,	TA.Yr
	,	TAM.ModelID
	,	TAM.ModelCode
	,	TAM.Model
	,	TP.PrimaryUseID												AS TP_PRIMARYUSEID
	,	TA.PrimaryUseID												AS TA_PRIMARYUSEID
	,	TAM.Category												AS AircraftType
	,	TAM.Gear
	,	TAM.Wing
	,	TAT.[Type]														AS AircraftTypeName		
	,	convert(varchar,TAM.Category) + ' - ' + TAT.[Type]				AS AircraftTypeNameDisplay	
	,	TA.HullAge
	,	TA.AgreedValue													AS HullValue_AgreedValue
	,	TA.AnnualHullPrem
	,	TA.PREMIUM
	,	C.AIRCRAFT_HULL_PREMIUM
	,	C.AIRCRAFT_LIAB_PREMIUM
	,	C.MEDPAY_PREMIUM
	,	C.AIRCRAFT_HULL_CVG
	,	C.AIRCRAFT_LIAB_CVG
	,	C.MEDPAY_CVG
	,	TA.IsManual
	,	TP.PPolID
	,	CASE
			WHEN TE.EntityName LIKE '%TRUST%' or TE.EntityName LIKE '%ESTATE%' or TE.EntityName LIKE '%NONE%' or TE.EntityName IS NULL
			THEN 'Individual'
			ELSE 'Corporation'
		END									AS ENTITY_TYPE
		,TE.EntityName
	--,	TU.UsageCd
	--,	TU.[Description]					AS USAGE_DESC
	,	PROD.Company						AS AGENCY
	,	CASE
			WHEN PRI.PriorityId IN (1,4)	--1=NEW PURCHASE, 4=NEW OPERATION (FOR AIRPORT GL)
			THEN 'NEW'
			ELSE 'RENEWAL'
		END									AS [PRIORITY]
	, UW
	, SourceID									--SOURCEID=8 MEADOWBROOK
	, ProgramID
	, CarrierID
	,EntryNote
INTO #AIRCRAFT_Policy_Sub

FROM [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS TP
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS TA 
	ON TP.PolID = TA.PolID
LEFT JOIN [HSQ-DB01].NPC_AIM.dbo.tlkPolicyStatus  AS TPS	
	ON TP.StatID = TPS.StatID
LEFT JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels as TAM 
	ON TA.ModelID = TAM.ModelID
LEFT JOIN [HSQ-DB01].NPC_AIM.dbo.tlkAircraftTypes AS TAT	
	ON TAM.Category = TAT.ID	
LEFT JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkEntity] AS TE
	ON TP.EntityID=TE.EntityID
LEFT JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tblProds] AS PROD
	ON TP.ProdID=PROD.ProdID
LEFT JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkPriority] AS PRI
	ON TP.PriorityID=PRI.PriorityId
LEFT JOIN #tblCoverages AS C
	ON TP.PolID=C.PolID AND TA.AircraftID=C.AircraftID
WHERE  
 ((TP.StatID >= 6)
AND TP.PolID <> 285191
--AND TA.AIRCRAFTID=395141)
) 
OR TP.PolicyNo='GA99-32936-00'			--SYSTEM HAS INCORRECT STATUS ID
ORDER BY TP.EfDate DESC




IF OBJECT_ID('tempdb..#FAANo_AIRCRAFTTYPE_NULL_UPDATE') IS NOT NULL
		DROP TABLE #FAANo_AIRCRAFTTYPE_NULL_UPDATE
SELECT DISTINCT TA.FAANo, TAM.Category AS AIRCRAFTTYPE, TAM.ModelID, ModelCode, Model, Gear, Wing 
INTO #FAANo_AIRCRAFTTYPE_NULL_UPDATE
FROM  [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS TA 
LEFT JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels as TAM 
	ON TA.ModelID = TAM.ModelID
WHERE Category IS NOT NULL


UPDATE A
SET A.ModelID = F.ModelID
FROM #AIRCRAFT_Policy_Sub AS A
INNER JOIN #FAANo_AIRCRAFTTYPE_NULL_UPDATE AS F
ON A.FAANo=F.FAANo
WHERE A.ModelID IS NULL AND A.AircraftType IS NULL

UPDATE A
SET A.ModelCode = F.ModelCode
FROM #AIRCRAFT_Policy_Sub AS A
INNER JOIN #FAANo_AIRCRAFTTYPE_NULL_UPDATE AS F
ON A.FAANo=F.FAANo
WHERE A.ModelCode IS NULL AND A.AircraftType IS NULL

UPDATE A
SET A.Model = F.Model
FROM #AIRCRAFT_Policy_Sub AS A
INNER JOIN #FAANo_AIRCRAFTTYPE_NULL_UPDATE AS F
ON A.FAANo=F.FAANo
WHERE A.Model IS NULL AND A.AircraftType IS NULL

UPDATE A
SET A.Gear = F.Gear
FROM #AIRCRAFT_Policy_Sub AS A
INNER JOIN #FAANo_AIRCRAFTTYPE_NULL_UPDATE AS F
ON A.FAANo=F.FAANo
WHERE A.Gear IS NULL AND A.AircraftType IS NULL

UPDATE A
SET A.Wing = F.Wing
FROM #AIRCRAFT_Policy_Sub AS A
INNER JOIN #FAANo_AIRCRAFTTYPE_NULL_UPDATE AS F
ON A.FAANo=F.FAANo
WHERE A.Wing IS NULL AND A.AircraftType IS NULL

UPDATE A
SET A.AircraftType = F.AIRCRAFTTYPE
FROM #AIRCRAFT_Policy_Sub AS A
INNER JOIN #FAANo_AIRCRAFTTYPE_NULL_UPDATE AS F
ON A.FAANo=F.FAANo
WHERE A.AircraftType IS NULL


IF OBJECT_ID('tempdb..#FAANo_AIRCRAFTTYPE_UPDATE_LATEST') IS NOT NULL
		DROP TABLE #FAANo_AIRCRAFTTYPE_UPDATE_LATEST

select A.FAANo, A.AircraftType, A.EfDate
INTO #FAANo_AIRCRAFTTYPE_UPDATE_LATEST
from 
(
select distinct faano, AircraftType, EfDate from #AIRCRAFT_Policy_Sub
where faano in (select FAANo from (select distinct FAANo, AircraftType from #AIRCRAFT_Policy_Sub) as x group by FAANo having count(*)>1) 
) AS A
INNER JOIN 
(
select distinct faano,MAX(EfDate) AS EfDate from #AIRCRAFT_Policy_Sub
where faano in (select FAANo from (select distinct FAANo, AircraftType from #AIRCRAFT_Policy_Sub) as  x group by FAANo having count(*)>1)
GROUP BY FAANo 
) AS B
ON A.FAANo=B.FAANo AND A.EfDate=B.EfDate
order by 3 desc


UPDATE A
SET A.AircraftType = F.AIRCRAFTTYPE
FROM #AIRCRAFT_Policy_Sub AS A
INNER JOIN #FAANo_AIRCRAFTTYPE_UPDATE_LATEST AS F
ON A.FAANo=F.FAANo



IF OBJECT_ID('tempdb..#AIRCRAFT_USAGE_LATEST') IS NOT NULL
		DROP TABLE #AIRCRAFT_USAGE_LATEST
select AircraftID, MAX(AIRCRAFTUSAGEID) AS MAX_AircraftUsageID
INTO #AIRCRAFT_USAGE_LATEST
FROM [HSQ-DB01].[NPC_AIM].[dbo].[tblAircraftUsage] AS TAU
LEFT JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkUsage] AS TU
	ON TAU.UsageID=TU.UsageID
WHERE AircraftID IN (SELECT DISTINCT AircraftID FROM #AIRCRAFT_Policy_Sub)
GROUP BY AircraftID





IF OBJECT_ID('tempdb..#DISTINCT_tlkUsage') IS NOT NULL
		DROP TABLE #DISTINCT_tlkUsage
SELECT DISTINCT TAU.AircraftID, TU.UsageID, TU.UsageCd, TU.[Description] AS Usage_Description, TU.PrimaryUseId AS Usage_PrimaryUseID
INTO #DISTINCT_tlkUsage
FROM [HSQ-DB01].[NPC_AIM].[dbo].[tblAircraftUsage] AS TAU
LEFT JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkUsage] AS TU
	ON TAU.UsageID=TU.UsageID
INNER JOIN #AIRCRAFT_USAGE_LATEST AS AU
	ON TAU.AircraftID=AU.AircraftID AND TAU.AircraftUsageID=AU.MAX_AircraftUsageID

IF OBJECT_ID('tempdb..#AIRCRAFT_SPECIAL_USE_ONLY') IS NOT NULL
		DROP TABLE #AIRCRAFT_SPECIAL_USE_ONLY
SELECT P.*, TU.UsageID, TU.UsageCd, TU.Usage_Description 
INTO #AIRCRAFT_SPECIAL_USE_ONLY
FROM #AIRCRAFT_Policy_Sub AS P
LEFT JOIN #DISTINCT_tlkUsage AS TU
	ON P.AircraftID=TU.AircraftID 
WHERE TU.Usage_PrimaryUseId=3
ORDER BY 1 DESC





IF OBJECT_ID('tempdb..#FAANo_MAX_AIRCRAFTID') IS NOT NULL
		DROP TABLE #FAANo_MAX_AIRCRAFTID
SELECT FAANO, MAX(AircraftID) AS AircraftID
INTO #FAANo_MAX_AIRCRAFTID
FROM [HSQ-DB01].[NPC_AIM].dbo.tblAircraft
GROUP BY FAANo

DELETE FROM #FAANo_MAX_AIRCRAFTID
WHERE FAANO=''

ALTER TABLE #FAANo_MAX_AIRCRAFTID
ADD PolID INT, PolicyNo NVARCHAR(30), StatID REAL



UPDATE F
SET F.PolID = A.PolID
FROM #FAANo_MAX_AIRCRAFTID AS F
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS A
ON F.AircraftID=A.AircraftID


UPDATE F
SET F.PolicyNo = P.PolicyNo
FROM #FAANo_MAX_AIRCRAFTID AS F
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P
ON F.PolID=P.PolID

UPDATE F
SET F.StatID = P.StatID
FROM #FAANo_MAX_AIRCRAFTID AS F
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P
ON F.PolID=P.PolID


IF OBJECT_ID('tempdb..#INSURED_POLID') IS NOT NULL
		DROP TABLE #INSURED_POLID

SELECT DISTINCT I.SubID, I.Insured, PolID, PPolID
INTO #INSURED_POLID
FROM [HSQ-DB01].[NPC_AIM].dbo.tblInsureds AS I
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P
ON I.SubID=P.SubID
ORDER BY 1


IF OBJECT_ID('tempdb..#ProbableCause') IS NOT NULL
		DROP TABLE #ProbableCause

CREATE TABLE #ProbableCause					
(					
	PcId int,				
	PcCode varchar(3),				
	PcReasonGroup varchar(100),				
	PcReason varchar(100)				
)					
					
insert into #ProbableCause					
values					
	(1,100,'GNIM','Weather (Wind.Tornado.Hurr.)'),				
	(2,101,'GNIM','Weather (Hail)'),				
	(3,102,'GNIM','Weather (Flood)'),				
	(4,103,'GNIM','Theft or Vandalism'),				
	(5,104,'GNIM','Third Party Negligence'),				
	(6,105,'GNIM','Fire or Explosion (Hostile)'),				
	(7,106,'GNIM','Fire or Explosion (Accidental)'),				
	(8,107,'GNIM','Fire or Explosion (Arson)'),				
	(9,108,'GNIM','Towing Damage'),				
	(10,109,'GNIM','Other'),				
	(11,200,'TAXI','Collision with other Aircraft'),				
	(12,201,'TAXI','Collision with other Vehicles'),				
	(13,202,'TAXI','Collision with Ground Structures'),				
	(14,203,'TAXI','Collision with Person'),				
	(15,204,'TAXI','Prop Strike'),				
	(16,205,'TAXI','Other'),				
	(17,300,'TAKEOFF','Loss of Directional Control'),				
	(18,301,'TAKEOFF','Collision with Objects/Animals'),				
	(19,302,'TAKEOFF','Departure Stall on Takeoff'),				
	(20,400,'FLIGHT','Stall and/or Spin'),				
	(21,401,'FLIGHT','Loss of Control (VFR)'),				
	(22,402,'FLIGHT','Loss of Control (IMC)'),				
	(23,403,'FLIGHT','Continued VFR Flight Into IMC'),				
	(24,404,'FLIGHT','Weather (Tstorm.Lightning.Hail)'),				
	(25,405,'FLIGHT','Weather (Icing)'),				
	(26,406,'FLIGHT','Fuel Exhaustion or Starvation'),				
	(27,407,'FLIGHT','Collision with other Aircraft'),				
	(28,408,'FLIGHT','Collision with Structures'),				
	(29,409,'FLIGHT','Collision with Birds'),				
	(30,410,'FLIGHT','Engine Failure (Mechanical)'),				
	(31,411,'FLIGHT','Engine Failure (Induced)'),				
	(32,412,'FLIGHT','Engine Component Failure'),				
	(33,413,'FLIGHT','Aircraft Component Failure'),				
	(34,414,'FLIGHT','Aircraft Structural Failure'),				
	(35,415,'FLIGHT','Controlled Flight into Terrain'),				
	(36,416,'FLIGHT','Other'),				
	(37,500,'LANDING','Hard Landing'),				
	(38,501,'LANDING','Loss of Directional Control'),				
	(39,502,'LANDING','Undershoot / Overshoot'),				
	(40,503,'LANDING','Gear Up'),				
	(41,504,'LANDING','Gear Failure / Collapse'),				
	(42,505,'LANDING','Improper IAP (DH / MDA)'),				
	(43,506,'LANDING','Improper IAP (Missed Approach)'),				
	(44,507,'LANDING','Go Around / Abort'),				
	(45,508,'LANDING','Precautionary - Off Airport'),				
	(46,509,'LANDING','Forced Landing Off Airport'),				
	(47,510,'LANDING','Other'),				
	(48,600,'OTHER','Premises'),				
	(49,601,'OTHER','Products & Completed Ops'),				
	(50,602,'OTHER','Hangarkeepers'),				
	(51,603,'OTHER','General Liability'),				
	(52,700,'CFI','Inadequate Supervision'),				
	(53,206,'TAXI','Engine Fire During Start'),				
	(54,303,'TAKEOFF','Other'),				
	(55,110,'GNIM','Hurricane CHARLEY'),				
	(56,111,'GNIM','Hurricane FRANCES'),				
	(57,112,'GNIM','Hurricane IVAN'),				
	(58,113,'GNIM','Hurricane JEANNE'),				
	(59,114,'GNIM','Hurricane KATRINA'),				
	(60,115,'GNIM','Hurricane RITA'),				
	(61,116,'GNIM','Hurricane WILMA'),				
	(62,117,'GNIM','Hurricane DOLLY'),				
	(63,118,'GNIM','Hurricane GUSTAV'),				
	(64,119,'GNIM','Hurricane IKE'),				
	(65,120,'GNIM','HURRICANE SANDY 2012'),				
	(67,207,'TAXI','FOD Ingestion'),				
	(68,121,'GNIM','Hurricane MATTHEW'),				
	(69,304,'TAKEOFF','Engine Failure'),				
	(71,122,'GNIM','Hurricane HARVEY'),				
	(72,123,'GNIM','Hurricane IRMA'),				
	(73,124,'GNIM','Hurricane NATE')	
	

IF OBJECT_ID('tempdb..#Claims_with_FAANo_Typos') IS NOT NULL
		DROP TABLE #Claims_with_FAANo_Typos

CREATE TABLE #Claims_with_FAANo_Typos (
   ClmId           INT 
  ,Policy_No       VARCHAR(13)
  ,Aircraft_ID     VARCHAR(8)
  ,CLAIM_TYPE_DESC VARCHAR(3)
  ,DOL             DATE 
  ,PolicyNo        VARCHAR(13)
  ,FAANo           VARCHAR(8)
);
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3898,'GA99-34045-01','N38778Y','ACH','6/24/2014','GA99-34045-01','N3878Y');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3813,'GA99-29254-03','N325W','ACH','1/19/2014','GA99-29254-03','N315W');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3559,'GA99-33449-00','N380KS','ACH','10/8/2012','GA99-33449-00','N380KC');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3469,'GA99-28363-02','N3132Y','ACH','5/17/2012','GA99-28363-02','N3132V');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3314,'GA99-30876-00','N960WN','ACH','8/18/2011','GA99-30876-00','N960WM');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3293,'GA99-27693-02','N3237D','ACH','7/8/2011','GA99-27693-02','N3237P');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3153,'GA99-28969-01','N2835H','ACH','1/16/2011','GA99-28969-01','N2853H');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (2972,'GA96-28811-00','N74TM','ACH','4/22/2010','GA96-28811-00','N74EM');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (2877,'GA99-22893-02','N4735D','ACH','10/25/2009','GA99-22893-02','N4753D');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (2753,'GA99-26804-00','N740E','ACH','4/23/2009','GA99-26804-00','N7409E');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (2315,'GA99-24767-00','N8931L','ACH','9/3/2007','GA99-24767-00','N8139L');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (2115,'GA96-20842-00','N332SX','ACH','12/16/2006','GA96-20842-00','N32SX');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1902,'GA96-21230-00','N7617N','ACH','4/19/2006','GA96-21230-00','N6717N');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1898,'GA96-18521-01','N95219','ACH','4/17/2006','GA96-18521-01','N95129');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1745,'GA96-18210-00','N3372G','ACH','10/24/2005','GA96-18210-00','N3372Q');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1724,'GA96-19449-00','N113AV','ACH','9/30/2005','GA96-19449-00','N113AW');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1673,'GA96-19244-00','N4274U','ACH','8/18/2005','GA96-19244-00','N4274Y');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1662,'GA96-18275-00','N3840G','ACH','8/9/2005','GA96-18275-00','N3840Q');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1630,'GA96-20062-00','N86BA','ACH','7/12/2005','GA96-20062-00','N96BA');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1459,'GA96-17106-00','N20592','ACH','12/5/2004','GA96-17106-00','N30592');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1714,'GA96-13105-00','N217SA','ACH','8/25/2004','GA96-13105-00','N2175A');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1268,'GA96-12179-00','N298JW','ACH','6/24/2004','GA96-12179-00','N198JW');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (1088,'GA96-11058-00','N747LE','ACH','12/8/2003','GA96-11058-00','N747LF');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (755,'GA94-09536-00','N4854E','ACH','12/16/2002','GA94-09536-00','N4864E');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (715,'GA94-06452-00','N9692T','ACH','10/20/2002','GA94-06452-00','N9296T');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (763,'GA96-07906-00','N77975N','ACH','10/3/2002','GA96-07906-00','N7975N');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (569,'GA94-06065-00','N6698W','ACH','5/9/2002','GA94-06065-00','N6689W');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (558,'GA96-05474-00','N4659V','ACH','4/19/2002','GA96-05474-00','N4659B');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (508,'GA94-04533-00','N2690E','ACH','2/19/2002','GA94-04533-00','N2609E');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (422,'GA96-05087-00','N6935A','ACH','8/25/2001','GA96-05087-00','N6539A');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (839,'GA94-03736-00','N6276W','ACH','7/21/2001','GA94-03736-00','N6928X');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (368,'GA94-03666-00','N6488W','ACH','6/8/2001','GA94-03666-00','N6588W');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (351,'GA94-03648-00','N277TY','ACH','5/24/2001','GA94-03648-00','N277TV');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (277,'GA94-02176-00','N71789','ACH','3/16/2001','GA94-02176-00','N51789');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (90,'GA94-02715-00','N6375G','ACH','2/9/2001','GA94-02715-00','N63759');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (57,'GA94-02957-00','N16609','ACH','11/26/2000','GA94-02957-00','N18609');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (47,'GA94-01077-00','N2608T','ACH','11/10/2000','GA94-01077-00','N2068T');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3898,'GA99-34045-01','N38778Y','ACL','6/24/2014','GA99-34045-01','N3878Y');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3375,'GA99-23432-04','N90QL','ACL','12/2/2011','GA99-23432-04','N49CH');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3201,'GA99-23043-04','N28WY','ACL','4/6/2011','GA99-23043-04','N125WY');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3099,'GA99-30644-00','N3051L','ACL','10/1/2010','GA99-30644-00','  N3051L');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (3026,'GA99-29511-00','N7700','ACL','6/26/2010','GA99-29511-00','N7700V');
INSERT INTO #Claims_with_FAANo_Typos(ClmId,Policy_No,Aircraft_ID,CLAIM_TYPE_DESC,DOL,PolicyNo,FAANo) VALUES (4036,'GA99-35616-00', 'Cessna','ACH','03/30/2015','GA99-35616-00','N738AY');


IF OBJECT_ID('tempdb..#Claims_with_No_Aircrafttype') IS NOT NULL
		DROP TABLE #Claims_with_No_Aircrafttype

CREATE TABLE #Claims_with_No_Aircrafttype (
   [Claim No]      VARCHAR(255) 
  ,FAANo	       VARCHAR(7)
  ,Aircrafttype    INT
  ,ModelCode	VARCHAR(255)
  ,Model        VARCHAR(255) 
  ,Gear			VARCHAR(255)
  ,Wing         VARCHAR(255)
);
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES ('CA22287','N1031U','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA20228','N1036V','1','CE172XP','R172K','T','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA22350','N1070U','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA24228','N135LE','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA25273','N135LE','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA22261','N14SS','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA23372','N14SS','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA24389','N15886','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA25298','N16573','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA20253','N238Z','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA26341','N31982','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA25385','N333SE','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA21136','N38844','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA21240','N38844','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA23282','N39794','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA23414','N39794','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA25161','N42752','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA25420','N43397','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA26108','N4495T','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA24130','N44LJ','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA27262','N56000','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA25129','N56880','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA23375','N680WS','12','AC680FL','680FL','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA21165','N6961F','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA26132','N8222B','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA27107','N8231D','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA21284','N92SA','10','PA34200I','PA34 200','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA29124','N8047C','11','PA34200II','PA34 200T','R','Fixed');
INSERT INTO #Claims_with_No_Aircrafttype([Claim No],FAANo,Aircrafttype,ModelCode,Model,Gear,Wing) VALUES('CA27188','N92993','14','HILL12C','UH 12C','S','Rotor');



IF OBJECT_ID('tempdb..#CLAIMS_SUB') IS NOT NULL
		DROP TABLE #CLAIMS_SUB
SELECT
CH.[Claim No] 
,	cd.ClmDtlId
		,	CH.CLMID
		,	CD.CId														AS CLAIM_TYPE
		,	PCId1
		,[Tre Code] treaty_id
			,[Policy No]		
			, CASE
					WHEN F.ClmId IS NOT NULL
					THEN F.FAANo
					ELSE CH.[Aircraft ID]
			END															AS [Aircraft ID]
		,	CASE										
				WHEN CD.CId=1
				THEN 'ACH'
				WHEN CD.CId=2
				THEN 'ACL'
				WHEN CD.CId=3
				THEN 'APL'		
			END															AS	CLAIM_TYPE_DESC
		,	CONVERT(varchar(12),CH.DOL, 101)							AS DOL
		,	YEAR(CH.DOL)												AS AccYear
		,	CASE
				WHEN MONTH(CH.DOL) <=6
				THEN CONCAT(CAST(YEAR(CH.DOL) AS VARCHAR(4)),'-1')
				ELSE CONCAT(CAST(YEAR(CH.DOL) AS VARCHAR(4)),'-2')
			END															AS AccHalfYear
		,	CASE
				WHEN MONTH(CH.DOL) <=3
				THEN 1
				WHEN MONTH(CH.DOL) <=6
				THEN 2
				WHEN MONTH(CH.DOL) <=9
				THEN 3
				ELSE 4
			END															AS AccQuarter
		,	MONTH(CH.DOL)												AS AccMonth
		,	CONVERT(varchar(12),cd.[Trans Date], 101)					AS TRANS_DATE
		,	YEAR(cd.[Trans Date])										AS TransYear
		,	CASE
				WHEN MONTH(cd.[Trans Date]) <=6
				THEN CONCAT(CAST(YEAR(cd.[Trans Date]) AS VARCHAR(4)),'-1')
				ELSE CONCAT(CAST(YEAR(cd.[Trans Date]) AS VARCHAR(4)),'-2')
			END															AS TransHalfYear
		,	CASE
				WHEN MONTH(cd.[Trans Date]) <=3
				THEN 1
				WHEN MONTH(cd.[Trans Date]) <=6
				THEN 2
				WHEN MONTH(cd.[Trans Date]) <=9
				THEN 3
				ELSE 4
			END															AS TransQuarter
		,	MONTH(cd.[Trans Date])										AS TransMonth
		,	CONVERT(varchar(12),CH.Reported, 101)						AS REPORTED_DATE
		,	YEAR(CH.Reported)											AS ReportedYear
		,	CASE
				WHEN MONTH(CH.Reported) <=6
				THEN CONCAT(CAST(YEAR(CH.Reported) AS VARCHAR(4)),'-1')
				ELSE CONCAT(CAST(YEAR(CH.Reported) AS VARCHAR(4)),'-2')
			END															AS ReportedHalfYear
		,	CASE
				WHEN MONTH(CH.Reported) <=3
				THEN 1
				WHEN MONTH(CH.Reported) <=6
				THEN 2
				WHEN MONTH(CH.Reported) <=9
				THEN 3
				ELSE 4
			END															AS ReportedQuarter
		,	MONTH(CH.Reported)											AS ReportedMonth
		,	CONVERT(varchar(12),CH.[Close Date], 101)					AS [Close Date]
		,	YEAR(CH.[Close Date])											AS CloseYear
		,	CASE
				WHEN MONTH(CH.[Close Date]) <=6
				THEN CONCAT(CAST(YEAR(CH.[Close Date]) AS VARCHAR(4)),'-1')
				ELSE CONCAT(CAST(YEAR(CH.[Close Date]) AS VARCHAR(4)),'-2')
			END															AS CloseHalfYear
		,	CASE
				WHEN MONTH(CH.[Close Date]) <=3
				THEN 1
				WHEN MONTH(CH.[Close Date]) <=6
				THEN 2
				WHEN MONTH(CH.[Close Date]) <=9
				THEN 3
				ELSE 4
			END															AS CloseQuarter
		,	MONTH(CH.[Close Date])											AS CloseMonth
		,	CH.State													AS CLAIM_STATE
		, CH.Comment
		,	CASE
				WHEN CD.Reserve IS NULL
				THEN 0
				ELSE CD.Reserve
			END															AS incurredLoss
		,	CASE
				WHEN CD.Paid IS NULL
				THEN 0
				ELSE CD.Paid
			END															AS Paid
		,	CASE
				WHEN CD.[Recovery] IS NULL
				THEN 0
				ELSE CD.[Recovery]
			END															AS [Recovery]	
		,	(CASE
				WHEN CD.Reserve IS NULL
				THEN 0
				ELSE CD.Reserve
			END)-	(CASE
				WHEN CD.[Recovery] IS NULL
				THEN 0
				ELSE CD.[Recovery]
			END)														AS NetInc	
		,	(CASE
				WHEN CD.Paid IS NULL
				THEN 0
				ELSE CD.Paid
			END)-	(CASE
				WHEN CD.[Recovery] IS NULL
				THEN 0
				ELSE CD.[Recovery]
			END)														AS NetPaid
		,	CASE
			 WHEN cd.[I Code] = 400
			 THEN 'ULAE'
			 WHEN cd.[I Code] = 401
			 then 'ALAE'
			 ELSE 'Loss'
		END																AS exp_ind
INTO #CLAIMS_SUB

FROM [HSQ-DB01].[Icarus].dbo.[Claims Dtl] CD
INNER JOIN [HSQ-DB01].[Icarus].dbo.[Claim Hdr] CH 
	ON CD.ClmId = CH.ClmId
LEFT JOIN [HSQ-DB01].[Icarus].dbo.Treaty t 
	ON CH.TreId = t.TId
LEFT JOIN #Claims_with_FAANo_Typos AS F
	ON CH.ClmId=F.ClmId AND CH.[Policy No]=F.Policy_No AND CD.CId=CASE 
																		WHEN F.CLAIM_TYPE_DESC='ACH' 
																		THEN 1  
																		WHEN F.CLAIM_TYPE_DESC='ACL' 
																		THEN 2
																		WHEN F.CLAIM_TYPE_DESC='APL' 
																		THEN 3 
																		ELSE 0 
																	END
WHERE CD.[Trans Date] <= @ed



UPDATE H
SET H.[Aircraft ID] = C.FAANO
FROM #CLAIMS_SUB AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]



SELECT ClmId, CLAIM_TYPE_DESC, dol,AccYear, [Close Date], CLAIM_STATE, PcReasonGroup, PcReason, sum(netinc) as NETINC, SUM(NETPAID) AS NETPAID 
FROM #CLAIMS_SUB AS CLAIMS
left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId
GROUP BY ClmId, CLAIM_TYPE_DESC, dol,AccYear, [Close Date], CLAIM_STATE, PcReasonGroup, PcReason



IF OBJECT_ID('tempdb..#ACH_CLAIMS_W_POLICYSUB_MATCH') IS NOT NULL
		DROP TABLE #ACH_CLAIMS_W_POLICYSUB_MATCH

				
select		CLAIMS.*
		,	PS.*
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else PS.HullValue_AgreedValue 
			end															AS ClaimHullValue 
		,	0															AS FIXED
		,	[Policy No]													AS FIXED_CLAIMS_POLICYNO
		,	PS.AIRCRAFTID												AS FIXED_AIRCRAFTID
		,	PS.POLID													AS FIXED_POLID
		,	[Aircraft ID]												AS FIXED_CLAIMS_FAANO
		,	0															AS FIXED_AIRCRAFTTYPE
		,	PS.MODELID													AS FIXED_MODELID
		,	''															AS FIXED_GEAR
		,	''															AS FIXED_WING					
	--SELECT  *
INTO #ACH_CLAIMS_W_POLICYSUB_MATCH
from	#CLAIMS_SUB AS CLAIMS 
		INNER JOIN #AIRCRAFT_Policy_Sub AS PS
			on PS.PolicyNo = CLAIMS.[Policy No] 		
			and PS.FAANo = CASE WHEN CLAIMS.ClmId=4036 AND CLAIMS.[Aircraft ID]='CESSNA' THEN 'N738AY' ELSE CLAIMS.[Aircraft ID] END
		left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId
		--INNER join (			
		--	select ch.ClmId, SUM(reserve) insuredLoss		
		--	from [HSQ-DB01].[Icarus].dbo.[Claim Hdr]  AS CH
		--		join [HSQ-DB01].[Icarus].dbo.[Claims Dtl] AS CD
		--			on ch.ClmId = cd.ClmId
		--	group		
		--	by		ch.ClmId
		--			)							AS LOSS			
			--on ch.ClmId = loss.ClmId	

	--where CH.ClmId<>3786 --NO HULL PREMIUM	
	--WHERE AnnualHullPrem=0 OR AnnualHullPrem IS NULL
	WHERE CLAIMS.CLAIM_TYPE_DESC='ACH'
	AND (FAANo NOT IN ('N/A','NA','TBA','VARIOUS') AND FAANo IS NOT NULL)

ORDER BY CAST(DOL AS DATE) DESC
--ORDER BY CAST(EfDate AS DATE) DESC	



--29 DISTINCT CLAIM NO TO UPDATE
SELECT '29 DISTINCT CLAIM NO TO UPDATE'
SELECT * FROM #Claims_with_No_Aircrafttype

--331 TRANSACTIONS TO UPDATE
SELECT '331 TRANSACTIONS TO UPDATE'
SELECT *FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.AIRCRAFTTYPE=C.AIRCRAFTTYPE
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.ModelCode=C.ModelCode
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.Model=C.Model
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.Gear=C.Gear
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.Wing=C.Wing
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo


-- CLMID 2899 AND 691
--2 EXTRA (INCORRECT) AIRCRAFT
--DELETE AIRCRAFTIDS 4687,124231

SELECT 'CLMID 2899 AND 691 2 EXTRA (INCORRECT) AIRCRAFT'
SELECT [ACTION], AircraftID,* FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1) AND [ACTION] IS NULL--AND [ACTION]<>'DELETE'
ORDER BY 3 DESC

--17 ROWS
DELETE FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE (ClmId=2899 AND AircraftID=4687) OR (ClmId=691 AND AircraftID=124231)

--CHECK ONLY 1 AIRCRAFTID PER CLAIM
SELECT 'CHECK ONLY 1 AIRCRAFTID PER CLAIM'
SELECT DISTINCT ClmID, AircraftID FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmId IN (2899,691)

SELECT DISTINCT ClmDtlId, AircraftID FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmId IN (2899,691)

--1043 ROWS
--DELETING DUPLICATES OF ACTION ADD/NULL/DELETES, WANT TO USE DELETES WHEN THEY HAVE INFO ADD/NULLS DO NOT
DELETE FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1) AND AircraftID NOT IN (SELECT DISTINCT MAX_AIRCRAFTID FROM (SELECT ClmDtlId, MAX(AIRCRAFTID) AS MAX_AIRCRAFTID FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1)
GROUP BY ClmDtlId) AS X)



--CHECK FOR MULTIPLES
SELECT 'CHECK FOR MULTIPLES'
SELECT ClmDtlId, AircraftID
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1) 


IF OBJECT_ID('tempdb..#ACH_CLAIMS_NO_POLICYSUB_MATCH') IS NOT NULL
		DROP TABLE #ACH_CLAIMS_NO_POLICYSUB_MATCH
										
	SELECT  ClmId, [Claim No], [Policy No], CASE WHEN [Aircraft ID] IS NULL THEN '' ELSE [Aircraft ID] END AS [Aircraft ID], CLAIM_TYPE_DESC	, CAST(DOL AS DATE) AS DOL, sum(NetInc) as NetInc
INTO #ACH_CLAIMS_NO_POLICYSUB_MATCH
from	#CLAIMS_SUB AS CLAIMS 
		LEFT JOIN #AIRCRAFT_Policy_Sub	AS PS
			on PS.PolicyNo = CLAIMS.[Policy No] 		
			and PS.FAANo = CLAIMS.[Aircraft ID]
		left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId		
	WHERE PS.PolicyNo IS NULL AND CLAIMS.CLAIM_TYPE_DESC='ACH'
	AND ClmId NOT IN (SELECT DISTINCT ClmId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH)
GROUP BY ClmId, [Claim No], [Policy No], [Aircraft ID], CLAIM_TYPE_DESC	, CAST(DOL AS DATE) 
ORDER BY CAST(DOL AS DATE) DESC	




--CONFIRM 4009=3640+369
SELECT 'CONFIRM 4009=3640+369'
SELECT COUNT(DISTINCT ClmId) FROM #CLAIMS_SUB WHERE CLAIM_TYPE_DESC='ACH'
SELECT COUNT(DISTINCT ClmId) FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
SELECT COUNT(DISTINCT ClmId) FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH	




--CLAIMS WITH WEIRD FAANOs
--17-1=16 CLAIMS
--CORRECTED OF CLMID 4036
SELECT '17 CLAIMS CLAIMS WITH WEIRD FAANOs'
SELECT Comment,*
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN [HSQ-DB01].[Icarus].dbo.[Claim Hdr] AS CH
ON H.ClmId=CH.ClmId
WHERE (H.[Aircraft ID] IN ('N/A','NA','TBA','VARIOUS','')) OR H.[Aircraft ID] IS NULL


IF OBJECT_ID('tempdb..#ACH_CLAIMS_BAD_FAANO') IS NOT NULL
		DROP TABLE #ACH_CLAIMS_BAD_FAANO

SELECT H.*, Comment
INTO #ACH_CLAIMS_BAD_FAANO
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN [HSQ-DB01].[Icarus].dbo.[Claim Hdr] AS CH
ON H.ClmId=CH.ClmId
WHERE (H.[Aircraft ID] IN ('N/A','NA','TBA','VARIOUS','')) OR H.[Aircraft ID] IS NULL


--NO POLICYNO MATCH
--194 CLAIMS
SELECT '194 CLAIMS NO POLICYNO MATCH'
SELECT *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
ORDER BY 1


--NO POLICYNO MATCH, MATCH VIA FAANo
--128 CLAIMS
SELECT '128 CLAIMS NO POLICYNO MATCH, MATCH VIA FAANo'
SELECT H.[Policy No], F.POLICYNO, DOL, *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','VARIOUS') THEN '?' ELSE F.FAANo END
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub) --AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS'))
ORDER BY CAST(DOL AS DATE) DESC

--3 HAVE A POLICY MATCH
--CLMID 4138 AND 4088 ARE AIRPORT POLICIES
--CLMID 2327 ITS POLICYNO DOES NOT HAVE ANY AIRCRAFTS ATTACHED AND IT WASN'T A BOUND POLICY
SELECT '3 HAVE A POLICY MATCH AIRPORT POLICIES'
SELECT *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub) --AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS'))
and [Policy No] IN (SELECT DISTINCT POLICYNO FROM [HSQ-DB01].[NPC_AIM].dbo.tblPolicy)

IF OBJECT_ID('tempdb..#ACH_CLAIMS_NONEXISTING_POLICYNO') IS NOT NULL
		DROP TABLE #ACH_CLAIMS_NONEXISTING_POLICYNO
SELECT H.*,F.*, TAM.Category AS AIRCRAFTTYPE, TAM.Gear, TAM.Wing,	convert(varchar,TAM.Category) + ' - ' + TAT.[Type]	AS AircraftTypeNameDisplay	
, TA.HullAge, TA.HullValue,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else TA.HullValue 
			end															AS ClaimHullValue 
INTO #ACH_CLAIMS_NONEXISTING_POLICYNO
FROM
(SELECT H.*, CLAIMS.PCId1
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN (SELECT DISTINCT CLMID, PCId1 FROM #CLAIMS_SUB) AS CLAIMS
ON H.ClmId=CLAIMS.CLMID) AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','VARIOUS') THEN '?' ELSE F.FAANo END
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS TA
	ON F.AircraftID=TA.AircraftID
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels AS TAM
	ON TA.ModelID=TAM.ModelID
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftTypes AS TAT
	ON TAM.Category=TAT.ID
left join #ProbableCause  AS PC	
			on H.PCId1 = pc.PCId
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub) --AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS'))
ORDER BY CAST(DOL AS DATE) DESC



--SELECT * FROM #ACH_CLAIMS_NONEXISTING_POLICYNO
--ORDER BY 1

--NO POLICYNO MATCH,NO FAANo MATCH
--66 CLAIMS
SELECT '66 CLAIMS NO POLICYNO MATCH,NO FAANo MATCH'
SELECT *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END--AND H.[Policy No]=F.POLICYNO
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)-- AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS'))
AND F.FAANo IS NULL
ORDER BY CAST(DOL AS DATE) DESC




--NO FAANO MATCH
--175 CLAIMS
SELECT '175 CLAIMS NO FAANO MATCH'
SELECT *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
ORDER BY 2

--FAANO MATCH, POLICYNO MATCH
--150 CLAIMS
--CLM ID 1986 HAS NO AIRCRAFT INFO, AIRCRAFT TYPE 4
SELECT '150 CLAIMS FAANO MATCH, POLICYNO MATCH'
SELECT *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub) --AND ClmId<>1986
ORDER BY 1



IF OBJECT_ID('tempdb..#ACH_CLAIMS_INCORRECT_POLICYNO') IS NOT NULL
		DROP TABLE #ACH_CLAIMS_INCORRECT_POLICYNO
SELECT X.*, CASE WHEN X.POLID=I.PPolID THEN 1 ELSE 0 END AS NEED_PREV_POLICY, CASE WHEN X.CLAIMS_POLID=146102 THEN 4 ELSE TAM.Category END AS AIRCRAFTTYPE 
, TAM.Gear, TAM.Wing,	convert(varchar,TAM.Category) + ' - ' + TAT.[Type]	AS AircraftTypeNameDisplay	
, TA.HullAge, TA.HullValue,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else TA.HullValue 
			end															AS ClaimHullValue 
INTO #ACH_CLAIMS_INCORRECT_POLICYNO
FROM #INSURED_POLID AS I
INNER JOIN
(
SELECT P.PolicyNo AS CLAIMS_POLICYNO, P.PolID AS CLAIMS_POLID, H.*, F.*, CLAIMS.PCId1
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=/*CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE*/ F.FAANo --END
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P
ON H.[Policy No]=P.PolicyNo
LEFT JOIN (SELECT DISTINCT CLMID, PCId1 FROM #CLAIMS_SUB) AS CLAIMS
ON H.ClmId=CLAIMS.CLMID
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
) AS X
ON X.CLAIMS_POLID=I.PolID
LEFT JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS TA
	ON X.AircraftID=TA.AircraftID 
LEFT JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels AS TAM
	ON CASE WHEN TA.AIRCRAFTID=150614 THEN 854 ELSE TA.ModelID END=TAM.ModelID 
LEFT JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftTypes AS TAT
	ON TAM.Category=TAT.ID
left join #ProbableCause  AS PC	
			on X.PCId1 = pc.PCId

--CLM ID 1986, AIRCRAFTID = 150614 HAS NO AIRCRAFT INFO, AIRCRAFT TYPE 4
SELECT * FROM #ACH_CLAIMS_INCORRECT_POLICYNO WHERE ClmId=1986

--select * from #AIRCRAFT_Policy_Sub where PolID=146102

--SELECT * FROM tblAircraft WHERE AircraftID=150614

--SELECT * FROM tlkAircraftModels WHERE Manufacturer LIKE '%PIPER%' AND MODEL LIKE '%PA46%'

--7 CLAIMS/8 AIRCRAFTS WITH PREVIOUS OR AFTER POLICIES
SELECT '7 CLAIMS/8 AIRCRAFTS WITH PREVIOUS OR AFTER POLICIES'
SELECT * FROM #ACH_CLAIMS_INCORRECT_POLICYNO WHERE NEED_PREV_POLICY=1 order by [Policy No]

--NO FAANO MATCH, POLICYNO MATCH
--25 CLAIMS
SELECT '25 CLAIMS NO FAANO MATCH, POLICYNO MATCH'
SELECT *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P
ON H.[Policy No]=P.PolicyNo
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
AND F.FAANo IS NULL
ORDER BY 2


--FAANo NOT IN DB
--66+25=91
SELECT '91 CLAIMS FAANo NOT IN DB'
SELECT *
FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
WHERE  F.FAANo IS NULL
ORDER BY 1


--DELETE 278 CORRECTED
DELETE FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH
WHERE ClmId IN (SELECT DISTINCT CLMID FROM #ACH_CLAIMS_NONEXISTING_POLICYNO) OR ClmId IN (SELECT DISTINCT ClmId FROM #ACH_CLAIMS_INCORRECT_POLICYNO)

--90 HULL CLAIM IDS
SELECT '91 CLAIMS NOT INCLUDED'
SELECT * FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH

--980 HULL CLAIM TRANSACTIONS NOT INCLUDED
SELECT '980 CLAIMS TRANSACTIONS NOT INCLUDED'
SELECT * FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS A INNER JOIN #CLAIMS_SUB AS B ON A.ClmId=B.ClmId AND B.CLAIM_TYPE_DESC='ACH'


--39967 TOTAL HULL CLAIM TRANSACTIONS
SELECT '39967 TOTAL HULL CLAIM TRANSACTIONS'
SELECT * FROM #CLAIMS_SUB WHERE CLAIM_TYPE_DESC='ACH'

--38987 CLAIM TRANSACTIONS INCLUDED
SELECT '38987 CLAIM TRANSACTIONS INCLUDED'
SELECT * FROM #CLAIMS_SUB WHERE  CLAIM_TYPE_DESC='ACH' AND ClmId NOT IN (SELECT ClmId FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH) ORDER BY ClmDtlId

--38987 CLAIM TRANSACTIONS INCLUDED
SELECT DISTINCT ClmDtlId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
UNION ALL
SELECT DISTINCT ClmDtlId FROM #ACH_CLAIMS_INCORRECT_POLICYNO AS A INNER JOIN #CLAIMS_SUB AS B ON A.ClmId=B.ClmId WHERE B.CLAIM_TYPE_DESC='ACH'
UNION ALL
SELECT DISTINCT ClmDtlId FROM #ACH_CLAIMS_NONEXISTING_POLICYNO  AS A INNER JOIN #CLAIMS_SUB AS B ON A.ClmId=B.ClmId WHERE B.CLAIM_TYPE_DESC='ACH'
ORDER BY ClmDtlId

--3918 CLAIM INCLUDED
SELECT '3918 CLAIM INCLUDED'
SELECT DISTINCT ClmId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
UNION ALL
SELECT DISTINCT A.ClmId FROM #ACH_CLAIMS_INCORRECT_POLICYNO AS A INNER JOIN #CLAIMS_SUB AS B ON A.ClmId=B.ClmId WHERE B.CLAIM_TYPE_DESC='ACH'
UNION ALL
SELECT DISTINCT A.ClmId FROM #ACH_CLAIMS_NONEXISTING_POLICYNO  AS A INNER JOIN #CLAIMS_SUB AS B ON A.ClmId=B.ClmId WHERE B.CLAIM_TYPE_DESC='ACH'
ORDER BY ClmId

--NO AIRCRAFT TYPE
SELECT 'NO AIRCRAFT TYPE'
SELECT [Claim No], FAANo,	SUM(NetInc)									AS NETINCURRED
	,	SUM(NetPaid)								AS NETPAID FROM #ACH_CLAIMS_W_POLICYSUB_MATCH WHERE AircraftType IS NULL
	GROUP BY [Claim No], FAANo



--AIRCRAFT TYPE HAS CHANGED
SELECT DISTINCT ClmId, AircraftID, FAANo, AircraftType, AircraftTypeNameDisplay,WHAT_TABLE
FROM
(
SELECT DISTINCT
	[Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'ALL MATCH'									AS WHAT_TABLE
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS A
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'MATCH BOTH, BUT INCORRECT POLICYNO WITH CLAIMS SUB'									AS WHAT_TABLE
FROM #ACH_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
WHERE B.CLAIM_TYPE_DESC='ACH'
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'NON EXISTING POLICYNO'									AS WHAT_TABLE
FROM #ACH_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE B.CLAIM_TYPE_DESC='ACH'
) AS X
WHERE AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL
ORDER BY AIRCRAFTTYPE


UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='1 - SELFG (4) ne200hp'
WHERE AircraftType=1 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='2 - SELFG (6) xs200hp'
WHERE AircraftType=2 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='2 - SELFG (6) xs200hp'
WHERE AircraftType=2 AND AircraftTypeNameDisplay='25 - zzNo Type'

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='3 - SELRG (4) ne200hp'
WHERE AIRCRAFTTYPE=3 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='4 - SELRG (6) xs200hp'
WHERE AircraftType=4 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='5 - SES (4) ne230hp'
WHERE AircraftType=5 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='7 - SELEXP (4) ne200hp'
WHERE AircraftType=7 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='8 - SELEXP(4) xs200hp'
WHERE AircraftType=8 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='9 - SELACRO'
WHERE AircraftType=9 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='10 - MELLT ne400hp'
WHERE AircraftType=10 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='11 - MELMD ne570hp'
WHERE AIRCRAFTTYPE=11 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='12 - MELCC xs570hp'
WHERE AIRCRAFTTYPE=12 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='14 - RW-Piston'
WHERE AircraftType=14 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='16 - ME-TurboJet'
WHERE AircraftType=16 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='19 - SE-TurboProp'
WHERE AircraftType=19 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='22 - Light Sport'
WHERE AircraftType=22 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACH_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='25 - zzNo Type'
WHERE AircraftType=25 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)


--AIRCRAFT TYPE HAS CHANGED
SELECT 'CHECK AGAIN, SHOULD ALL BE GONE'
SELECT DISTINCT ClmId, AircraftID, FAANo, AircraftType, AircraftTypeNameDisplay,WHAT_TABLE
FROM
(
SELECT DISTINCT
	[Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'ALL MATCH'									AS WHAT_TABLE
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS A
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'MATCH BOTH, BUT INCORRECT POLICYNO WITH CLAIMS SUB'									AS WHAT_TABLE
FROM #ACH_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
WHERE B.CLAIM_TYPE_DESC='ACH'
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'NON EXISTING POLICYNO'									AS WHAT_TABLE
FROM #ACH_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE B.CLAIM_TYPE_DESC='ACH'
) AS X
WHERE AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL
ORDER BY AIRCRAFTTYPE


SELECT DISTINCT AircraftType, AircraftTypeNameDisplay FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE AircraftType+ ' ' <> LEFT(AircraftTypeNameDisplay,2)

SELECT AircraftType, COUNT(DISTINCT AircraftTypeNameDisplay) FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
GROUP BY AircraftType
ORDER BY 2 DESC, 1



if OBJECT_ID('tempDb.dbo.#completeach') is not null drop table #completeach
--ALL CLAIM DATA
SELECT *
into #completeach
FROM
(
SELECT
	[polid]
	, [Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	, [policy no]
	, treaty_id
	, DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue_AgreedValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then [Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then [Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then [Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then [Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then netpaid else 0 end) as NetPaid_lae
	, SUM(incurredLoss) AS Incurred_la
	, SUM(Paid) AS paid_la
	, SUM([Recovery]) AS Recovered_la
	, SUM(NetInc) AS NetIncurred_la
	, SUM(netpaid) as NetPaid_la
	,	'ALL MATCH'									AS WHAT_TABLE
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS A
--WHERE AircraftType=4
GROUP BY polid
	, [Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	[policy no]
	, treaty_id
	, DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue_AgreedValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
UNION ALL
SELECT
	a.CLAIMS_POLID
	, A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then b.incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then b.[Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then b.NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then b.incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then b.[Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then b.NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then b.incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then b.Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then b.[Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then b.NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then b.netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.[Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.netpaid else 0 end) as NetPaid_lae
	, SUM(b.incurredLoss) AS Incurred_la
	, SUM(b.Paid) AS paid_la
	, SUM(b.[Recovery]) AS Recovered_la
	, SUM(b.NetInc) AS NetIncurred_la
	, SUM(b.netpaid) as NetPaid_la
	,	'MATCH BOTH, BUT INCORRECT POLICYNO WITH CLAIMS SUB'									AS WHAT_TABLE
FROM #ACH_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
--WHERE AircraftType=4
WHERE B.CLAIM_TYPE_DESC='ACH'
GROUP BY a.CLAIMS_POLID
	, A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
UNION ALL
SELECT
	0
	, A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then b.incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then b.[Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then b.NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then b.incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then b.[Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then b.NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then b.incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then b.Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then b.[Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then b.NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then b.netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.[Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.netpaid else 0 end) as NetPaid_lae
	, SUM(b.incurredLoss) AS Incurred_la
	, SUM(b.Paid) AS paid_la
	, SUM(b.[Recovery]) AS Recovered_la
	, SUM(b.NetInc) AS NetIncurred_la
	, SUM(b.netpaid) as NetPaid_la
	,	'NON EXISTING POLICYNO'									AS WHAT_TABLE
FROM #ACH_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
--WHERE AircraftType=4
WHERE B.CLAIM_TYPE_DESC='ACH'
GROUP BY A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	, a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
) AS X
--where AircraftType is null
ORDER BY CONVERT(datetime,DOL)



if OBJECT_ID('TempDB.dbo.#extraclaimsforach') is not null drop table #extraclaimsforach

select * into #extraclaimsforach from #CLAIMS_SUB
where clmdtlid not in (select clmdtlid from #completeach) and claim_type_desc = 'ACH'


if OBJECT_ID('TempDb.dbo.#extraclaimsnopolmatch') is not null drop table #extraclaimsnopolmatch

SELECT  claims.*, tam.category as aircrafttype, tam.wing, convert(varchar,TAM.Category) + ' - ' + TAT.[Type]	AS AircraftTypeNameDisplay, TA.HullAge, TA.HullValue
		,	case when pc.[PCCode] is null then 0 else 1 end				AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case when pc.[PCCode] is null then 0 else TA.HullValue end	AS ClaimHullValue 
INTO #extraclaimsnopolmatch
from	#extraclaimsforach claims
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON claims.[Aircraft ID] = F.FAANo
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS TA
	ON F.AircraftID=TA.AircraftID
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels AS TAM
	ON TA.ModelID=TAM.ModelID
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftTypes AS TAT
	ON TAM.Category=TAT.ID
left join #ProbableCause  AS PC	
	on claims.PCId1 = pc.PCId
WHERE claims.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
ORDER BY CAST(DOL AS DATE) DESC	



insert into #completeach
select 0
	, [claim no]
	, ClmId
	, ClmdtlID
	, claim_type
	, claim_type_desc
	, [policy no]
	, treaty_id
	, dol
	, accyear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, CLAIM_STATE
	, 99999 as AircraftID
	, [Aircraft ID] as FAANo
	, aircrafttype as AircraftType
	, 'O' as Gear
	, Wing
	, AircraftTypeNameDisplay
	, HullAge
	, HullValue
	, HasClaim
	, ClaimCauseGroup
	, ClaimCause
	, ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then [Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then [Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then [Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then [Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then netpaid else 0 end) as NetPaid_lae
	, SUM(incurredLoss) AS Incurred_la
	, SUM(Paid) AS paid_la
	, SUM([Recovery]) AS Recovered_la
	, SUM(NetInc) AS NetIncurred_la
	, SUM(netpaid) as NetPaid_la
	, 'OTHER CLAIMS NO POLICYSUB MATCH'			AS WHAT_TABLE
from #extraclaimsnopolmatch
GROUP BY 
	  [claim no]
	, ClmId
	, ClmdtlID
	, claim_type
	, claim_type_desc
	, [policy no]
	, treaty_id
	, dol
	, accyear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, CLAIM_STATE
	, [Aircraft ID]
	, aircrafttype
	, wing
	, AircraftTypeNameDisplay
	, hullage
	, hullvalue
	, HasClaim
	, ClaimCauseGroup
	, ClaimCause
	, ClaimHullValue

UNION ALL 
SELECT 0
	, [claim no]
	, ClmId
	, ClmdtlID
	, claim_type
	, claim_type_desc
	, [policy no]
	, treaty_id
	, dol
	, accyear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, CLAIM_STATE
	, 99999 as AircraftID
	, [Aircraft ID] as FAANo
	, 999 as AircraftType
	, 'O' as Gear
	, 'Unknown' as Wing
	, 'Other - Unknown' as AircraftTypeNameDisplay
	, 000 as HullAge
	, 000 as HullValue
	, case when pc.[PCCode] is null then 0 else 1 end				AS HasClaim														
	, pc.PcReasonGroup												AS ClaimCauseGroup	
	, pc.PcReason													AS ClaimCause		
	, 000															AS ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then [Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then [Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then [Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then [Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then netpaid else 0 end) as NetPaid_lae
	, SUM(incurredLoss) AS Incurred_la
	, SUM(Paid) AS paid_la
	, SUM([Recovery]) AS Recovered_la
	, SUM(NetInc) AS NetIncurred_la
	, SUM(netpaid) as NetPaid_la
	, 'OTHER CLAIMS NO KNOWN MATCH'									AS WHAT_TABLE
from #extraclaimsforach claims left join #probablecause pc on claims.pcid1 = pc.pcid where clmdtlid not in (select clmdtlid from #extraclaimsnopolmatch)
GROUP BY 
	  [claim no]
	, ClmId
	, ClmdtlID
	, claim_type
	, claim_type_desc
	, [policy no]
	, treaty_id
	, dol
	, accyear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, CLAIM_STATE
	, [Aircraft ID]
	, pc.PcCode
	, pc.PcReason
	, pc.PcReasonGroup





--SPECIAL USE ONLY
	IF OBJECT_ID('tempdb..#ACH_CLAIMS_SPECIAL_USE_ONLY') IS NOT NULL
		DROP TABLE #ACH_CLAIMS_SPECIAL_USE_ONLY
	SELECT CLAIMS.*
		,	SU.*
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else SU.HullValue_AgreedValue 
			end															AS ClaimHullValue 
	INTO #ACH_CLAIMS_SPECIAL_USE_ONLY
	from	#CLAIMS_SUB AS CLAIMS 
		INNER JOIN #AIRCRAFT_SPECIAL_USE_ONLY AS SU
			on SU.PolicyNo = CLAIMS.[Policy No] 		
			and SU.FAANo = CASE WHEN CLAIMS.ClmId=4036 AND CLAIMS.[Aircraft ID]='CESSNA' THEN 'N738AY' ELSE CLAIMS.[Aircraft ID] END
		left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId
	WHERE CLAIMS.CLAIM_TYPE_DESC='ACH' 

--204 ROWS
--DELETING DUPLICATES OF ACTION ADD/NULL/DELETES, WANT TO USE DELETES WHEN THEY HAVE INFO ADD/NULLS DO NOT
DELETE FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
GROUP BY ClmDtlId
HAVING COUNT(1)>1) AND AircraftID NOT IN (SELECT DISTINCT MAX_AIRCRAFTID FROM (SELECT ClmDtlId, MAX(AIRCRAFTID) AS MAX_AIRCRAFTID FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
GROUP BY ClmDtlId
HAVING COUNT(1)>1)
GROUP BY ClmDtlId) AS X)



--CHECK FOR MULTIPLES
SELECT 'CHECK FOR MLTIPLES'
SELECT ClmDtlId, AircraftID
FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
GROUP BY ClmDtlId
HAVING COUNT(1)>1) 


SELECT ClaimCause, ClaimCauseGroup, COUNT(DISTINCT CLMID), SUM(NETINC)
FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
WHERE UsageCd='ST'
GROUP BY ClaimCause, ClaimCauseGroup
ORDER BY 4 DESC

SELECT CLMID, PolicyNo, EfDate, AccYear, FAANo, SUM(NETINC) AS NETINC, sum(netpaid) FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
WHERE UsageCd='ST' AND ClaimCauseGroup='LANDING'
GROUP BY CLMID, PolicyNo, EfDate, AccYear, FAANo

SELECT * FROM #CLAIMS_SUB WHERE ClmId=3680


SELECT * FROM [HSQ-DB01].[NPC_AIM].[dbo].[tblAircraftUsage] AS TAU
LEFT JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkUsage] AS TU
	ON TAU.UsageID=TU.UsageID
WHERE AircraftID in (SELECT DISTINCT AircraftID FROM #ACH_CLAIMS_SPECIAL_USE_ONLY
WHERE UsageCd='ST' AND ClaimCauseGroup='LANDING')

--SPECIAL USE ONLY
--EARNED EXPOSURES COUNTS
SELECT 
		AircraftID
	,	CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END																		AS EfDate
	,	ExDate
	,	1		AS	PIF
FROM #AIRCRAFT_SPECIAL_USE_ONLY
WHERE UsageCd='FC'
and cast(CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END as date)<= @ed
ORDER BY cast(CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END as date)


--SPECIAL USE ONLY
--COUNTS
SELECT
	[Claim No]
	, DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredLoss) AS INCURRED
FROM (SELECT CLAIMS.*
		,	SU.*
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else SU.HullValue_AgreedValue 
			end															AS ClaimHullValue 
	from	#CLAIMS_SUB AS CLAIMS 
		INNER JOIN #AIRCRAFT_SPECIAL_USE_ONLY AS SU
			on SU.PolicyNo = CLAIMS.[Policy No] 		
			and SU.FAANo = CASE WHEN CLAIMS.ClmId=4036 AND CLAIMS.[Aircraft ID]='CESSNA' THEN 'N738AY' ELSE CLAIMS.[Aircraft ID] END
		left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId) AS X
WHERE UsageCd='FC'
GROUP BY [Claim No]
	, DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)	
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)	



SELECT 'AIRCRAFT TYPE COUNT'
SELECT AircraftType, COUNT(1) FROM #AIRCRAFT_Policy_Sub
GROUP BY AircraftType
ORDER BY 1

SELECT 'NULL COUNTS BY YEAR'
SELECT YEAR(EfDate), COUNT(1) FROM #AIRCRAFT_Policy_Sub
WHERE AircraftType IS NULL
GROUP BY YEAR(EFDATE)
ORDER BY 1


--EARNED EXPOSURES COUNTS
SELECT 
		AircraftID
	,	CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END																		AS EfDate
	,	ExDate
	,	1		AS	PIF
FROM #AIRCRAFT_Policy_Sub
WHERE UW='BB'
and cast(CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END as date)<=@ed
ORDER BY cast(CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END as date)


		--select uw,count(distinct [Claim No]) from #ACH_CLAIMS_W_POLICYSUB_MATCH
		--where AccYear>2013
		--group by uw
		--order by 2 desc


--COUNTS
SELECT
	[Claim No]
	, DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(Incurredloss) AS INCURRED
FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
WHERE UW='BB'
GROUP BY [Claim No]
	, DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)
UNION ALL
SELECT
	A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(Incurredloss) AS INCURRED
FROM #ACH_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE AircraftType=21
GROUP BY A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			
UNION ALL
SELECT
	A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredloss) AS INCURRED
FROM #ACH_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE AircraftType=21
GROUP BY A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)		



IF OBJECT_ID('tempdb..#ACL_CLAIMS_W_POLICYSUB_MATCH') IS NOT NULL
		DROP TABLE #ACL_CLAIMS_W_POLICYSUB_MATCH

				
select		CLAIMS.*
		,	PS.*
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else PS.HullValue_AgreedValue 
			end															AS ClaimHullValue 
		,	0															AS FIXED
		,	[Policy No]													AS FIXED_CLAIMS_POLICYNO
		,	PS.AIRCRAFTID												AS FIXED_AIRCRAFTID
		,	PS.POLID													AS FIXED_POLID
		,	[Aircraft ID]												AS FIXED_CLAIMS_FAANO
		,	0															AS FIXED_AIRCRAFTTYPE
		,	PS.MODELID													AS FIXED_MODELID
		,	''															AS FIXED_GEAR
		,	''															AS FIXED_WING					
	--SELECT  *
INTO #ACL_CLAIMS_W_POLICYSUB_MATCH
from	#CLAIMS_SUB AS CLAIMS 
		INNER JOIN #AIRCRAFT_Policy_Sub AS PS
			on PS.PolicyNo = CLAIMS.[Policy No] 		
			and PS.FAANo = CLAIMS.[Aircraft ID]
		left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId
		--INNER join (			
		--	select ch.ClmId, SUM(reserve) insuredLoss		
		--	from [HSQ-DB01].[Icarus].dbo.[Claim Hdr]  AS CH
		--		join [HSQ-DB01].[Icarus].dbo.[Claims Dtl] AS CD
		--			on ch.ClmId = cd.ClmId
		--	group		
		--	by		ch.ClmId
		--			)							AS LOSS			
			--on ch.ClmId = loss.ClmId	

	--where CH.ClmId<>3786 --NO HULL PREMIUM	
	--WHERE AnnualHullPrem=0 OR AnnualHullPrem IS NULL
	WHERE CLAIMS.CLAIM_TYPE_DESC='ACL'
	--AND (FAANo NOT IN ('N/A','NA','TBA','VARIOUS') AND FAANo IS NOT NULL)

ORDER BY CAST(DOL AS DATE) DESC


--30 DISTINCT CLAIM NO TO UPDATE
SELECT '30 DISTINCT CLAIM NO TO UPDATE'
SELECT * FROM #Claims_with_No_Aircrafttype

--208 TRANSACTIONS TO UPDATE
SELECT '208 TRANSACTIONS TO UPDATE'
SELECT * FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.AIRCRAFTTYPE=C.AIRCRAFTTYPE
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.ModelCode=C.ModelCode
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.Model=C.Model
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.Gear=C.Gear
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

UPDATE H
SET H.Wing=C.Wing
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS H
INNER JOIN #Claims_with_No_Aircrafttype AS C
	ON H.[Claim No]=C.[Claim No]
	AND H.FAANo=C.FAANo

-- CLMID 2899 AND 691
--2 EXTRA (INCORRECT) AIRCRAFT
--DELETE AIRCRAFTIDS 4687,124231
SELECT 'CLMID 691 2 EXTRA (INCORRECT) AIRCRAFT'
SELECT [ACTION], AircraftID,* FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1) AND [ACTION] IS NULL--AND [ACTION]<>'DELETE'
ORDER BY 3 DESC


--2 ROWS
DELETE FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE (ClmId=691 AND AircraftID=124231)

--CHECK ONLY 1 AIRCRAFTID PER CLAIM
SELECT 'CHECK ONLY 1 AIRCRAFTID PER CLAIM'
SELECT DISTINCT ClmID, AircraftID FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmId IN (691)

SELECT DISTINCT ClmDtlId, AircraftID FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmId IN (691)

--27 ROWS
--DELETING DUPLICATES OF ACTION ADD/NULL/DELETES, WANT TO USE DELETES WHEN THEY HAVE INFO ADD/NULLS DO NOT
DELETE FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1) AND AircraftID NOT IN (SELECT DISTINCT MAX_AIRCRAFTID FROM (SELECT ClmDtlId, MAX(AIRCRAFTID) AS MAX_AIRCRAFTID FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1)
GROUP BY ClmDtlId) AS X)

--CHECK FOR MULTIPLES
SELECT 'CHECK FOR MULTIPLES'
SELECT ClmDtlId, AircraftID
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE ClmDtlId IN(
SELECT ClmDtlId FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
GROUP BY ClmDtlId
HAVING COUNT(1)>1) 



IF OBJECT_ID('tempdb..#ACL_CLAIMS_NO_POLICYSUB_MATCH') IS NOT NULL
		DROP TABLE #ACL_CLAIMS_NO_POLICYSUB_MATCH
										
	SELECT  ClmId, [Claim No], [Policy No], CASE WHEN [Aircraft ID] IS NULL THEN '' ELSE [Aircraft ID] END AS [Aircraft ID], CLAIM_TYPE_DESC	, CAST(DOL AS DATE) AS DOL, sum(NetInc) as NetInc
INTO #ACL_CLAIMS_NO_POLICYSUB_MATCH
from	#CLAIMS_SUB AS CLAIMS 
		LEFT JOIN #AIRCRAFT_Policy_Sub	AS PS
			on PS.PolicyNo = CLAIMS.[Policy No] 		
			and PS.FAANo = CLAIMS.[Aircraft ID]
		left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId		
		--INNER join (			
		--	select ch.ClmId, SUM(reserve) insuredLoss		
		--	from [HSQ-DB01].[Icarus].dbo.[Claim Hdr]  AS CH
		--		join [HSQ-DB01].[Icarus].dbo.[Claims Dtl] AS CD
		--			on ch.ClmId = cd.ClmId
		--	group		
		--	by		ch.ClmId
		--			)							AS LOSS			
			--on ch.ClmId = loss.ClmId	

	--where CH.ClmId<>3786 --NO HULL PREMIUM	
	--WHERE AnnualHullPrem=0 OR AnnualHullPrem IS NULL
	WHERE PS.PolicyNo IS NULL AND CLAIMS.CLAIM_TYPE_DESC='ACL'
	--AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS') AND [Aircraft ID] IS NOT NULL)
	AND ClmId NOT IN (SELECT DISTINCT ClmId FROM #ACL_CLAIMS_W_POLICYSUB_MATCH)
GROUP BY ClmId, [Claim No], [Policy No], [Aircraft ID], CLAIM_TYPE_DESC	, CAST(DOL AS DATE) 
ORDER BY CAST(DOL AS DATE) DESC	



--CONFIRM 711=612+99
SELECT 'CONFIRM 711=614+97'
SELECT COUNT(DISTINCT ClmId) FROM #CLAIMS_SUB WHERE CLAIM_TYPE_DESC='ACL'
SELECT COUNT(DISTINCT ClmId) FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
SELECT COUNT(DISTINCT ClmId) FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH	


--CLAIMS WITH WEIRD FAANOs
--22 CLAIMS
SELECT '22 CLAIMS WITH WEIRD FAANOs'
SELECT Comment,*
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN [HSQ-DB01].[Icarus].dbo.[Claim Hdr] AS CH
ON H.ClmId=CH.ClmId
WHERE (H.[Aircraft ID] IN ('N/A','NA','TBA','VARIOUS','')) OR H.[Aircraft ID] IS NULL
ORDER BY H.DOL DESC




IF OBJECT_ID('tempdb..#ACL_CLAIMS_BAD_FAANO') IS NOT NULL
		DROP TABLE #ACL_CLAIMS_BAD_FAANO

SELECT H.*, Comment
INTO #ACL_CLAIMS_BAD_FAANO
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN [HSQ-DB01].[Icarus].dbo.[Claim Hdr] AS CH
ON H.ClmId=CH.ClmId
WHERE (H.[Aircraft ID] IN ('N/A','NA','TBA','VARIOUS','')) OR H.[Aircraft ID] IS NULL


--NO POLICYNO MATCH
--31 CLAIMS
SELECT '31 CLAIMS NO POLICYNO MATCH'
SELECT *
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
ORDER BY DOL DESC



--NO POLICYNO MATCH, MATCH VIA FAANo
--4 CLAIMS
SELECT '4 CLAIMS NO POLICYNO MATCH, MATCH VIA FAANo'
SELECT H.[Policy No], F.POLICYNO, DOL, *
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','VARIOUS') THEN '?' ELSE F.FAANo END
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub) --AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS'))
ORDER BY CAST(DOL AS DATE) DESC



IF OBJECT_ID('tempdb..#ACL_CLAIMS_NONEXISTING_POLICYNO') IS NOT NULL
		DROP TABLE #ACL_CLAIMS_NONEXISTING_POLICYNO
SELECT H.*,F.*, TAM.Category AS AIRCRAFTTYPE, TAM.Gear, TAM.Wing,	convert(varchar,TAM.Category) + ' - ' + TAT.[Type]	AS AircraftTypeNameDisplay	
, TA.HullAge, TA.HullValue,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else TA.HullValue 
			end															AS ClaimHullValue 
INTO #ACL_CLAIMS_NONEXISTING_POLICYNO
FROM
(SELECT H.*, CLAIMS.PCId1
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN (SELECT DISTINCT CLMID, PCId1 FROM #CLAIMS_SUB) AS CLAIMS
ON H.ClmId=CLAIMS.CLMID) AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','VARIOUS') THEN '?' ELSE F.FAANo END
INNER JOIN [HSQ-Db01].[NPC_AIM].dbo.tblAircraft AS TA
	ON F.AircraftID=TA.AircraftID
INNER JOIN [HSQ-Db01].[NPC_AIM].dbo.tlkAircraftModels AS TAM
	ON TA.ModelID=TAM.ModelID
INNER JOIN [HSQ-Db01].[NPC_AIM].dbo.tlkAircraftTypes AS TAT
	ON TAM.Category=TAT.ID
left join #ProbableCause  AS PC	
			on H.PCId1 = pc.PCId
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub) --AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS'))





--NO POLICYNO MATCH,NO FAANo MATCH
--27 CLAIMS
SELECT '27 CLAIMS NO POLICYNO MATCH,NO FAANo MATCH'
SELECT *
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END--AND H.[Policy No]=F.POLICYNO
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)-- AND ([Aircraft ID] NOT IN ('N/A','NA','TBA','CESSNA','VARIOUS'))
AND F.FAANo IS NULL
ORDER BY CAST(DOL AS DATE) DESC



--NO FAANO MATCH
--66 CLAIMS
SELECT '66 CLAIMS NO FAANO MATCH'
SELECT *
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
ORDER BY 2

--FAANO MATCH, POLICYNO MATCH
--33 CLAIMS
--CLM ID 1986 HAS NO AIRCRAFT INFO, AIRCRAFT TYPE 4
SELECT '33 CLAIMS FAANO MATCH, POLICYNO MATCH'
SELECT *
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub) --AND ClmId<>1986
ORDER BY 1



IF OBJECT_ID('tempdb..#ACL_CLAIMS_INCORRECT_POLICYNO') IS NOT NULL
		DROP TABLE #ACL_CLAIMS_INCORRECT_POLICYNO
SELECT X.*, CASE WHEN X.POLID=I.PPolID THEN 1 ELSE 0 END AS NEED_PREV_POLICY, CASE WHEN X.CLAIMS_POLID=146102 THEN 4 ELSE TAM.Category END AS AIRCRAFTTYPE 
, TAM.Gear, TAM.Wing,	convert(varchar,TAM.Category) + ' - ' + TAT.[Type]	AS AircraftTypeNameDisplay	
, TA.HullAge, TA.HullValue,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else TA.HullValue 
			end															AS ClaimHullValue 
INTO #ACL_CLAIMS_INCORRECT_POLICYNO
FROM #INSURED_POLID AS I
INNER JOIN
(
SELECT P.PolicyNo AS CLAIMS_POLICYNO, P.PolID AS CLAIMS_POLID, H.*, F.*, CLAIMS.PCId1
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
INNER JOIN [HSQ-Db01].[NPC_AIM].dbo.tblPolicy AS P
ON H.[Policy No]=P.PolicyNo
LEFT JOIN (SELECT DISTINCT CLMID, PCId1 FROM #CLAIMS_SUB) AS CLAIMS
ON H.ClmId=CLAIMS.CLMID
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
) AS X
ON X.CLAIMS_POLID=I.PolID
LEFT JOIN [HSQ-Db01].[NPC_AIM].dbo.tblAircraft AS TA
	ON X.AircraftID=TA.AircraftID 
LEFT JOIN [HSQ-Db01].[NPC_AIM].dbo.tlkAircraftModels AS TAM
	ON CASE WHEN TA.AIRCRAFTID=150614 THEN 854 ELSE TA.ModelID END=TAM.ModelID 
LEFT JOIN [HSQ-Db01].[NPC_AIM].dbo.tlkAircraftTypes AS TAT
	ON TAM.Category=TAT.ID
left join #ProbableCause  AS PC	
			on X.PCId1 = pc.PCId


		
--4 CLAIMS WITH PREVIOUS OR AFTER POLICIES
SELECT '4 CLAIMS WITH PREVIOUS OR AFTER POLICIES'
SELECT * FROM #ACL_CLAIMS_INCORRECT_POLICYNO WHERE NEED_PREV_POLICY=1 order by [Policy No]


--NO FAANO MATCH, POLICYNO MATCH
--33 CLAIMS
SELECT '33 CLAIMS NO FAANO MATCH, POLICYNO MATCH'
SELECT *
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
INNER JOIN [HSQ-Db01].[NPC_AIM].dbo.tblPolicy AS P
ON H.[Policy No]=P.PolicyNo
WHERE H.[Policy No]  IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)
AND F.FAANo IS NULL
ORDER BY DOL DESC


--FAANo NOT IN DB
--27+33=62
SELECT '60 CLAIMS FAANo NOT IN DB'
SELECT *
FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH AS H
LEFT JOIN #FAANo_MAX_AIRCRAFTID AS F
ON H.[Aircraft ID]=CASE WHEN F.FAANo IN ('N/A','NA','TBA','CESSNA','VARIOUS') THEN '?' ELSE F.FAANo END
WHERE  F.FAANo IS NULL
ORDER BY 1



--DELETE 37 CLAIMS CORRECTED
DELETE FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH
WHERE ClmId IN (SELECT DISTINCT CLMID FROM #ACL_CLAIMS_NONEXISTING_POLICYNO) OR ClmId IN (SELECT DISTINCT ClmId FROM #ACL_CLAIMS_INCORRECT_POLICYNO)



--CHECK
SELECT 'TOTAL =  44,239,544 '
select sum(netinc) from #CLAIMS_SUB where CLAIM_TYPE_DESC='acl'

SELECT 'MATCH =  39,954,468 +  1,389,735  +  1,078  =  41,345,282 '
select sum(NetInc) from #ACL_CLAIMS_W_POLICYSUB_MATCH
UNION ALL
SELECT SUM(NETINC) FROM #ACL_CLAIMS_INCORRECT_POLICYNO
UNION ALL
SELECT SUM(NETINC) FROM #ACL_CLAIMS_NONEXISTING_POLICYNO

SELECT 'NOT INCLUDED =  2,894,262 '
select sum(NetInc) from #ACL_CLAIMS_NO_POLICYSUB_MATCH

--60 ACL CLAIM IDS NOT INCLUDED
SELECT '60 CLAIMS NOT INCLUDED'
SELECT * FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH



--10298 TOTAL ACL CLAIM TRANSACTIONS
SELECT '10298 TOTAL ACL CLAIM TRANSACTIONS'
SELECT * FROM #CLAIMS_SUB WHERE CLAIM_TYPE_DESC='ACL'

--9481 CLAIM TRANSACTIONS INCLUDED
SELECT '9481 CLAIM TRANSACTIONS INCLUDED'
SELECT * FROM #CLAIMS_SUB WHERE  CLAIM_TYPE_DESC='ACL' AND ClmId NOT IN (SELECT ClmId FROM #ACL_CLAIMS_NO_POLICYSUB_MATCH) ORDER BY ClmDtlId

--9481 CLAIM TRANSACTIONS INCLUDED
SELECT DISTINCT ClmDtlId FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
UNION ALL
SELECT DISTINCT ClmDtlId FROM #ACL_CLAIMS_INCORRECT_POLICYNO AS A INNER JOIN #CLAIMS_SUB AS C ON A.ClmId=C.ClmId WHERE C.CLAIM_TYPE_DESC='ACL'
UNION ALL
SELECT DISTINCT ClmDtlId FROM #ACL_CLAIMS_NONEXISTING_POLICYNO  AS A  INNER JOIN #CLAIMS_SUB AS C ON A.ClmId=C.ClmId WHERE C.CLAIM_TYPE_DESC='ACL'
ORDER BY ClmDtlId

--651 CLAIM INCLUDED
SELECT '651 CLAIM INCLUDED'
SELECT DISTINCT ClmId FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
UNION ALL
SELECT DISTINCT A.ClmId FROM #ACL_CLAIMS_INCORRECT_POLICYNO AS A INNER JOIN #CLAIMS_SUB AS B ON A.ClmId=B.ClmId WHERE B.CLAIM_TYPE_DESC='ACL'
UNION ALL
SELECT DISTINCT A.ClmId FROM #ACL_CLAIMS_NONEXISTING_POLICYNO  AS A INNER JOIN #CLAIMS_SUB AS B ON A.ClmId=B.ClmId WHERE B.CLAIM_TYPE_DESC='ACL'
ORDER BY ClmId

--NO AIRCRAFT TYPE
SELECT 'NO AIRCRAFT TYPE'
SELECT [Claim No], FAANo,	SUM(NetInc)									AS NETINCURRED
	,	SUM(NetPaid)								AS NETPAID FROM #ACL_CLAIMS_W_POLICYSUB_MATCH 
	WHERE AircraftType IS NULL
	GROUP BY [Claim No], FAANo



--AIRCRAFT TYPE HAS CHANGED
SELECT DISTINCT ClmId, AircraftID, FAANo, AircraftType, AircraftTypeNameDisplay,WHAT_TABLE
FROM
(
SELECT DISTINCT
	[Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'ALL MATCH'									AS WHAT_TABLE
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS A
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'MATCH BOTH, BUT INCORRECT POLICYNO WITH CLAIMS SUB'									AS WHAT_TABLE
FROM #ACL_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
WHERE B.CLAIM_TYPE_DESC='ACL'
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'NON EXISTING POLICYNO'									AS WHAT_TABLE
FROM #ACL_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE B.CLAIM_TYPE_DESC='ACL'
) AS X
WHERE AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL
ORDER BY AIRCRAFTTYPE



UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='1 - SELFG (4) ne200hp'
WHERE AircraftType=1 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='2 - SELFG (6) xs200hp'
WHERE AircraftType=2 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='2 - SELFG (6) xs200hp'
WHERE AircraftType=2 AND AircraftTypeNameDisplay='25 - zzNo Type'

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='4 - SELRG (6) xs200hp'
WHERE AircraftType=4 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='5 - SES (4) ne230hp'
WHERE AircraftType=5 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='10 - MELLT ne400hp'
WHERE AircraftType=10 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='11 - MELMD ne570hp'
WHERE AIRCRAFTTYPE=11 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='12 - MELCC xs570hp'
WHERE AIRCRAFTTYPE=12 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)

UPDATE #ACL_CLAIMS_W_POLICYSUB_MATCH
SET AircraftTypeNameDisplay='14 - RW-Piston'
WHERE AircraftType=14 AND (AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL)


--AIRCRAFT TYPE HAS CHANGED
SELECT 'CHECK AGAIN, SHOULD ALL BE GONE'
SELECT DISTINCT ClmId, AircraftID, FAANo, AircraftType, AircraftTypeNameDisplay,WHAT_TABLE
FROM
(
SELECT DISTINCT
	[Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'ALL MATCH'									AS WHAT_TABLE
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS A
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'MATCH BOTH, BUT INCORRECT POLICYNO WITH CLAIMS SUB'									AS WHAT_TABLE
FROM #ACL_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
WHERE B.CLAIM_TYPE_DESC='ACL'
UNION ALL
SELECT DISTINCT
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	AircraftTypeNameDisplay
	,	'NON EXISTING POLICYNO'									AS WHAT_TABLE
FROM #ACL_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE B.CLAIM_TYPE_DESC='ACL'
) AS X
WHERE AircraftType <> CASE
						WHEN LEN(AircraftType)=1 
						THEN LEFT(AircraftTypeNameDisplay,1)
						ELSE LEFT(AircraftTypeNameDisplay,2)
					END
	OR AircraftTypeNameDisplay IS NULL
ORDER BY AIRCRAFTTYPE

SELECT * FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE AircraftType+ ' ' <> LEFT(AircraftTypeNameDisplay,2)

SELECT AircraftType, COUNT(DISTINCT AircraftTypeNameDisplay) FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
GROUP BY AircraftType
ORDER BY 2 DESC, 1


if OBJECT_ID('tempdb.dbo.#completeacl') is not null drop table #completeacl

--ALL ACL CLAIM DATA
SELECT *
into #completeacl
FROM
(
SELECT
	polid
	, [Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	, [policy no]
	, treaty_id
	, DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue_AgreedValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then [Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then [Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then [Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then [Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then netpaid else 0 end) as NetPaid_lae
	, SUM(incurredLoss) AS Incurred_la
	, SUM(Paid) AS paid_la
	, SUM([Recovery]) AS Recovered_la
	, SUM(NetInc) AS NetIncurred_la
	, SUM(netpaid) as NetPaid_la
	,	'ALL MATCH'									AS WHAT_TABLE
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH AS A
--WHERE AircraftType=4
GROUP BY polid
	, [Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	[policy no]
	, treaty_id
	, DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue_AgreedValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
UNION ALL
SELECT
	a.CLAIMS_POLID
	, A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then b.incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then b.[Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then b.NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then b.incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then b.[Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then b.NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then b.incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then b.Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then b.[Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then b.NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then b.netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.[Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.netpaid else 0 end) as NetPaid_lae
	, SUM(b.incurredLoss) AS Incurred_la
	, SUM(b.Paid) AS paid_la
	, SUM(b.[Recovery]) AS Recovered_la
	, SUM(b.NetInc) AS NetIncurred_la
	, SUM(b.netpaid) as NetPaid_la
	,	'MATCH BOTH, BUT INCORRECT POLICYNO WITH CLAIMS SUB'									AS WHAT_TABLE
FROM #ACL_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
--WHERE AircraftType=4
WHERE B.CLAIM_TYPE_DESC='ACL'
GROUP BY a.CLAIMS_POLID
	, A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	, a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
UNION ALL
SELECT
	0
	, A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then b.incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then b.[Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then b.NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then b.netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then b.incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then b.[Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then b.NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then b.netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then b.incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then b.Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then b.[Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then b.NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then b.netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.[Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then b.netpaid else 0 end) as NetPaid_lae
	, SUM(b.incurredLoss) AS Incurred_la
	, SUM(b.Paid) AS paid_la
	, SUM(b.[Recovery]) AS Recovered_la
	, SUM(b.NetInc) AS NetIncurred_la
	, SUM(b.netpaid) as NetPaid_la
	,	'NON EXISTING POLICYNO'									AS WHAT_TABLE
FROM #ACL_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
--WHERE AircraftType=4
WHERE B.CLAIM_TYPE_DESC='ACL'
GROUP BY 
	A.[Claim No]
	, A.ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	B.CLAIM_TYPE_DESC
	,	a.[policy no]
	, treaty_id
	, A.DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	, REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	FAANo
	,	AircraftType
	,	Gear
	,	A.Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	--,	AIRCRAFT_HULL_PREMIUM
	--,	ENTITY_TYPE
	--,	[PRIORITY]
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
) AS X
--where AircraftType is null
ORDER BY CONVERT(datetime,DOL)


if OBJECT_ID('TempDB.dbo.#extraclaimsforacl') is not null drop table #extraclaimsforacl

select * into #extraclaimsforacl from #CLAIMS_SUB claims
where clmdtlid not in (select clmdtlid from #completeacl) and CLAIM_TYPE_DESC = 'ACL'


if OBJECT_ID('TempDb.dbo.#extraaclnopol') is not null drop table #extraaclnopol

SELECT H.*,F.*, TAM.Category AS AIRCRAFTTYPE, TAM.Gear, TAM.Wing,	convert(varchar,TAM.Category) + ' - ' + TAT.[Type]	AS AircraftTypeNameDisplay	
, TA.HullAge, TA.HullValue,	case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim													
		,	pc.[PCCode]													AS ClaimCauseId		
		,	pc.PcReasonGroup											AS ClaimCauseGroup	
		,	pc.PcReason													AS ClaimCause			
		,	case 
				when pc.[PCCode] is null 
				then 0 
				else TA.HullValue 
			end															AS ClaimHullValue 
INTO #extraaclnopol
FROM
#extraclaimsforacl AS H
INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
	ON H.[Aircraft ID] = F.FAANo
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS TA
	ON F.AircraftID=TA.AircraftID
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels AS TAM
	ON TA.ModelID=TAM.ModelID
INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftTypes AS TAT
	ON TAM.Category=TAT.ID
left join #ProbableCause  AS PC	
			on H.PCId1 = pc.PCId
WHERE H.[Policy No] NOT IN (SELECT DISTINCT POLICYNO FROM #AIRCRAFT_Policy_Sub)



insert into #completeacl
SELECT
	0
	, [Claim No]
	,	ClmId
	,	ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	[policy no]
	, treaty_id
	,	DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	,	REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	[AircraftID] as AircraftID
	,	[aircraft id] as FAANo
	,	AircraftType
	,	Gear
	,	Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue as HullValue_AgreedValue
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then [Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then [Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then [Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then [Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then netpaid else 0 end) as NetPaid_lae
	, SUM(incurredLoss) AS Incurred_la
	, SUM(Paid) AS paid_la
	, SUM([Recovery]) AS Recovered_la
	, SUM(NetInc) AS NetIncurred_la
	, SUM(netpaid) as NetPaid_la
	,	'EXTRA CLAIMS WITH CLAIM NUM MATCH'			AS WHAT_TABLE
FROM #extraaclnopol
GROUP BY
	[Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	[policy no]
	, treaty_id
	,	DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	,	REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	 CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	AircraftID
	,	[Aircraft ID]
	,	AircraftType
	,	Gear
	,	Wing
	,	AircraftTypeNameDisplay
	,	HullAge
	,	HullValue
	,	HasClaim
	,	ClaimCauseGroup
	,	ClaimCause
	,	ClaimHullValue
UNION ALL
SELECT
	0
	, [Claim No]
	,	ClmId
	,	ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	[policy no]
	, treaty_id
	,	DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	,	REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	999 as AircraftID
	,	[aircraft id] as FAANo
	,	999 as AircraftType
	,	'O' as Gear
	,	'O' as Wing
	,	'Other - Unknown' as AircraftTypeNameDisplay
	,	000 as HullAge
	,	000 as HullValue
	,	case when pc.[PCCode] is null then 0 else 1 end				AS HasClaim														
	,	pc.PcReasonGroup											AS ClaimCauseGroup	
	,	pc.PcReason													AS ClaimCause		
	,	000															AS ClaimHullValue
	, SUM(case when exp_ind = 'ULAE' then incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then [Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then [Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then [Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then [Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then netpaid else 0 end) as NetPaid_lae
	, SUM(incurredLoss) AS Incurred_la
	, SUM(Paid) AS paid_la
	, SUM([Recovery]) AS Recovered_la
	, SUM(NetInc) AS NetIncurred_la
	, SUM(netpaid) as NetPaid_la
	,	'EXTRA CLAIMS WITH NO MATCHES'								AS WHAT_TABLE
FROM #extraclaimsforacl e left join #ProbableCause pc on pc.PcId = e.pcid1 where e.clmdtlid not in (select clmdtlid from #extraaclnopol)
GROUP BY [Claim No]
	, ClmId
	, ClmDtlId
	,	CLAIM_TYPE
	,	CLAIM_TYPE_DESC
	,	[policy no]
	, treaty_id
	,	DOL
	,	AccYear
	,	AccHalfYear
	,	AccQuarter
	,	AccMonth
	,	TRANS_DATE
	,	TransYear
	,	TransHalfYear
	,	TransQuarter
	,	TransMonth
	,	REPORTED_DATE
	,	ReportedYear
	,	ReportedHalfYear
	,	ReportedQuarter
	,	ReportedMonth
	,	[Close Date]
	,	CloseYear
	,	CloseHalfYear
	,	CloseQuarter
	,	CloseMonth
	,	CLAIM_STATE
	,	[Aircraft ID]
	,	pc.PcCode
	,	pc.PcReasonGroup
	,	pc.PcReason



SELECT COUNT(1)
FROM
(
select distinct ClmId
from #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE AircraftType=25 AND AccYear>2009
union all
select distinct A.clmid
from #ACL_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS C
	ON A.ClmId=C.ClmId AND C.CLAIM_TYPE_DESC='ACL'
WHERE AircraftType=25 AND AccYear>2009
UNION ALL
SELECT DISTINCT A.CLMID
FROM #ACL_CLAIMS_NONEXISTING_POLICYNO
 AS A
INNER JOIN #CLAIMS_SUB AS C
	ON A.ClmId=C.ClmId AND C.CLAIM_TYPE_DESC='ACL'
WHERE AircraftType=25 AND AccYear>2009
) AS A


SELECT AccYear,SUM(NETINC) AS NETINC
FROM
(
select AccYear, SUM(NetInc) AS NetInc
from #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE AircraftType=25 AND AccYear>2009
GROUP BY AccYear
union all
select AccYear, SUM(C.NetInc) AS NetInc
from #ACL_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS C
	ON A.ClmId=C.ClmId  AND C.CLAIM_TYPE_DESC='ACL'
WHERE AircraftType=25 AND AccYear>2009
GROUP BY AccYear
UNION ALL
SELECT AccYear, SUM(C.NetInc) AS NetInc
FROM #ACL_CLAIMS_NONEXISTING_POLICYNO
 AS A
INNER JOIN #CLAIMS_SUB AS C
	ON A.ClmId=C.ClmId AND C.CLAIM_TYPE_DESC='ACL'
WHERE AircraftType=25 AND AccYear>2009
GROUP BY AccYear
) AS A
GROUP BY AccYear
ORDER BY 1


--EARNED EXPOSURES COUNTS
SELECT 
		AircraftID
	,	CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END																		AS EfDate
	,	ExDate
	,	1		AS	PIF
FROM #AIRCRAFT_Policy_Sub
WHERE AircraftType=4
and cast(CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END as date)<= @ed
ORDER BY cast(CASE
			WHEN EfDate IS NULL
			THEN CONVERT(varchar(12),DATEFROMPARTS(YEAR(EXDATE)-1, MONTH(EXDATE), DAY(EXDATE)), 101)
			ELSE EfDate
		END as date)


		--select uw,count(distinct [Claim No]) from #ACL_CLAIMS_W_POLICYSUB_MATCH
		--where AccYear>2013
		--group by uw
		--order by 2 desc

--COUNTS
SELECT
	[Claim No]
	, DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredloss) AS INCURRED
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE AIRCRAFTTYPE=25
GROUP BY [Claim No]
	, DOL
	, REPORTED_DATE
	,	[Close Date]
		,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)	
UNION ALL
SELECT
	A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredloss) AS INCURRED
FROM #ACL_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE AIRCRAFTTYPE=25
GROUP BY A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)		
UNION ALL
SELECT
	A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredloss) AS INCURRED
FROM #ACL_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId 
WHERE AIRCRAFTTYPE=25
GROUP BY A.[Claim No]
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			

	SELECT * FROM #ACL_CLAIMS_W_POLICYSUB_MATCH WHERE ClmId=2065

	
SELECT
	CLMID
	, DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredloss) AS INCURRED
FROM #ACL_CLAIMS_W_POLICYSUB_MATCH
WHERE AIRCRAFTTYPE=25
GROUP BY CLMID
	, DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)		
UNION ALL
SELECT
	A.CLMID
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredloss) AS INCURRED
FROM #ACL_CLAIMS_INCORRECT_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
WHERE AIRCRAFTTYPE=25
GROUP BY A.CLMID
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)	
UNION ALL
SELECT
	A.CLMID
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		AS LOSSMo
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	AS REPMo
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)			AS CLOSEMo
	,	SUM(incurredloss) AS INCURRED
FROM #ACL_CLAIMS_NONEXISTING_POLICYNO AS A
INNER JOIN #CLAIMS_SUB AS B
ON A.ClmId=B.ClmId
WHERE AIRCRAFTTYPE=25
GROUP BY A.CLMID
	, A.DOL
	, REPORTED_DATE
	,	[Close Date]
	,	CONCAT(ACCYEAR,'M',AccMonth)		
	,	CONCAT(REPORTEDYEAR,'M',ReportedMonth)	
	,	CONCAT(CLOSEYEAR,'M',CloseMonth)	
ORDER BY 1






IF OBJECT_ID('tempdb..#APL_CLAIMS') IS NOT NULL
		DROP TABLE #APL_CLAIMS

select claims.*, isnull(ps.polid,0) as polid, case 
				when pc.[PCCode] is null 
				then 0 
				else 1
			end															AS HasClaim,
			PcReason,
			PcReasonGroup	
INTO #APL_CLAIMS
FROM #CLAIMS_SUB AS CLAIMS
left join #ProbableCause  AS PC	
			on CLAIMS.PCId1 = pc.PCId
left join #AIRCRAFT_Policy_Sub ps
			on PS.PolicyNo = CLAIMS.[Policy No] 
			and ps.faano = claims.[Aircraft ID]
WHERE CLAIM_TYPE_DESC='APL'


select accyear, sum(incurredloss - [recovery]) as ccincd, sum(netinc) as netinc from #APL_CLAIMS group by AccYear order by AccYear

if OBJECT_ID('tempDb.dbo.#completeapl') is not null drop table #completeapl

SELECT
	 polid
	, [Claim No]
	, [Clmid]
	, [clmdtlid]
	, [CLAIM_TYPE]
	, [CLAIM_TYPE_DESC]
	, [policy no]
	, treaty_id
	, DOL
	, AccYear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, CLAIM_STATE
	, HasClaim
	, PcReasonGroup as ClaimCauseGroup
	, PcReason as ClaimCause
	, SUM(case when exp_ind = 'ULAE' then incurredLoss else 0 end) AS Incurred_ulae
	, SUM(case when exp_ind = 'ULAE' then Paid else 0 end) as Paid_ulae
	, SUM(case when exp_ind = 'ULAE' then [Recovery] else 0 end) as Recovered_ulae
	, SUM(case when exp_ind = 'ULAE' then NetInc else 0 end) AS NetIncurred_ulae
	, SUM(case when exp_ind = 'ULAE' then netpaid else 0 end) as NetPaid_ulae
	, SUM(case when exp_ind = 'ALAE' then incurredLoss else 0 end) AS Incurred_alae
	, SUM(case when exp_ind = 'ALAE' then Paid else 0 end) as Paid_alae
	, SUM(case when exp_ind = 'ALAE' then [Recovery] else 0 end) as Recovered_alae
	, SUM(case when exp_ind = 'ALAE' then NetInc else 0 end) AS NetIncurred_alae
	, SUM(case when exp_ind = 'ALAE' then netpaid else 0 end) as NetPaid_alae
	, SUM(case when exp_ind = 'Loss' then incurredLoss else 0 end) AS Incurred_loss
	, SUM(case when exp_ind = 'Loss' then Paid else 0 end) as Paid_loss
	, SUM(case when exp_ind = 'Loss' then [Recovery] else 0 end) as Recovered_loss
	, SUM(case when exp_ind = 'Loss' then NetInc else 0 end) AS NetIncurred_loss
	, SUM(case when exp_ind = 'Loss' then netpaid else 0 end) as NetPaid_loss
	, SUM(case when exp_ind in ('ULAE','ALAE') then incurredLoss else 0 end) AS Incurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then Paid else 0 end) as Paid_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then [Recovery] else 0 end) as Recovered_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then NetInc else 0 end) AS NetIncurred_lae
	, SUM(case when exp_ind in ('ULAE','ALAE') then netpaid else 0 end) as NetPaid_lae
	, SUM(incurredLoss) AS Incurred_la
	, SUM(Paid) AS paid_la
	, SUM([Recovery]) AS Recovered_la
	, SUM(NetInc) AS NetIncurred_la
	, SUM(netpaid) as NetPaid_la
into #completeapl
FROM #APL_CLAIMS
GROUP BY polid
	, [Claim No]
	, [Clmid]
	, [clmdtlid]
	, [CLAIM_TYPE]
	, [CLAIM_TYPE_DESC]
	, [policy no]
	, treaty_id
	, DOL
	, AccYear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, CLAIM_STATE
	, HasClaim
	, PcReasonGroup
	, PcReason


-----Individual verifications. The older years should match up exactly with reserving files since there is no IBNR left
select DATEPART(yyyy,dol), sum(NetIncurred_la) as incd from #completeacl group by DATEPART(yyyy,dol) order by DATEPART(yyyy,dol)
select DATEPART(yyyy,dol), sum(NetIncurred_la) as incd from #completeach group by DATEPART(yyyy,dol) order by DATEPART(yyyy,dol)
select DATEPART(yyyy,dol), sum(NetIncurred_la) as incd from #completeapl group by DATEPART(yyyy,dol) order by DATEPART(yyyy,dol)



-----Combining all the types together into one big table for exporting
if OBJECT_ID('tempdb.dbo.#allclaims') is not null drop table #allclaims
select
	polid
	, [Claim No]
	, [Clmid]
	, [clmdtlid]
	, [CLAIM_TYPE]
	, [CLAIM_TYPE_DESC]
	, [policy no]
	, treaty_id
	, DOL
	, AccYear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, Claim_state
	, AircraftID
	, FAANo
	, AircraftType
	, Gear
	, Wing
	, AircraftTypeNameDisplay
	, HullAge
	, HullValue_AgreedValue
	, HasClaim
	, (case when ClaimCause in ('Hurricane CHARLEY','Hurricane FRANCES','Hurricane IVAN','Hurricane JEANNE','Hurricane KATRINA','Hurricane RITA','Hurricane WILMA','Hurricane DOLLY','Hurricane GUSTAV','Hurricane SANDY 2012','Hurricane MATTHEW','Hurricane HARVEY','Hurricane IRMA','Hurricane NATE','Weather (Wind.Tornado.Hurr.)') THEN 'Y' ELSE 'N' END) as ClmCat
	, ClaimCauseGroup
	, ClaimCause
	, ClaimHullValue
	, Incurred_ulae
	, Paid_ulae
	, Recovered_ulae
	, NetIncurred_ulae
	, NetPaid_ulae
	, Incurred_alae
	, Paid_alae
	, Recovered_alae
	, NetIncurred_alae
	, NetPaid_alae
	, Incurred_loss
	, Paid_loss
	, Recovered_loss
	, NetIncurred_loss
	, NetPaid_loss
	, Incurred_lae
	, Paid_lae
	, Recovered_lae
	, NetIncurred_lae
	, NetPaid_lae
	, Incurred_la
	, paid_la
	, Recovered_la
	, NetIncurred_la
	, NetPaid_la
	, WHAT_TABLE
into #allclaims
from #completeach
union all
select 
	polid
	, [Claim No]
	, [Clmid]
	, [clmdtlid]
	, [CLAIM_TYPE]
	, [CLAIM_TYPE_DESC]
	, [policy no]
	, treaty_id
	, DOL
	, AccYear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, Claim_state
	, AircraftID
	, FAANo
	, AircraftType
	, Gear
	, Wing
	, AircraftTypeNameDisplay
	, HullAge
	, HullValue_AgreedValue
	, HasClaim
	, (case when ClaimCause in ('Hurricane CHARLEY','Hurricane FRANCES','Hurricane IVAN','Hurricane JEANNE','Hurricane KATRINA','Hurricane RITA','Hurricane WILMA','Hurricane DOLLY','Hurricane GUSTAV','Hurricane SANDY 2012','Hurricane MATTHEW','Hurricane HARVEY','Hurricane IRMA','Hurricane NATE','Weather (Wind.Tornado.Hurr.)') THEN 'Y' ELSE 'N' END) as ClmCat
	, ClaimCauseGroup
	, ClaimCause
	, ClaimHullValue
		, Incurred_ulae
	, Paid_ulae
	, Recovered_ulae
	, NetIncurred_ulae
	, NetPaid_ulae
	, Incurred_alae
	, Paid_alae
	, Recovered_alae
	, NetIncurred_alae
	, NetPaid_alae
	, Incurred_loss
	, Paid_loss
	, Recovered_loss
	, NetIncurred_loss
	, NetPaid_loss
	, Incurred_lae
	, Paid_lae
	, Recovered_lae
	, NetIncurred_lae
	, NetPaid_lae
	, Incurred_la
	, paid_la
	, Recovered_la
	, NetIncurred_la
	, NetPaid_la
	, WHAT_TABLE
from #completeacl
union all
select
	polid
	, [Claim No]
	, [Clmid]
	, [clmdtlid]
	, [CLAIM_TYPE]
	, [CLAIM_TYPE_DESC]
	, [policy no]
	, treaty_id
	, DOL
	, AccYear
	, AccHalfYear
	, AccQuarter
	, AccMonth
	, TRANS_DATE
	, TransYear
	, TransHalfYear
	, TransQuarter
	, TransMonth
	, REPORTED_DATE
	, ReportedYear
	, ReportedHalfYear
	, ReportedQuarter
	, ReportedMonth
	, [Close Date]
	, CloseYear
	, CloseHalfYear
	, CloseQuarter
	, CloseMonth
	, CLAIM_STATE
	, 00000						as AircraftID
	, 'N/A'						as FAANo
	, 999						as AircraftType
	, 'N'						as Gear
	, 'N/A'						as Wing
	, 'N/A- Airport policy'		as AircraftTypeNameDisplay
	, 0							as HullAge
	, 0							as HullValue_AgreedValue
	, HasClaim
	, (case when ClaimCause in ('Hurricane CHARLEY','Hurricane FRANCES','Hurricane IVAN','Hurricane JEANNE','Hurricane KATRINA','Hurricane RITA','Hurricane WILMA','Hurricane DOLLY','Hurricane GUSTAV','Hurricane SANDY 2012','Hurricane MATTHEW','Hurricane HARVEY','Hurricane IRMA','Hurricane NATE','Weather (Wind.Tornado.Hurr.)') THEN 'Y' ELSE 'N' END) as ClmCat
	, ClaimCauseGroup
	, ClaimCause
	, 0							as ClaimHullValue
		, Incurred_ulae
	, Paid_ulae
	, Recovered_ulae
	, NetIncurred_ulae
	, NetPaid_ulae
	, Incurred_alae
	, Paid_alae
	, Recovered_alae
	, NetIncurred_alae
	, NetPaid_alae
	, Incurred_loss
	, Paid_loss
	, Recovered_loss
	, NetIncurred_loss
	, NetPaid_loss
	, Incurred_lae
	, Paid_lae
	, Recovered_lae
	, NetIncurred_lae
	, NetPaid_lae
	, Incurred_la
	, paid_la
	, Recovered_la
	, NetIncurred_la
	, NetPaid_la
	, 'ALL APL'					as WHAT_TABLE
from #completeapl





-----Look at the total number here with the numbers from the individual pieces. The numbers between them should be the same
select accyear, sum(NETINCURRED_la) as incd from #allclaims where AccYear > 2009 group by AccYear order by AccYear
select DATEPART(yyyy,dol), sum(NETINCURRED_la) as incd from #completeacl where datepart(yyyy,dol) > 2009 group by DATEPART(yyyy,dol) order by DATEPART(yyyy,dol)
select DATEPART(yyyy,dol), sum(NETINCURRED_la) as incd from #completeach where datepart(yyyy,dol) > 2009 group by DATEPART(yyyy,dol) order by DATEPART(yyyy,dol)
select DATEPART(yyyy,dol), sum(NETINCURRED_la) as incd from #completeapl where datepart(yyyy,dol) > 2009 group by DATEPART(yyyy,dol) order by DATEPART(yyyy,dol)


----- Put the loss data into a table in HFS-S17
--if OBJECT_ID('pricing_Aim.dbo.pnl_losses_2') is not null drop table pricing_aim.dbo.pnl_losses_2

if OBJECT_ID('tempdb.dbo.#losses_detail') is not null drop table #losses_detail
select polid	
,[Claim No]	
,Clmid	
,clmdtlid	
,CLAIM_TYPE	
,CLAIM_TYPE_DESC	
,CLAIM_TYPE_DESC Reserving
,[policy no]
,treaty_id
,Claim_state	
,AircraftID	
,FAANo	
,AircraftType	
,Gear	
,Wing	
,AircraftTypeNameDisplay	
,HullAge	
,HullValue_AgreedValue	
,HasClaim	
,ClmCat	
,ClaimCauseGroup	
,ClaimCause	
,ClaimHullValue
,WHAT_TABLE
,DOL
,datepart(yy,DOL) AY
,datepart(yy,DOL)*100 + datepart(mm,DOL) mth_loss
,datepart(yy,DOL)*10 + case when datepart(mm,DOL) in (1,2,3) then 1 when datepart(mm,DOL) in (4,5,6) then 2 when datepart(mm,DOL) in (7,8,9) then 3 else 4 end qtr_loss
,REPORTED_DATE
,datepart(yy,REPORTED_DATE)*100 + datepart(mm,REPORTED_DATE) mth_rept
,datepart(yy,REPORTED_DATE)*10 + case when datepart(mm,REPORTED_DATE) in (1,2,3) then 1 when datepart(mm,REPORTED_DATE) in (4,5,6) then 2 when datepart(mm,REPORTED_DATE) in (7,8,9) then 3 else 4 end qtr_rept
,[Close Date]
,datepart(yy,[Close Date])*10 + case when datepart(mm,[Close Date]) in (1,2,3) then 1 when datepart(mm,[Close Date]) in (4,5,6) then 2 when datepart(mm,[Close Date]) in (7,8,9) then 3 else 4 end qtr_close
,datepart(yy,TRANS_DATE)*10 + case when datepart(mm,TRANS_DATE) in (1,2,3) then 1 when datepart(mm,TRANS_DATE) in (4,5,6) then 2 when datepart(mm,TRANS_DATE) in (7,8,9) then 3 else 4 end qtr_val
,datepart(yy,[Close Date])*100 + datepart(mm,[Close Date]) mth_close
,datepart(yy,TRANS_DATE)*100 +datepart(mm,TRANS_DATE) mth_val
,TRANS_DATE
	, Incurred_ulae
	, Paid_ulae
	, Recovered_ulae
	, NetIncurred_ulae
	, NetPaid_ulae
	, Incurred_alae
	, Paid_alae
	, Recovered_alae
	, NetIncurred_alae
	, NetPaid_alae
	, Incurred_loss
	, Paid_loss
	, Recovered_loss
	, NetIncurred_loss
	, NetPaid_loss
	, Incurred_lae
	, Paid_lae
	, Recovered_lae
	, NetIncurred_lae
	, NetPaid_lae
	, Incurred_la
	, paid_la
	, Recovered_la
	, NetIncurred_la
	, NetPaid_la
into #losses_detail
from #allclaims a



if OBJECT_ID('tempdb.dbo.#Triangle_dev') is not null drop table #Triangle_dev
select
 [policy no] + cast(isnull(faano,'APL') as varchar(25)) + cast(isnull(AircraftType,1) as varchar(25)) [lookup_claims]
,polid	
,[Claim No]	
,Clmid	
,CLAIM_TYPE	
,CLAIM_TYPE_DESC	
,Reserving
,[policy no]
,treaty_id
,Claim_state	
,AircraftID	
,FAANo	
,AircraftType	
,Gear	
,Wing	
,AircraftTypeNameDisplay	
,HullAge	
,HullValue_AgreedValue	
,HasClaim	
,ClmCat	
,ClaimCauseGroup	
,ClaimCause	
,ClaimHullValue
,WHAT_TABLE
,DOL
,AY
,mth_loss
,qtr_loss
,REPORTED_DATE
,mth_rept
,qtr_rept
,[Close Date]
,mth_close
,qtr_close
,TRANS_DATE
,b.mth_val
,left(b.mth_val,4)*10 + case when RIGHT(b.mth_val,2) in ('01','02','03') then 1 when RIGHT(b.mth_val,2) in ('04','05','06') then 2 when RIGHT(b.mth_val,2) in ('07','08','09') then 3 else 4 end qtr_val
,case when right(b.mth_val,2) in ('03','06','09','12') then 1 else 0 end qtr_end
,(left(b.mth_val,4)*1 - left(mth_loss,4)*1)*12 + RIGHT(b.mth_val,2)*1 - RIGHT(mth_loss,2)*1 mth_dev 
,(left(b.mth_val,4)*1 - left(qtr_loss,4)*1)*4 + case when RIGHT(b.mth_val,2) in ('01','02','03') then 1 when RIGHT(b.mth_val,2) in ('04','05','06') then 2 when RIGHT(b.mth_val,2) in ('07','08','09') then 3 else 4 end qtr_dev

	
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.Paid_loss, 0) else 0 end) as paid_loss
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.Paid_alae, 0) else 0 end) as paid_alae
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.Paid_ulae, 0) else 0 end) as paid_ulae
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.Paid_lae, 0) else 0 end) as paid_lae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(Incurred_loss,0) else 0 end) as incd_loss	
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(a.Incurred_alae, 0) else 0 end) as incd_alae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(Incurred_ulae,0) else 0 end) as incd_ulae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(Incurred_lae,0) else 0 end) as incd_lae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(PAID_la,0) else 0 end) as paid_la
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(INCURRED_la,0) else 0 end) as incd_la
	
	
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.NetPaid_loss, 0) else 0 end) as net_paid_loss
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.NetPaid_alae, 0) else 0 end) as net_paid_alae
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.NetPaid_ulae, 0) else 0 end) as net_paid_ulae
	,sum(case	when b.mth_val >= a.mth_val then isnull(a.NetPaid_lae, 0) else 0 end) as net_paid_lae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(NetIncurred_loss,0) else 0 end) as net_incd_loss	
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(a.NetIncurred_alae, 0) else 0 end) as net_incd_alae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(NetIncurred_ulae,0) else 0 end) as net_incd_ulae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(NetIncurred_lae,0) else 0 end) as net_incd_lae
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(NETPAID_la,0) else 0 end) as net_paid_la
	,sum(case	when b.mth_val >= a.mth_val 
				then isnull(NETINCURRED_la,0) else 0 end) as net_incd_la

into #Triangle_dev
FROM #losses_detail a
left join #triangle b on (b.mth_val >= a.mth_loss)
group by polid	
,[Claim No]	
,Clmid	
,CLAIM_TYPE	
,CLAIM_TYPE_DESC	
,Reserving
,[policy no]
,treaty_id
,Claim_state	
,AircraftID	
,FAANo	
,AircraftType	
,Gear	
,Wing	
,AircraftTypeNameDisplay	
,HullAge	
,HullValue_AgreedValue	
,HasClaim	
,ClmCat	
,ClaimCauseGroup	
,ClaimCause	
,ClaimHullValue
,WHAT_TABLE
,DOL
,AY
,mth_loss
,qtr_loss
,REPORTED_DATE
,mth_rept
,qtr_rept
,[Close Date]
,mth_close
,qtr_close
,TRANS_DATE
,b.mth_val
,left(b.mth_val,4)*10 + case when RIGHT(b.mth_val,2) in ('01','02','03') then 1 when RIGHT(b.mth_val,2) in ('04','05','06') then 2 when RIGHT(b.mth_val,2) in ('07','08','09') then 3 else 4 end
,case when right(b.mth_val,2) in ('03','06','09','12') then 1 else 0 end 
,(left(b.mth_val,4)*1 - left(mth_loss,4)*1)*12 + RIGHT(b.mth_val,2)*1 - RIGHT(mth_loss,2)*1
,(left(b.mth_val,4)*1 - left(qtr_loss,4)*1)*4 + case when RIGHT(b.mth_val,2) in ('01','02','03') then 1 when RIGHT(b.mth_val,2) in ('04','05','06') then 2 when RIGHT(b.mth_val,2) in ('07','08','09') then 3 else 4 end



select a.*, case when ch.comment like '%Hail%' then 'Hail'
				when ch.comment like '%Tornado%' then 'Tornado'
				else ClaimCauseGroup end ClaimCauseGroup_detail
		, case when ch.PCId1 in (1,2,3,24,25,55,56,57,58,59,60,61,62,63,64,65,68,71,72,73,74,76,77,78,79,80,81) then 1 else 0 end Weather_claim_ind
into #final
FROM #Triangle_dev a
left join [HSQ-DB01].[Icarus].dbo.[Claim Hdr] CH 
	ON a.ClmId = CH.ClmId and a.[claim no] = ch.[claim no]


select distinct [claim no]
,a.D55_CAT_CODE
,D55_DESCRIPTION cat_description
into #cat_mapping
FROM pricing_aim.dbo.clm_cat_map a
left join AHIS..AHISPROD.LD55_CATASTROPHE b on a.D55_CAT_CODE=b.D55_CAT_CODE

delete from #cat_mapping where [claim no] = 'CA34158' and D55_CAT_CODE = 'C1441' and cat_description = 'CAT 41 WND, THNDRSTRM'
delete from #cat_mapping where [claim no] = 'CA37151' and D55_CAT_CODE = 'C1720' and cat_description = 'CAT 1720 FL,HL,TOR,WND'

select a.* 
,b.D55_CAT_CODE
,b.cat_description
into #final_2
FROM #final a
left join #cat_mapping b on a.[claim no]=b.[claim no] and reserving='ACH'


UPDATE #final_2
SET TRANS_DATE = FORMAT(CONVERT(date, TRANS_DATE, 101), 'yyyy-MM-dd')

if OBJECT_ID('tempdb.dbo.#temp05') is not null drop table #temp05
select
	a.[Claim No], a.reserving, a.dol, a.[Close Date], a.mth_val, a.TRANS_DATE,
	a.qtr_close,
	ROW_NUMBER() over (partition by a.[Claim No], a.reserving, a.mth_val order by a.TRANS_DATE)
		as counter1,
	isnull(a.net_incd_loss - a.net_paid_loss, 0) as case_loss,
	isnull(a.net_incd_lae - a.net_paid_lae, 0) as case_lgl,
	SUM(isnull(a.net_incd_loss - a.net_paid_loss, 0)) OVER (partition by a.[Claim No], a.reserving, a.mth_val order by a.TRANS_DATE) AS case_loss_cum,
	SUM(isnull(a.net_incd_lae - a.net_paid_lae, 0)) OVER (partition by a.[Claim No], a.reserving, a.mth_val order by a.TRANS_DATE) AS case_lgl_cum
into
	#temp05
from
	#final_2 a

----------------------------------------------------------------------------------------------------
-- If first transactions (via 'counter1') doesn't result in reserves, find first one that does
-- otherwise transaction will be flagged as a reopen
if OBJECT_ID('tempdb.dbo.#temp06') is not null drop table #temp06
select
	a.[Claim No], a.reserving, a.mth_val, min(a.counter1) as countermin
into
	#temp06
from
	#temp05 a
where
	--(a.case_loss_cum + a.case_lgl_cum) > 0
	a.case_loss_cum <> 0 or a.case_lgl_cum <> 0
group by
	a.[Claim No], a.reserving, a.mth_val

----------------------------------------------------------------------------------------------------
-- Create reopen/close flags based on change in reserves
-- if all rsv = 0 but any prior rsv <> 0 then close
-- if any rsv <> 0 but all prior rsv = 0 then reopen

-- Does this exaggerate reopens?

if OBJECT_ID('tempdb.dbo.#temp07') is not null drop table #temp07
select
	a.*, 
	isnull(b.case_loss_cum, 0) as cum_case_loss_prior,
	isnull(b.case_lgl_cum, 0) as cum_case_lgl_prior,
	(case	when (a.case_loss_cum = 0 and a.case_lgl_cum = 0)
				and (b.case_loss_cum <> 0 or b.case_lgl_cum <> 0) then 1 
			else 0 end) as flg_close,
	(case	when (a.case_loss_cum <> 0 or a.case_lgl_cum <> 0)
				and (b.case_loss_cum = 0 and b.case_lgl_cum = 0)
				and (a.counter1 > c.countermin)
			then 1 else 0 end) as flg_reopen,
	case when (case	when (a.case_loss_cum = 0 and a.case_lgl_cum = 0)
				and (b.case_loss_cum <> 0 or b.case_lgl_cum <> 0) then 1 
		else 0 end) = 1 then a.TRANS_DATE 
	else null 
	end date_close_kpi,
	case when (case	when (a.case_loss_cum <> 0 or a.case_lgl_cum <> 0)
				and (b.case_loss_cum = 0 and b.case_lgl_cum = 0)
				and (a.counter1 > c.countermin)
		then 1 else 0 end) = 1 then a.TRANS_DATE
	else null
	end date_reopen_kpi
into
	#temp07
from
	#temp05 a
left join
	#temp05 b on (a.[Claim No] = b.[Claim No]) and (a.reserving = b.reserving) and (a.mth_val = b.mth_val)
		and (a.counter1 = b.counter1 + 1)
left join
	#temp06 c on (a.[Claim No] = c.[Claim No]) and (a.reserving = c.reserving) and (a.mth_val = c.mth_val)

-- reserves cancel out? 
--select * from #temp07
--where [Claim No] = 'CA39207' and mth_val = 202305
--order by reserving, mth_val, TRANS_DATE
--select * from #temp07
--where [Claim No] = 'CA39248' and mth_val = 202305
--order by reserving, mth_val, TRANS_DATE

---- expenses reserve changes after close date
--select * from #temp07
--where [Claim No] = 'CA37301' and mth_val = 202305
--order by reserving, mth_val, TRANS_DATE

---- positive to negative and negative to positive reserves 
--select * from #temp07
--where [Claim No] = 'CA39320' and mth_val = 202305
--order by reserving, mth_val, TRANS_DATE

---- negative reserves
--select * from #temp07 
--where [Claim No] = 'CA36117' and mth_val = 202305
--order by reserving, mth_val, TRANS_DATE

----------------------------------------------------------------------------------------------------
-- Trim data down to only reopens and closures -- this is for merging back on later
if OBJECT_ID('tempdb.dbo.#temp08') is not null drop table #temp08
select
	a.[Claim No], a.reserving, a.DOL, a.[Close Date] as date_close,
	a.mth_val, a.qtr_close, a.flg_close, a.flg_reopen, a.date_close_kpi, a.date_reopen_kpi
into
	#temp08
from
	#temp07 a
where
	(a.flg_reopen = 1 or a.flg_close = 1)
group by
	a.[Claim No], a.reserving, a.DOL, a.[Close Date],
	a.mth_val, a.qtr_close, a.flg_close, a.flg_reopen, a.date_close_kpi, a.date_reopen_kpi

--select * from #temp08
--where [Claim No] =  'CA20254'
--order by mth_val

------------------------------------------------------------------------------------------------------
---- Grab all records from original table (#temp03) that have a close date.
---- Remember that close date will equal the most recent close date (not pushed back).
---- Compare to table we created, grab records that open/close without any case movement.
---- The 'HAVING' statement is important to catch errors with the close indicator (or closures that
---- still have IBNR).
if OBJECT_ID('tempdb.dbo.#temp09') is not null drop table #temp09
select
	a.[Claim No], a.reserving, a.DOL, a.[Close Date],
	a.mth_val, a.TRANS_DATE, a.qtr_close,
	1 as flg_close, 0 as flg_reopen, [Close Date] date_close_kpi, cast(null as date) date_reopen_kpi
into
	#temp09
from
	#final_2 a
left join
	#temp08 b on (a.[Claim No] = b.[Claim No]) and (a.reserving = b.reserving)--and (a.mth_val = b.mth_val) 
where
	a.[Close Date] is not null
	and b.[Claim No] is null
group by
	a.[Claim No], a.reserving, a.DOL, a.[Close Date],
	a.mth_val, a.TRANS_DATE, a.qtr_close
having
	sum(a.net_incd_la - a.net_paid_la) = 0

------------------------------------------------------------------------------------------------------
---- Merge #temp08 and #temp09 for complete list
if OBJECT_ID('tempdb.dbo.#temp10') is not null drop table #temp10
select
	a.*
	,1 case_ind 
into
	#temp10
from
	#temp07 a
left join #temp09 b on a.[Claim No] = b.[Claim No] and a.reserving = b.reserving
where b.[Claim No] is null and b.reserving is null
union all
select
	a.[Claim No], a.reserving, a.DOL, a.[Close Date],
	a.mth_val, a.trans_date, a.qtr_close, 1 counter1, 0 case_loss, 0 case_lgl, 0 case_loss_cum, 0 case_lgl_num, 0 cum_case_loss_prior, 0 cum_case_lgl_prior, a.flg_close, a.flg_reopen, a.date_close_kpi, a.date_reopen_kpi
	,0 case_ind 
from #temp09 a

--drop table #trinagle_qtr
--select distinct mth_val, TRANS_DATE into #trinagle_qtr from #final_2

----------------------------------------------------------------------------------------------------
-- Merge with #triangle for incremental ---> cumulative
-- want cumulative close/reopen flags for defining open/close at a given valuation
-- also merge close/reopen dates on
--drop table #temp11
--select
--	a.[Claim No], a.reserving, b.mth_val, b.trans_date, a.DOL,
--	c.[Close Date] as date_close, d.[Close Date] as date_reopen, datepart(yy,c.TRANS_DATE)*10 + case when datepart(mm,c.TRANS_DATE) in (1,2,3) then 1 when datepart(mm,c.TRANS_DATE) in (4,5,6) then 2 when datepart(mm,c.TRANS_DATE) in (7,8,9) then 3 else 4 end as test,

--	sum(case	when b.TRANS_DATE >= a.TRANS_DATE  
--				then isnull(a.flg_close, 0) else 0 end) as flg_close,
--	sum(case	when b.TRANS_DATE >= a.TRANS_DATE  
--				then isnull(a.flg_reopen, 0) else 0 end) as flg_reopen,
--	c.date_close_kpi,
--	d.date_reopen_kpi
--into
--	#temp11
--from
--	#temp07 a
--left join
--	#trinagle_qtr b on (b.TRANS_DATE >= a.DOL)
--left join
--	#temp07 c on (a.[Claim No] = c.[Claim No]) and (a.reserving = c.reserving) and (a.mth_val = c.mth_val) 
--		and (c.flg_close = 1)
--left join
--	#temp07 d on (a.[Claim No] = d.[Claim No]) and (a.reserving = d.reserving) and (a.mth_val = d.mth_val) 
--		and (d.flg_reopen = 1)
--group by
--	a.[Claim No], a.reserving, b.mth_val, b.trans_date, a.DOL,
--	c.[Close Date], d.[Close Date], datepart(yy,c.TRANS_DATE)*10 + case when datepart(mm,c.TRANS_DATE) in (1,2,3) then 1 when datepart(mm,c.TRANS_DATE) in (4,5,6) then 2 when datepart(mm,c.TRANS_DATE) in (7,8,9) then 3 else 4 end
--	,c.date_close_kpi,
--	d.date_reopen_kpi


if OBJECT_ID('tempdb.dbo.#temp11') is not null drop table #temp11
select
	a.[Claim No], a.reserving, a.mth_val, a.trans_date, a.DOL, a.flg_close, a.flg_reopen,
	SUM(isnull(a.flg_close, 0)) OVER (partition by a.[Claim No], a.reserving, a.mth_val order by a.TRANS_DATE) AS flg_close_cum,
	SUM(isnull(a.flg_reopen, 0)) OVER (partition by a.[Claim No], a.reserving, a.mth_val order by a.TRANS_DATE) AS flg_reopen_cum
	,a.date_close_kpi
	,a.date_reopen_kpi
	,a.case_ind
into #temp11
from #temp10 as a
group by
	a.[Claim No], a.reserving, a.mth_val, a.trans_date, a.DOL, a.flg_close, a.flg_reopen
	,a.date_close_kpi
	,a.date_reopen_kpi
	,a.case_ind

----------------------------------------------------------------------------------------------------
-- Delete records where date_close, date_reopen isn't maximum for a given quarter
-- do we really want min for reopen, i.e. earliest reopen?
--drop table #temp12
--select
--	a.[Claim No], a.reserving, a.qtr_val, a.mth_val, a.qtr_loss, a.mth_loss, a.DOL, a.flg_close,
--	a.flg_reopen, max(isnull(a.date_close,'9999-12-31')) as date_close, 
--	max(isnull(a.date_reopen,'9999-12-31')) as date_reopen
--into
--	#temp12
--from
--	#temp11 a
--group by
--	a.[Claim No], a.reserving, a.qtr_val, a.mth_val, a.qtr_loss, a.mth_loss, a.DOL, a.flg_close,a.qtr_val,
--	a.flg_reopen

if OBJECT_ID('tempdb.dbo.#final_3') is not null drop table #final_3
select a.*
	--,isnull(c.date_close, '9999-12-31') as date_close_act 
	--,isnull(c.date_reopen, '9999-12-31') as date_reopen_act
	--,year(c.date_close) * 10 + ceiling((month(c.date_close) - 1) / 3 + 1) as qtr_close_act
	,isnull(c.flg_close_cum, 0) as flg_close
	,isnull(c.flg_reopen_cum, 0) as flg_reopen
	,c.date_close_kpi
	,c.date_reopen_kpi
	,(case	when a.qtr_val < a.qtr_rept then 'U'
			when isnull(c.flg_close_cum, 0) = 0 and isnull(c.flg_reopen_cum, 0) = 0 then 'O'
			when isnull(c.flg_reopen_cum, 0) > 0 and isnull(c.flg_close_cum, 0) - isnull(c.flg_reopen_cum, 0) = 1 then 'RC'
			when isnull(c.flg_reopen_cum, 0) > 0 and isnull(c.flg_close_cum, 0) - isnull(c.flg_reopen_cum, 0) = 0 then 'RO'
			when isnull(c.flg_close_cum, 0) - isnull(c.flg_reopen_cum, 0) = 1 then 'C'
			else 'X' end) as clm_status1,
	(case	when a.net_incd_loss <= 0 then 'Without Indemnity'
			else 'Has Indemnity' end) as clm_status2,
	(case	when a.net_incd_lae <= 0 then 'Without Indemnity'
			else 'Has ALAE' end) as clm_status3
into #final_3
FROM #final_2 a
left join
	#temp11 c on (a.[Claim No] = c.[Claim No]) and (a.reserving = c.reserving) 
		and (a.mth_val = c.mth_val) and (a.TRANS_DATE = c.TRANS_DATE) 

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if OBJECT_ID('tempdb.dbo.#test01') is not null drop table #test01
select 
	[Claim No]
	,reserving
	,mth_val
	,TRANS_DATE
	,flg_close
	,flg_reopen
	,date_close_kpi
	,date_reopen_kpi
	,clm_status1
	,clm_status2
	,clm_status3
	,reported_date
into #test01
from #final_3
--where datepart(yy,trans_date)*100 + datepart(mm,trans_date) <= mth_val
group by
	[Claim No]
	,reserving
	,mth_val
	,TRANS_DATE
	,flg_close
	,flg_reopen
	,date_close_kpi
	,date_reopen_kpi
	,clm_status1
	,clm_status2
	,clm_status3
	,reported_date


if OBJECT_ID('tempdb.dbo.#test02') is not null drop table #test02
select
	[Claim No]
	,Reserving
	,mth_val
	,flg_close
	,date_close_kpi date_close_act
into #test02
from #test01
group by
	[Claim No]
	,Reserving
	,mth_val
	,flg_close
	,date_close_kpi

delete from #test02 where flg_close >= 1 and date_close_act is null


if OBJECT_ID('tempdb.dbo.#test03') is not null drop table #test03
select
	[Claim No]
	,Reserving
	,mth_val
	,flg_reopen
	,date_reopen_kpi date_reopen_act
into #test03
from #test01
group by
	[Claim No]
	,Reserving
	,mth_val
	,flg_reopen
	,date_reopen_kpi

delete from #test03 where flg_reopen >= 1 and date_reopen_act is null

if OBJECT_ID('tempdb.dbo.#test04') is not null drop table #test04
select
	a.*
	,b.date_close_act
	,c.date_reopen_act
	,case when a.flg_close = 0 and a.flg_reopen = 0 then '9999-12-31'
			when a.flg_reopen >= a.flg_close and a.flg_reopen >= 1 then '9999-12-31'
			when a.flg_close > a.flg_reopen then b.date_close_act
			end date_close_act_kpi
	,case when a.flg_close = 0 and a.flg_reopen = 0 then '9999-12-31'
			when a.flg_reopen >= a.flg_close and a.flg_reopen >= 1 then c.date_reopen_act
			when a.flg_close > a.flg_reopen then '9999-12-31'
			else '9999-12-31'
			end date_reopen_act_kpi
into #test04
from #test01 as a
left join #test02 as b on a.[Claim No] = b.[Claim No] and a.flg_close = b.flg_close and a.Reserving = b.Reserving and a.mth_val = b.mth_val
left join #test03 as c on a.[Claim No] = c.[Claim No] and a.flg_reopen = c.flg_reopen and a.Reserving = c.Reserving and a.mth_val = c.mth_val


if OBJECT_ID('tempdb.dbo.#test05') is not null drop table #test05
SELECT t.[Claim No], t.reserving, t.mth_val, t.date_close_act_kpi, t.date_reopen_act_kpi
into #test05
FROM #test04 t
INNER JOIN (
    SELECT [Claim No], reserving, mth_val, MAX(trans_date) AS max_trans_date
    FROM #test04
	where datepart(yy,trans_date) * 100 + datepart(mm,trans_date) <= mth_val 
    GROUP BY [Claim No], reserving, mth_val
) sub
ON t.[Claim No] = sub.[Claim No] and t.reserving = sub.reserving and t.mth_val = sub.mth_val AND t.trans_date = sub.max_trans_date
GROUP BY t.[Claim No], t.reserving, t.mth_val, t.date_close_act_kpi, t.date_reopen_act_kpi


if OBJECT_ID('tempdb.dbo.#final_4') is not null drop table #final_4
select
	a.*
	,b.date_close_act_kpi
	,b.date_reopen_act_kpi
into #final_4
from #final_3 as a
left join #test05 as b on a.[Claim No] = b.[Claim No] and a.mth_val = b.mth_val and a.Reserving = b.Reserving
where datepart(yy,a.trans_date) * 100 + datepart(mm,a.trans_date) <= a.mth_val

 
if OBJECT_ID('pricing_aim.dbo.aim_loss_ulae') is not null drop table pricing_aim.dbo.aim_loss_ulae

select * into pricing_aim.dbo.aim_loss_ulae
FROM #final_4
DECLARE @prior AS VARCHAR(4)
SET @prior = concat(RIGHT('00' + CONVERT(NVARCHAR(2), month(dateadd(month, -2, getdate()))), 2), right(year(dateadd(month, -2, getdate())),2))

--if OBJECT_ID('pricing_aim.dbo.aim_loss_ulae_0725') is not null drop table pricing_aim.dbo.aim_loss_ulae_0525

select * into pricing_aim.dbo.aim_loss_ulae FROM #final_4

select * into pricing_aim.dbo.aim_loss_ulae
FROM #final_4

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


----Reopens and Recloses
--select * from #final_4 where [Claim No] = 'CA20254' order by reserving, mth_val
--select * from #temp05 where [Claim No] = 'CA20254' order by reserving, mth_val, TRANS_DATE

----Current Pending
--select * from #final_4 where [Claim No] = 'CA39271' order by reserving, mth_val
--select * from #temp05 where [Claim No] = 'CA39271' order by reserving, mth_val, TRANS_DATE

------AFter same day loss payment
----select * from #status_ft_03 where clm_ft_num = 'PTX20-049594-2-2' order by order_id

------After expense payment
----select * from #status_ft_03 where clm_ft_num = 'PAZ20-045642-2-1' order by order_id

----No Transactions
--select * from #final_4 where [Claim No] = 'CA20129' order by reserving, mth_val
--select * from #temp11 where [Claim No] = 'CA20129' order by reserving, mth_val, TRANS_DATE

------Immediate Close
--select * from #final_4 where [Claim No] = 'CA42230' order by reserving, mth_val
--select * from #temp05 where [Claim No] = 'CA42230' order by reserving, mth_val, TRANS_DATE

------Expense Only
--select * from #final_4 where [Claim No] = 'CA31272' order by reserving, mth_val
--select * from #temp05 where [Claim No] = 'CA31272' order by reserving, mth_val, TRANS_DATE



--select AY
--,[claim no]
--,right(mth_loss,2) mth_loss
--,mth_dev 
--,mth_val
--,reserving
--,D55_CAT_CODE
--,cat_description
--,ClaimCauseGroup_detail
--,case when D55_CAT_CODE is null then 0 else 1 end cat_ind
--,count(distinct [claim no]) claim_count
--,sum(net_paid_loss) paid_loss
--,sum(net_paid_alae) paid_alae
--,sum(net_incd_loss) incd_loss
--,sum(net_incd_alae) incd_alae
--,sum(net_paid_la) paid_la
--,sum(net_incd_la) incd_la
--FROM #final_2
--where qtr_end =1 AND qtr_val=20201
--group by AY
--,right(mth_loss,2)
--,mth_dev
--,mth_val 
--,reserving
--,ClaimCauseGroup_detail
--,D55_CAT_CODE
--,cat_description
--,case when D55_CAT_CODE is null then 0 else 1 end 
--,[claim no]

--select AY
--,[claim no]
--,right(mth_loss,2) mth_loss
--,mth_dev 
--,mth_val
--,reserving
--,D55_CAT_CODE
--,cat_description
--,ClaimCauseGroup_detail
--,case when D55_CAT_CODE is null then 0 else 1 end cat_ind
--,count(distinct [claim no]) claim_count
--,sum(net_paid_loss) paid_loss
--,sum(net_paid_alae) paid_alae
--,sum(net_incd_loss) incd_loss
--,sum(net_incd_alae) incd_alae
--,sum(net_paid_la) paid_la
--,sum(net_incd_la) incd_la
--FROM #final_3
--where qtr_end =1 AND qtr_val=20201
--group by AY
--,right(mth_loss,2)
--,mth_dev
--,mth_val 
--,reserving
--,ClaimCauseGroup_detail
--,D55_CAT_CODE
--,cat_description
--,case when D55_CAT_CODE is null then 0 else 1 end 
--,[claim no]


drop table
#triangle
,#tblCoverages
,#AIRCRAFT_Policy_Sub
,#FAANo_AIRCRAFTTYPE_NULL_UPDATE
,#FAANo_AIRCRAFTTYPE_UPDATE_LATEST
,#AIRCRAFT_USAGE_LATEST
,#DISTINCT_tlkUsage
,#AIRCRAFT_SPECIAL_USE_ONLY
,#FAANo_MAX_AIRCRAFTID
,#INSURED_POLID
,#ProbableCause
,#Claims_with_FAANo_Typos
,#Claims_with_No_Aircrafttype
,#CLAIMS_SUB
,#ACH_CLAIMS_W_POLICYSUB_MATCH
,#ACH_CLAIMS_NO_POLICYSUB_MATCH
,#ACH_CLAIMS_BAD_FAANO
,#ACH_CLAIMS_NONEXISTING_POLICYNO
,#ACH_CLAIMS_INCORRECT_POLICYNO
,#extraclaimsforach
,#extraclaimsnopolmatch
,#ACH_CLAIMS_SPECIAL_USE_ONLY
,#ACL_CLAIMS_W_POLICYSUB_MATCH
,#ACL_CLAIMS_NO_POLICYSUB_MATCH
,#ACL_CLAIMS_BAD_FAANO
,#ACL_CLAIMS_NONEXISTING_POLICYNO
,#ACL_CLAIMS_INCORRECT_POLICYNO
,#completeacl
,#extraclaimsforacl
,#extraaclnopol
,#completeacl
,#APL_CLAIMS
,#completeapl
,#allclaims
,#losses_detail
,#Triangle_dev
,#final
,#cat_mapping
,#final_2
,#temp11
,#final_3
,#test01
,#test02
,#test03
,#test04
,#test05
,#final_4

DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID)
exec UPDATE_QUERY_TIMES @PROC_NAME, @StartTime
 
END TRY 
BEGIN CATCH 
SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE 
END CATCH
GO


