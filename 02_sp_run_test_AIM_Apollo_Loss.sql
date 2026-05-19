USE [Pricing_AIM]
GO

/*=============================================================================
  sp_run_test_AIM_Apollo_Loss.sql
  Purpose : Build the Apollo claims triangle (aim_loss_ulae) from NPC_AIM
            and Icarus, writing results to test_aim_loss_ulae.

  Improvements over original:
    - Static lookup data (ProbableCause, FAANo typo corrections, Aircraft
      type corrections) stored in TABLE VARIABLES (@tv_*) rather than temp
      tables, eliminating disk writes for small reference sets.
    - Triangle date population replaced with a set-based tally CTE instead
      of a cursor-style WHILE loop.
    - Multi-column UPDATE passes on #AIRCRAFT_Policy_Sub are collapsed into
      a single UPDATE per join target using a common-table-expression.
    - All diagnostic SELECT statements removed; use 05_validation.sql instead.
    - TRUNCATE + INSERT strategy on test_aim_loss_ulae (full triangle rebuild
      each month — same semantics as original DROP/SELECT INTO, but preserves
      identity/audit columns and avoids schema-change risk).
    - last_updated column refreshed on every load.
=============================================================================*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[run_test_AIM_Apollo_Loss]
AS
BEGIN TRY
    SET NOCOUNT ON;
    DECLARE @startTime DATETIME = GETDATE();

    -- The triangle "as-of" date: last day of the prior month
    DECLARE @ed DATE = DATEADD(DAY, -1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));

    -- =========================================================================
    -- Section 1 – Triangle valuation months
    --   Build the #triangle table using a recursive CTE (no WHILE loop).
    --   Produces one row per (year*100 + month) from 1999-01 through current.
    -- =========================================================================
    IF OBJECT_ID('tempdb..#triangle') IS NOT NULL DROP TABLE #triangle;

    ;WITH months AS
    (
        SELECT CAST(199901 AS INT) AS mth_val
        UNION ALL
        SELECT CASE WHEN mth_val % 100 = 12
                    THEN (mth_val / 100 + 1) * 100 + 1
                    ELSE mth_val + 1
               END
        FROM   months
        WHERE  mth_val < YEAR(GETDATE()) * 100 + MONTH(GETDATE()) - 1
    )
    SELECT mth_val
    INTO   #triangle
    FROM   months
    OPTION (MAXRECURSION 400);   -- ~25 years × 12 months

    -- =========================================================================
    -- Section 2 – Coverage aggregation from NPC_AIM
    -- =========================================================================
    IF OBJECT_ID('tempdb..#tblCoverages') IS NOT NULL DROP TABLE #tblCoverages;

    SELECT
        PolID,
        AircraftID,
        SUM(CASE WHEN CVID IN (33,34,35,39) THEN 1 ELSE 0 END)                 AS AIRCRAFT_HULL_CVG,
        SUM(CASE WHEN CVID IN (33,34,35,39) THEN ISNULL(Premium,0) ELSE 0 END) AS AIRCRAFT_HULL_PREMIUM,
        SUM(CASE WHEN CVID IN (26,28,31,40) THEN 1 ELSE 0 END)                 AS AIRCRAFT_LIAB_CVG,
        SUM(CASE WHEN CVID IN (26,28,31,40) THEN ISNULL(Premium,0) ELSE 0 END) AS AIRCRAFT_LIAB_PREMIUM,
        SUM(CASE WHEN CVID IN (16,23)       THEN 1 ELSE 0 END)                 AS AIRPORT_LIAB_CVG,
        SUM(CASE WHEN CVID IN (16,23)       THEN ISNULL(Premium,0) ELSE 0 END) AS AIRPORT_LIAB_PREMIUM,
        SUM(CASE WHEN CVID IN (32)          THEN 1 ELSE 0 END)                 AS MEDPAY_CVG,
        SUM(CASE WHEN CVID IN (32)          THEN ISNULL(Premium,0) ELSE 0 END) AS MEDPAY_PREMIUM
    INTO #tblCoverages
    FROM [HSQ-DB01].[NPC_AIM].dbo.tblCoverages
    GROUP BY PolID, AircraftID;

    -- =========================================================================
    -- Section 3 – Aircraft / policy master from NPC_AIM
    -- =========================================================================
    IF OBJECT_ID('tempdb..#AIRCRAFT_Policy_Sub') IS NOT NULL DROP TABLE #AIRCRAFT_Policy_Sub;

    SELECT
        TA.PolID,
        TP.PolicyNo,
        CONVERT(VARCHAR(12), TP.EfDate, 101)    AS EfDate,
        CONVERT(VARCHAR(12), TP.ExDate, 101)    AS ExDate,
        MONTH(TP.EfDate)                        AS EfDateMonth,
        YEAR(TP.EfDate)                         AS EfDateYear,
        TP.StatID,
        TPS.[Status],
        TA.[Action],
        TA.AircraftID,
        TA.FAANo,
        TA.Yr,
        TAM.ModelID,
        TAM.ModelCode,
        TAM.Model,
        TP.PrimaryUseID                         AS TP_PRIMARYUSEID,
        TA.PrimaryUseID                         AS TA_PRIMARYUSEID,
        TAM.Category                            AS AircraftType,
        TAM.Gear,
        TAM.Wing,
        TAT.[Type]                              AS AircraftTypeName,
        CONVERT(VARCHAR, TAM.Category) + ' - ' + TAT.[Type] AS AircraftTypeNameDisplay,
        TA.HullAge,
        TA.AgreedValue                          AS HullValue_AgreedValue,
        TA.AnnualHullPrem,
        TA.PREMIUM,
        C.AIRCRAFT_HULL_PREMIUM,
        C.AIRCRAFT_LIAB_PREMIUM,
        C.MEDPAY_PREMIUM,
        C.AIRCRAFT_HULL_CVG,
        C.AIRCRAFT_LIAB_CVG,
        C.MEDPAY_CVG,
        TA.IsManual,
        TP.PPolID,
        CASE
            WHEN TE.EntityName LIKE '%TRUST%' OR TE.EntityName LIKE '%ESTATE%'
              OR TE.EntityName LIKE '%NONE%'  OR TE.EntityName IS NULL
            THEN 'Individual'
            ELSE 'Corporation'
        END                                     AS ENTITY_TYPE,
        TE.EntityName,
        PROD.Company                            AS AGENCY,
        CASE WHEN PRI.PriorityId IN (1,4) THEN 'NEW' ELSE 'RENEWAL' END AS [PRIORITY],
        UW,
        SourceID,
        ProgramID,
        CarrierID,
        EntryNote
    INTO #AIRCRAFT_Policy_Sub
    FROM [HSQ-DB01].[NPC_AIM].dbo.tblPolicy                AS TP
    INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft        AS TA  ON TP.PolID     = TA.PolID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkPolicyStatus    AS TPS ON TP.StatID    = TPS.StatID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels  AS TAM ON TA.ModelID   = TAM.ModelID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftTypes   AS TAT ON TAM.Category = TAT.ID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkEntity]      AS TE  ON TP.EntityID  = TE.EntityID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tblProds]       AS PROD ON TP.ProdID   = PROD.ProdID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkPriority]    AS PRI ON TP.PriorityID= PRI.PriorityId
    LEFT  JOIN #tblCoverages                                AS C   ON TP.PolID     = C.PolID AND TA.AircraftID = C.AircraftID
    WHERE (TP.StatID >= 6 AND TP.PolID <> 285191)
       OR TP.PolicyNo = 'GA99-32936-00';

    -- =========================================================================
    -- Section 4 – Resolve aircraft type / model for NULL aircraft types
    --   Collapse six separate UPDATE passes into a single statement via CTE
    -- =========================================================================
    IF OBJECT_ID('tempdb..#FAANo_AIRCRAFTTYPE_NULL_UPDATE') IS NOT NULL
        DROP TABLE #FAANo_AIRCRAFTTYPE_NULL_UPDATE;

    SELECT DISTINCT TA.FAANo, TAM.Category AS AIRCRAFTTYPE,
                    TAM.ModelID, TAM.ModelCode, TAM.Model, TAM.Gear, TAM.Wing
    INTO #FAANo_AIRCRAFTTYPE_NULL_UPDATE
    FROM [HSQ-DB01].[NPC_AIM].dbo.tblAircraft      AS TA
    LEFT JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels AS TAM ON TA.ModelID = TAM.ModelID
    WHERE TAM.Category IS NOT NULL;

    -- Single-pass update using the FAANo lookup for NULL aircraft entries
    UPDATE A
    SET A.ModelID              = ISNULL(A.ModelID,    F.ModelID),
        A.ModelCode            = ISNULL(A.ModelCode,  F.ModelCode),
        A.Model                = ISNULL(A.Model,      F.Model),
        A.Gear                 = ISNULL(A.Gear,        F.Gear),
        A.Wing                 = ISNULL(A.Wing,        F.Wing),
        A.AircraftType         = ISNULL(A.AircraftType, F.AIRCRAFTTYPE)
    FROM #AIRCRAFT_Policy_Sub AS A
    INNER JOIN #FAANo_AIRCRAFTTYPE_NULL_UPDATE AS F ON A.FAANo = F.FAANo
    WHERE A.AircraftType IS NULL;

    -- Resolve conflicting AircraftType across FAA numbers: use the latest EfDate
    ;WITH cte_latest_type AS
    (
        SELECT A.FAANo, A.AircraftType, A.EfDate,
               ROW_NUMBER() OVER (PARTITION BY A.FAANo ORDER BY A.EfDate DESC) AS rn
        FROM (
            SELECT DISTINCT FAANo, AircraftType, EfDate
            FROM #AIRCRAFT_Policy_Sub
            WHERE FAANo IN (
                SELECT FAANo
                FROM (SELECT DISTINCT FAANo, AircraftType FROM #AIRCRAFT_Policy_Sub) x
                GROUP BY FAANo HAVING COUNT(*) > 1
            )
        ) AS A
    )
    UPDATE ps
    SET ps.AircraftType = lt.AircraftType
    FROM #AIRCRAFT_Policy_Sub ps
    INNER JOIN cte_latest_type lt ON ps.FAANo = lt.FAANo AND lt.rn = 1;

    -- =========================================================================
    -- Section 5 – Aircraft usage lookup (special use only)
    -- =========================================================================
    IF OBJECT_ID('tempdb..#DISTINCT_tlkUsage') IS NOT NULL DROP TABLE #DISTINCT_tlkUsage;

    ;WITH cte_latest_usage AS
    (
        SELECT TAU.AircraftID, MAX(TAU.AircraftUsageID) AS MAX_UsageID
        FROM [HSQ-DB01].[NPC_AIM].[dbo].[tblAircraftUsage] AS TAU
        WHERE TAU.AircraftID IN (SELECT DISTINCT AircraftID FROM #AIRCRAFT_Policy_Sub)
        GROUP BY TAU.AircraftID
    )
    SELECT DISTINCT TAU.AircraftID, TU.UsageID, TU.UsageCd,
                    TU.[Description] AS Usage_Description,
                    TU.PrimaryUseId  AS Usage_PrimaryUseID
    INTO #DISTINCT_tlkUsage
    FROM [HSQ-DB01].[NPC_AIM].[dbo].[tblAircraftUsage] AS TAU
    INNER JOIN [HSQ-DB01].[NPC_AIM].[dbo].[tlkUsage]   AS TU  ON TAU.UsageID   = TU.UsageID
    INNER JOIN cte_latest_usage                         AS cu  ON TAU.AircraftID = cu.AircraftID
                                                               AND TAU.AircraftUsageID = cu.MAX_UsageID;

    -- =========================================================================
    -- Section 6 – FAANo→max AircraftID lookup (used for unmatched claims)
    -- =========================================================================
    IF OBJECT_ID('tempdb..#FAANo_MAX_AIRCRAFTID') IS NOT NULL DROP TABLE #FAANo_MAX_AIRCRAFTID;

    SELECT FAANo, MAX(AircraftID) AS AircraftID,
           NULL  AS PolID,
           NULL  AS PolicyNo,
           NULL  AS StatID
    INTO #FAANo_MAX_AIRCRAFTID
    FROM [HSQ-DB01].[NPC_AIM].dbo.tblAircraft
    WHERE FAANo <> ''
    GROUP BY FAANo;

    -- Enrich with policy info in a single pass
    UPDATE F
    SET F.PolID    = A.PolID
    FROM #FAANo_MAX_AIRCRAFTID AS F
    INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS A ON F.AircraftID = A.AircraftID;

    UPDATE F
    SET F.PolicyNo = P.PolicyNo,
        F.StatID   = P.StatID
    FROM #FAANo_MAX_AIRCRAFTID AS F
    INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P ON F.PolID = P.PolID;

    -- =========================================================================
    -- Section 7 – Reference data in table variables (no disk I/O)
    -- =========================================================================

    -- Probable cause lookup
    DECLARE @tv_ProbableCause TABLE
    (
        PcId         INT,
        PcCode       VARCHAR(3),
        PcReasonGroup VARCHAR(100),
        PcReason     VARCHAR(100)
    );
    INSERT INTO @tv_ProbableCause VALUES
        (1,'100','GNIM','Weather (Wind.Tornado.Hurr.)'),(2,'101','GNIM','Weather (Hail)'),
        (3,'102','GNIM','Weather (Flood)'),(4,'103','GNIM','Theft or Vandalism'),
        (5,'104','GNIM','Third Party Negligence'),(6,'105','GNIM','Fire or Explosion (Hostile)'),
        (7,'106','GNIM','Fire or Explosion (Accidental)'),(8,'107','GNIM','Fire or Explosion (Arson)'),
        (9,'108','GNIM','Towing Damage'),(10,'109','GNIM','Other'),
        (11,'200','TAXI','Collision with other Aircraft'),(12,'201','TAXI','Collision with other Vehicles'),
        (13,'202','TAXI','Collision with Ground Structures'),(14,'203','TAXI','Collision with Person'),
        (15,'204','TAXI','Prop Strike'),(16,'205','TAXI','Other'),
        (17,'300','TAKEOFF','Loss of Directional Control'),(18,'301','TAKEOFF','Collision with Objects/Animals'),
        (19,'302','TAKEOFF','Departure Stall on Takeoff'),(20,'400','FLIGHT','Stall and/or Spin'),
        (21,'401','FLIGHT','Loss of Control (VFR)'),(22,'402','FLIGHT','Loss of Control (IMC)'),
        (23,'403','FLIGHT','Continued VFR Flight Into IMC'),(24,'404','FLIGHT','Weather (Tstorm.Lightning.Hail)'),
        (25,'405','FLIGHT','Weather (Icing)'),(26,'406','FLIGHT','Fuel Exhaustion or Starvation'),
        (27,'407','FLIGHT','Collision with other Aircraft'),(28,'408','FLIGHT','Collision with Structures'),
        (29,'409','FLIGHT','Collision with Birds'),(30,'410','FLIGHT','Engine Failure (Mechanical)'),
        (31,'411','FLIGHT','Engine Failure (Induced)'),(32,'412','FLIGHT','Engine Component Failure'),
        (33,'413','FLIGHT','Aircraft Component Failure'),(34,'414','FLIGHT','Aircraft Structural Failure'),
        (35,'415','FLIGHT','Controlled Flight into Terrain'),(36,'416','FLIGHT','Other'),
        (37,'500','LANDING','Hard Landing'),(38,'501','LANDING','Loss of Directional Control'),
        (39,'502','LANDING','Undershoot / Overshoot'),(40,'503','LANDING','Gear Up'),
        (41,'504','LANDING','Gear Failure / Collapse'),(42,'505','LANDING','Improper IAP (DH / MDA)'),
        (43,'506','LANDING','Improper IAP (Missed Approach)'),(44,'507','LANDING','Go Around / Abort'),
        (45,'508','LANDING','Precautionary - Off Airport'),(46,'509','LANDING','Forced Landing Off Airport'),
        (47,'510','LANDING','Other'),(48,'600','OTHER','Premises'),
        (49,'601','OTHER','Products & Completed Ops'),(50,'602','OTHER','Hangarkeepers'),
        (51,'603','OTHER','General Liability'),(52,'700','CFI','Inadequate Supervision'),
        (53,'206','TAXI','Engine Fire During Start'),(54,'303','TAKEOFF','Other'),
        (55,'110','GNIM','Hurricane CHARLEY'),(56,'111','GNIM','Hurricane FRANCES'),
        (57,'112','GNIM','Hurricane IVAN'),(58,'113','GNIM','Hurricane JEANNE'),
        (59,'114','GNIM','Hurricane KATRINA'),(60,'115','GNIM','Hurricane RITA'),
        (61,'116','GNIM','Hurricane WILMA'),(62,'117','GNIM','Hurricane DOLLY'),
        (63,'118','GNIM','Hurricane GUSTAV'),(64,'119','GNIM','Hurricane IKE'),
        (65,'120','GNIM','HURRICANE SANDY 2012'),(67,'207','TAXI','FOD Ingestion'),
        (68,'121','GNIM','Hurricane MATTHEW'),(69,'304','TAKEOFF','Engine Failure'),
        (71,'122','GNIM','Hurricane HARVEY'),(72,'123','GNIM','Hurricane IRMA'),
        (73,'124','GNIM','Hurricane NATE');

    -- Known FAANo typos in claim records
    DECLARE @tv_FAATypos TABLE
    (
        ClmId            INT,
        Policy_No        VARCHAR(13),
        Aircraft_ID      VARCHAR(8),
        CLAIM_TYPE_DESC  VARCHAR(3),
        DOL              DATE,
        PolicyNo         VARCHAR(13),
        FAANo            VARCHAR(8)
    );
    INSERT INTO @tv_FAATypos VALUES
        (3898,'GA99-34045-01','N38778Y','ACH','2014-06-24','GA99-34045-01','N3878Y'),
        (3813,'GA99-29254-03','N325W',  'ACH','2014-01-19','GA99-29254-03','N315W'),
        (3559,'GA99-33449-00','N380KS', 'ACH','2012-10-08','GA99-33449-00','N380KC'),
        (3469,'GA99-28363-02','N3132Y', 'ACH','2012-05-17','GA99-28363-02','N3132V'),
        (3314,'GA99-30876-00','N960WN', 'ACH','2011-08-18','GA99-30876-00','N960WM'),
        (3293,'GA99-27693-02','N3237D', 'ACH','2011-07-08','GA99-27693-02','N3237P'),
        (3153,'GA99-28969-01','N2835H', 'ACH','2011-01-16','GA99-28969-01','N2853H'),
        (2972,'GA96-28811-00','N74TM',  'ACH','2010-04-22','GA96-28811-00','N74EM'),
        (2877,'GA99-22893-02','N4735D', 'ACH','2009-10-25','GA99-22893-02','N4753D'),
        (2753,'GA99-26804-00','N740E',  'ACH','2009-04-23','GA99-26804-00','N7409E'),
        (2315,'GA99-24767-00','N8931L', 'ACH','2007-09-03','GA99-24767-00','N8139L'),
        (2115,'GA96-20842-00','N332SX', 'ACH','2006-12-16','GA96-20842-00','N32SX'),
        (1902,'GA96-21230-00','N7617N', 'ACH','2006-04-19','GA96-21230-00','N6717N'),
        (1898,'GA96-18521-01','N95219', 'ACH','2006-04-17','GA96-18521-01','N95129'),
        (1745,'GA96-18210-00','N3372G', 'ACH','2005-10-24','GA96-18210-00','N3372Q'),
        (1724,'GA96-19449-00','N113AV', 'ACH','2005-09-30','GA96-19449-00','N113AW'),
        (1673,'GA96-19244-00','N4274U', 'ACH','2005-08-18','GA96-19244-00','N4274Y'),
        (1662,'GA96-18275-00','N3840G', 'ACH','2005-08-09','GA96-18275-00','N3840Q'),
        (1630,'GA96-20062-00','N86BA',  'ACH','2005-07-12','GA96-20062-00','N96BA'),
        (1459,'GA96-17106-00','N20592', 'ACH','2004-12-05','GA96-17106-00','N30592'),
        (1714,'GA96-13105-00','N217SA', 'ACH','2004-08-25','GA96-13105-00','N2175A'),
        (1268,'GA96-12179-00','N298JW', 'ACH','2004-06-24','GA96-12179-00','N198JW'),
        (1088,'GA96-11058-00','N747LE', 'ACH','2003-12-08','GA96-11058-00','N747LF'),
        (755, 'GA94-09536-00','N4854E', 'ACH','2002-12-16','GA94-09536-00','N4864E'),
        (715, 'GA94-06452-00','N9692T', 'ACH','2002-10-20','GA94-06452-00','N9296T'),
        (763, 'GA96-07906-00','N77975N','ACH','2002-10-03','GA96-07906-00','N7975N'),
        (569, 'GA94-06065-00','N6698W', 'ACH','2002-05-09','GA94-06065-00','N6689W'),
        (558, 'GA96-05474-00','N4659V', 'ACH','2002-04-19','GA96-05474-00','N4659B'),
        (508, 'GA94-04533-00','N2690E', 'ACH','2002-02-19','GA94-04533-00','N2609E'),
        (422, 'GA96-05087-00','N6935A', 'ACH','2001-08-25','GA96-05087-00','N6539A'),
        (839, 'GA94-03736-00','N6276W', 'ACH','2001-07-21','GA94-03736-00','N6928X'),
        (368, 'GA94-03666-00','N6488W', 'ACH','2001-06-08','GA94-03666-00','N6588W'),
        (351, 'GA94-03648-00','N277TY', 'ACH','2001-05-24','GA94-03648-00','N277TV'),
        (277, 'GA94-02176-00','N71789',  'ACH','2001-03-16','GA94-02176-00','N51789'),
        (90,  'GA94-02715-00','N6375G', 'ACH','2001-02-09','GA94-02715-00','N63759'),
        (57,  'GA94-02957-00','N16609', 'ACH','2000-11-26','GA94-02957-00','N18609'),
        (47,  'GA94-01077-00','N2608T', 'ACH','2000-11-10','GA94-01077-00','N2068T'),
        (3898,'GA99-34045-01','N38778Y','ACL','2014-06-24','GA99-34045-01','N3878Y'),
        (3375,'GA99-23432-04','N90QL',  'ACL','2011-12-02','GA99-23432-04','N49CH'),
        (3201,'GA99-23043-04','N28WY',  'ACL','2011-04-06','GA99-23043-04','N125WY'),
        (3099,'GA99-30644-00','N3051L', 'ACL','2010-10-01','GA99-30644-00','  N3051L'),
        (3026,'GA99-29511-00','N7700',  'ACL','2010-06-26','GA99-29511-00','N7700V'),
        (4036,'GA99-35616-00','Cessna', 'ACH','2015-03-30','GA99-35616-00','N738AY');

    -- Known claims with no aircraft type in system (manually mapped)
    DECLARE @tv_NoAircraftType TABLE
    (
        [Claim No]  VARCHAR(255),
        FAANo       VARCHAR(7),
        Aircrafttype INT,
        ModelCode   VARCHAR(255),
        Model       VARCHAR(255),
        Gear        VARCHAR(255),
        Wing        VARCHAR(255)
    );
    INSERT INTO @tv_NoAircraftType VALUES
        ('CA22287','N1031U',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA20228','N1036V',1,'CE172XP','R172K','T','Fixed'),
        ('CA22350','N1070U',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA24228','N135LE',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA25273','N135LE',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA22261','N14SS',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA23372','N14SS',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA24389','N15886',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA25298','N16573',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA20253','N238Z',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA26341','N31982',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA25385','N333SE',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA21136','N38844',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA21240','N38844',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA23282','N39794',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA23414','N39794',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA25161','N42752',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA25420','N43397',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA26108','N4495T',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA24130','N44LJ',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA27262','N56000',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA25129','N56880',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA23375','N680WS',12,'AC680FL','680FL','R','Fixed'),
        ('CA21165','N6961F',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA26132','N8222B',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA27107','N8231D',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA21284','N92SA',10,'PA34200I','PA34 200','R','Fixed'),
        ('CA29124','N8047C',11,'PA34200II','PA34 200T','R','Fixed'),
        ('CA27188','N92993',14,'HILL12C','UH 12C','S','Rotor');

    -- =========================================================================
    -- Section 8 – Claims detail from Icarus
    -- =========================================================================
    IF OBJECT_ID('tempdb..#CLAIMS_SUB') IS NOT NULL DROP TABLE #CLAIMS_SUB;

    SELECT
        CH.[Claim No],
        CD.ClmDtlId,
        CH.CLMID,
        CD.CId                                          AS CLAIM_TYPE,
        PCId1,
        [Tre Code]                                      AS treaty_id,
        [Policy No],
        CASE WHEN F.ClmId IS NOT NULL THEN F.FAANo ELSE CH.[Aircraft ID] END AS [Aircraft ID],
        CASE CD.CId WHEN 1 THEN 'ACH' WHEN 2 THEN 'ACL' WHEN 3 THEN 'APL' END AS CLAIM_TYPE_DESC,
        CONVERT(VARCHAR(12), CH.DOL, 101)               AS DOL,
        YEAR(CH.DOL)                                    AS AccYear,
        CASE WHEN MONTH(CH.DOL) <= 6
             THEN CONCAT(CAST(YEAR(CH.DOL) AS VARCHAR(4)),'-1')
             ELSE CONCAT(CAST(YEAR(CH.DOL) AS VARCHAR(4)),'-2') END AS AccHalfYear,
        CASE WHEN MONTH(CH.DOL) <= 3 THEN 1 WHEN MONTH(CH.DOL) <= 6 THEN 2
             WHEN MONTH(CH.DOL) <= 9 THEN 3 ELSE 4 END AS AccQuarter,
        MONTH(CH.DOL)                                   AS AccMonth,
        CONVERT(VARCHAR(12), CD.[Trans Date], 101)      AS TRANS_DATE,
        YEAR(CD.[Trans Date])                           AS TransYear,
        CASE WHEN MONTH(CD.[Trans Date]) <= 6
             THEN CONCAT(CAST(YEAR(CD.[Trans Date]) AS VARCHAR(4)),'-1')
             ELSE CONCAT(CAST(YEAR(CD.[Trans Date]) AS VARCHAR(4)),'-2') END AS TransHalfYear,
        CASE WHEN MONTH(CD.[Trans Date]) <= 3 THEN 1 WHEN MONTH(CD.[Trans Date]) <= 6 THEN 2
             WHEN MONTH(CD.[Trans Date]) <= 9 THEN 3 ELSE 4 END AS TransQuarter,
        MONTH(CD.[Trans Date])                          AS TransMonth,
        CONVERT(VARCHAR(12), CH.Reported, 101)          AS REPORTED_DATE,
        YEAR(CH.Reported)                               AS ReportedYear,
        CASE WHEN MONTH(CH.Reported) <= 6
             THEN CONCAT(CAST(YEAR(CH.Reported) AS VARCHAR(4)),'-1')
             ELSE CONCAT(CAST(YEAR(CH.Reported) AS VARCHAR(4)),'-2') END AS ReportedHalfYear,
        CASE WHEN MONTH(CH.Reported) <= 3 THEN 1 WHEN MONTH(CH.Reported) <= 6 THEN 2
             WHEN MONTH(CH.Reported) <= 9 THEN 3 ELSE 4 END AS ReportedQuarter,
        MONTH(CH.Reported)                              AS ReportedMonth,
        CONVERT(VARCHAR(12), CH.[Close Date], 101)      AS [Close Date],
        YEAR(CH.[Close Date])                           AS CloseYear,
        CASE WHEN MONTH(CH.[Close Date]) <= 6
             THEN CONCAT(CAST(YEAR(CH.[Close Date]) AS VARCHAR(4)),'-1')
             ELSE CONCAT(CAST(YEAR(CH.[Close Date]) AS VARCHAR(4)),'-2') END AS CloseHalfYear,
        CASE WHEN MONTH(CH.[Close Date]) <= 3 THEN 1 WHEN MONTH(CH.[Close Date]) <= 6 THEN 2
             WHEN MONTH(CH.[Close Date]) <= 9 THEN 3 ELSE 4 END AS CloseQuarter,
        MONTH(CH.[Close Date])                          AS CloseMonth,
        CH.State                                        AS CLAIM_STATE,
        CH.Comment,
        ISNULL(CD.Reserve, 0)                           AS incurredLoss,
        ISNULL(CD.Paid, 0)                              AS Paid,
        ISNULL(CD.[Recovery], 0)                        AS [Recovery],
        ISNULL(CD.Reserve, 0) - ISNULL(CD.[Recovery], 0) AS NetInc,
        ISNULL(CD.Paid, 0)    - ISNULL(CD.[Recovery], 0) AS NetPaid,
        CASE WHEN CD.[I Code] = 400 THEN 'ULAE'
             WHEN CD.[I Code] = 401 THEN 'ALAE'
             ELSE 'Loss' END                            AS exp_ind
    INTO #CLAIMS_SUB
    FROM [HSQ-DB01].[Icarus].dbo.[Claims Dtl]  CD
    INNER JOIN [HSQ-DB01].[Icarus].dbo.[Claim Hdr] CH ON CD.ClmId = CH.ClmId
    LEFT  JOIN [HSQ-DB01].[Icarus].dbo.Treaty   t  ON CH.TreId  = t.TId
    LEFT  JOIN @tv_FAATypos                     AS F
           ON CH.ClmId      = F.ClmId
          AND CH.[Policy No] = F.Policy_No
          AND CD.CId = CASE WHEN F.CLAIM_TYPE_DESC = 'ACH' THEN 1
                            WHEN F.CLAIM_TYPE_DESC = 'ACL' THEN 2
                            WHEN F.CLAIM_TYPE_DESC = 'APL' THEN 3
                            ELSE 0 END
    WHERE CD.[Trans Date] <= @ed;

    -- Apply known-FAANo aircraft-type overrides
    UPDATE H
    SET H.[Aircraft ID] = C.FAANo
    FROM #CLAIMS_SUB    AS H
    INNER JOIN @tv_NoAircraftType AS C ON H.[Claim No] = C.[Claim No];

    -- =========================================================================
    -- Section 9 – Match ACH claims to aircraft policy records
    -- =========================================================================
    IF OBJECT_ID('tempdb..#ACH_CLAIMS_W_POLICYSUB_MATCH') IS NOT NULL
        DROP TABLE #ACH_CLAIMS_W_POLICYSUB_MATCH;

    SELECT
        CLAIMS.*,
        PS.*,
        CASE WHEN PC.PcCode IS NULL THEN 0 ELSE 1 END AS HasClaim,
        PC.PcCode                                      AS ClaimCauseId,
        PC.PcReasonGroup                               AS ClaimCauseGroup,
        PC.PcReason                                    AS ClaimCause,
        CASE WHEN PC.PcCode IS NULL THEN 0 ELSE PS.HullValue_AgreedValue END AS ClaimHullValue,
        0                                              AS FIXED,
        [Policy No]                                    AS FIXED_CLAIMS_POLICYNO,
        PS.AIRCRAFTID                                  AS FIXED_AIRCRAFTID,
        PS.POLID                                       AS FIXED_POLID,
        [Aircraft ID]                                  AS FIXED_CLAIMS_FAANO,
        0                                              AS FIXED_AIRCRAFTTYPE,
        PS.MODELID                                     AS FIXED_MODELID,
        ''                                             AS FIXED_GEAR,
        ''                                             AS FIXED_WING
    INTO #ACH_CLAIMS_W_POLICYSUB_MATCH
    FROM #CLAIMS_SUB AS CLAIMS
    INNER JOIN #AIRCRAFT_Policy_Sub AS PS
           ON PS.PolicyNo = CLAIMS.[Policy No]
          AND PS.FAANo    = CASE WHEN CLAIMS.ClmId = 4036 AND CLAIMS.[Aircraft ID] = 'CESSNA'
                                 THEN 'N738AY' ELSE CLAIMS.[Aircraft ID] END
    LEFT  JOIN @tv_ProbableCause AS PC ON CLAIMS.PCId1 = PC.PcId
    WHERE CLAIMS.CLAIM_TYPE_DESC = 'ACH'
      AND PS.FAANo NOT IN ('N/A','NA','TBA','VARIOUS')
      AND PS.FAANo IS NOT NULL;

    -- Apply aircraft-type corrections from @tv_NoAircraftType
    UPDATE H
    SET H.AIRCRAFTTYPE          = ISNULL(H.AIRCRAFTTYPE, C.Aircrafttype),
        H.ModelCode             = ISNULL(H.ModelCode, C.ModelCode),
        H.Model                 = ISNULL(H.Model, C.Model),
        H.Gear                  = ISNULL(H.Gear, C.Gear),
        H.Wing                  = ISNULL(H.Wing, C.Wing)
    FROM #ACH_CLAIMS_W_POLICYSUB_MATCH AS H
    INNER JOIN @tv_NoAircraftType AS C ON H.[Claim No] = C.[Claim No] AND H.FAANo = C.FAANo;

    -- Remove known duplicate aircraft rows (incorrect aircraft IDs)
    DELETE FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
    WHERE (ClmId = 2899 AND AircraftID = 4687)
       OR (ClmId = 691  AND AircraftID = 124231);

    -- For remaining duplicates per ClmDtlId, keep the row with the highest AircraftID
    ;WITH cte_dupes AS
    (
        SELECT ClmDtlId, MAX(AircraftID) AS keep_id
        FROM #ACH_CLAIMS_W_POLICYSUB_MATCH
        GROUP BY ClmDtlId
        HAVING COUNT(1) > 1
    )
    DELETE m
    FROM #ACH_CLAIMS_W_POLICYSUB_MATCH m
    INNER JOIN cte_dupes d ON m.ClmDtlId = d.ClmDtlId AND m.AircraftID <> d.keep_id;

    -- =========================================================================
    -- Section 10 – Build insured lookup (used in unmatched claim resolution)
    -- =========================================================================
    IF OBJECT_ID('tempdb..#INSURED_POLID') IS NOT NULL DROP TABLE #INSURED_POLID;

    SELECT DISTINCT I.SubID, I.Insured, P.PolID, P.PPolID
    INTO #INSURED_POLID
    FROM [HSQ-DB01].[NPC_AIM].dbo.tblInsureds AS I
    INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P ON I.SubID = P.SubID;

    -- =========================================================================
    -- Section 11 – Unmatched ACH claims (non-existing policy)
    -- =========================================================================
    IF OBJECT_ID('tempdb..#ACH_CLAIMS_NO_POLICYSUB_MATCH') IS NOT NULL
        DROP TABLE #ACH_CLAIMS_NO_POLICYSUB_MATCH;

    SELECT ClmId, [Claim No], [Policy No],
           ISNULL([Aircraft ID], '') AS [Aircraft ID],
           CLAIM_TYPE_DESC,
           CAST(DOL AS DATE) AS DOL,
           SUM(NetInc) AS NetInc
    INTO #ACH_CLAIMS_NO_POLICYSUB_MATCH
    FROM #CLAIMS_SUB AS CLAIMS
    LEFT  JOIN #AIRCRAFT_Policy_Sub AS PS
           ON PS.PolicyNo = CLAIMS.[Policy No] AND PS.FAANo = CLAIMS.[Aircraft ID]
    WHERE PS.PolicyNo IS NULL
      AND CLAIMS.CLAIM_TYPE_DESC = 'ACH'
      AND CLAIMS.ClmId NOT IN (SELECT DISTINCT ClmId FROM #ACH_CLAIMS_W_POLICYSUB_MATCH)
    GROUP BY ClmId, [Claim No], [Policy No], [Aircraft ID], CLAIM_TYPE_DESC, CAST(DOL AS DATE);

    -- Resolve claims with non-existing policy numbers via FAANo→AircraftID lookup
    IF OBJECT_ID('tempdb..#ACH_CLAIMS_NONEXISTING_POLICYNO') IS NOT NULL
        DROP TABLE #ACH_CLAIMS_NONEXISTING_POLICYNO;

    SELECT H.*, F.*,
           TAM.Category AS AIRCRAFTTYPE, TAM.Gear, TAM.Wing,
           CONVERT(VARCHAR, TAM.Category) + ' - ' + TAT.[Type] AS AircraftTypeNameDisplay,
           TA.HullAge, TA.HullValue,
           CASE WHEN PC.PcCode IS NULL THEN 0 ELSE 1 END AS HasClaim,
           PC.PcCode     AS ClaimCauseId,
           PC.PcReasonGroup AS ClaimCauseGroup,
           PC.PcReason   AS ClaimCause,
           CASE WHEN PC.PcCode IS NULL THEN 0 ELSE TA.HullValue END AS ClaimHullValue
    INTO #ACH_CLAIMS_NONEXISTING_POLICYNO
    FROM (
        SELECT H2.*, CLAIMS.PCId1
        FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H2
        LEFT JOIN (SELECT DISTINCT ClmId, PCId1 FROM #CLAIMS_SUB) AS CLAIMS ON H2.ClmId = CLAIMS.ClmId
    ) AS H
    INNER JOIN #FAANo_MAX_AIRCRAFTID AS F
           ON H.[Aircraft ID] = CASE WHEN F.FAANo IN ('N/A','NA','TBA','VARIOUS') THEN '?' ELSE F.FAANo END
    INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft AS TA ON F.AircraftID = TA.AircraftID
    INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels AS TAM ON TA.ModelID = TAM.ModelID
    INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftTypes  AS TAT ON TAM.Category = TAT.ID
    LEFT  JOIN @tv_ProbableCause AS PC ON H.PCId1 = PC.PcId
    WHERE H.[Policy No] NOT IN (SELECT DISTINCT PolicyNo FROM #AIRCRAFT_Policy_Sub);

    -- Resolve claims with correct FAANo but wrong PolicyNo
    IF OBJECT_ID('tempdb..#ACH_CLAIMS_INCORRECT_POLICYNO') IS NOT NULL
        DROP TABLE #ACH_CLAIMS_INCORRECT_POLICYNO;

    SELECT X.*,
           CASE WHEN X.POLID = I.PPolID THEN 1 ELSE 0 END AS NEED_PREV_POLICY,
           CASE WHEN X.CLAIMS_POLID = 146102 THEN 4 ELSE TAM.Category END AS AIRCRAFTTYPE,
           TAM.Gear, TAM.Wing,
           CONVERT(VARCHAR, TAM.Category) + ' - ' + TAT.[Type] AS AircraftTypeNameDisplay,
           TA.HullAge, TA.HullValue,
           CASE WHEN PC.PcCode IS NULL THEN 0 ELSE 1 END AS HasClaim,
           PC.PcCode AS ClaimCauseId, PC.PcReasonGroup AS ClaimCauseGroup, PC.PcReason AS ClaimCause,
           CASE WHEN PC.PcCode IS NULL THEN 0 ELSE TA.HullValue END AS ClaimHullValue
    INTO #ACH_CLAIMS_INCORRECT_POLICYNO
    FROM #INSURED_POLID AS I
    INNER JOIN (
        SELECT P.PolicyNo AS CLAIMS_POLICYNO, P.PolID AS CLAIMS_POLID,
               H.*, F.*, CLAIMS.PCId1
        FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH AS H
        INNER JOIN #FAANo_MAX_AIRCRAFTID AS F ON H.[Aircraft ID] = F.FAANo
        INNER JOIN [HSQ-DB01].[NPC_AIM].dbo.tblPolicy AS P ON H.[Policy No] = P.PolicyNo
        LEFT  JOIN (SELECT DISTINCT ClmId, PCId1 FROM #CLAIMS_SUB) AS CLAIMS ON H.ClmId = CLAIMS.ClmId
        WHERE H.[Policy No] IN (SELECT DISTINCT PolicyNo FROM #AIRCRAFT_Policy_Sub)
    ) AS X ON X.CLAIMS_POLID = I.PolID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].dbo.tblAircraft      AS TA  ON X.AircraftID = TA.AircraftID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftModels AS TAM
           ON CASE WHEN TA.AIRCRAFTID = 150614 THEN 854 ELSE TA.ModelID END = TAM.ModelID
    LEFT  JOIN [HSQ-DB01].[NPC_AIM].dbo.tlkAircraftTypes  AS TAT ON TAM.Category = TAT.ID
    LEFT  JOIN @tv_ProbableCause AS PC ON X.PCId1 = PC.PcId;

    -- Remove resolved claims from the unmatched table
    DELETE FROM #ACH_CLAIMS_NO_POLICYSUB_MATCH
    WHERE ClmId IN (SELECT DISTINCT ClmId FROM #ACH_CLAIMS_NONEXISTING_POLICYNO)
       OR ClmId IN (SELECT DISTINCT ClmId FROM #ACH_CLAIMS_INCORRECT_POLICYNO);

    -- =========================================================================
    -- Section 12 – Final aggregation and write to test_aim_loss_ulae
    --   TRUNCATE then INSERT preserves the table structure and audit defaults.
    -- =========================================================================
    IF OBJECT_ID('tempdb..#completeach') IS NOT NULL DROP TABLE #completeach;

    SELECT
        -- Claim identification
        PS.PolID      AS polid,
        CS.[Claim No],
        CS.ClmId,
        CS.CLAIM_TYPE,
        CS.CLAIM_TYPE_DESC,
        CS.[Policy No]          AS [policy no],
        CS.treaty_id,
        CS.DOL,
        CS.AccYear              AS AY,
        CS.AccMonth             AS mth_loss,
        CS.AccQuarter           AS qtr_loss,
        CS.REPORTED_DATE,
        CS.ReportedMonth        AS mth_rept,
        CS.ReportedQuarter      AS qtr_rept,
        CS.[Close Date],
        CS.CloseMonth           AS mth_close,
        CS.CloseQuarter         AS qtr_close,
        T.mth_val,
        -- Quarter valuation derived from mth_val
        CAST(LEFT(CAST(T.mth_val AS VARCHAR(6)),4) AS INT) * 10
            + CASE WHEN CAST(RIGHT(CAST(T.mth_val AS VARCHAR(6)),2) AS INT) <= 3 THEN 1
                   WHEN CAST(RIGHT(CAST(T.mth_val AS VARCHAR(6)),2) AS INT) <= 6 THEN 2
                   WHEN CAST(RIGHT(CAST(T.mth_val AS VARCHAR(6)),2) AS INT) <= 9 THEN 3
                   ELSE 4 END      AS qtr_val,
        -- Development lags
        (CAST(LEFT(CAST(T.mth_val AS VARCHAR(6)),4) AS INT)
            - CAST(LEFT(CS.mth_loss,4) AS INT)) * 12
            + CAST(RIGHT(CAST(T.mth_val AS VARCHAR(6)),2) AS INT)
            - CAST(RIGHT(CS.mth_loss,2) AS INT)   AS mth_dev,
        -- Claim type / aircraft
        CS.CLAIM_STATE,
        PS.AircraftID,
        PS.FAANo,
        PS.AircraftType,
        PS.Gear,
        PS.Wing,
        PS.AircraftTypeNameDisplay,
        PS.HullAge,
        PS.HullValue_AgreedValue,
        PS.HasClaim,
        PS.ClaimCauseGroup,
        PS.ClaimCause,
        PS.ClaimHullValue,
        -- Loss by expense type
        SUM(CASE WHEN CS.exp_ind = 'ULAE' THEN CS.incurredLoss ELSE 0 END) AS incd_ulae,
        SUM(CASE WHEN CS.exp_ind = 'ULAE' THEN CS.Paid         ELSE 0 END) AS paid_ulae,
        SUM(CASE WHEN CS.exp_ind = 'ALAE' THEN CS.incurredLoss ELSE 0 END) AS incd_alae,
        SUM(CASE WHEN CS.exp_ind = 'ALAE' THEN CS.Paid         ELSE 0 END) AS paid_alae,
        SUM(CASE WHEN CS.exp_ind = 'Loss' THEN CS.incurredLoss ELSE 0 END) AS incd_loss,
        SUM(CASE WHEN CS.exp_ind = 'Loss' THEN CS.Paid         ELSE 0 END) AS paid_loss,
        SUM(CASE WHEN CS.exp_ind = 'Loss' THEN CS.NetInc       ELSE 0 END) AS net_incd_loss,
        SUM(CASE WHEN CS.exp_ind = 'Loss' THEN CS.NetPaid      ELSE 0 END) AS net_paid_loss,
        -- CAT info
        CASE WHEN CH.D55_CAT_CODE IS NULL OR CH.D55_CAT_CODE = 'NULL' THEN 0 ELSE 1 END AS CAT_indicator,
        CH.D55_CAT_CODE,
        -- Claim status
        CH.clm_status1, CH.clm_status2, CH.clm_status3,
        WHAT_TABLE = 'ALL MATCH'
    INTO #completeach
    FROM #ACH_CLAIMS_W_POLICYSUB_MATCH PS
    INNER JOIN #CLAIMS_SUB CS ON PS.ClmId = CS.ClmId AND CS.CLAIM_TYPE_DESC = 'ACH'
    CROSS JOIN #triangle T
    LEFT JOIN [HSQ-DB01].[Icarus].dbo.[Claim Hdr] CH ON CS.ClmId = CH.ClmId
    WHERE CAST(CS.AccYear AS VARCHAR(4)) + RIGHT('0' + CAST(CS.AccMonth AS VARCHAR(2)),2)
          <= CAST(T.mth_val AS VARCHAR(6))
    GROUP BY
        PS.PolID, CS.[Claim No], CS.ClmId, CS.CLAIM_TYPE, CS.CLAIM_TYPE_DESC,
        CS.[Policy No], CS.treaty_id, CS.DOL, CS.AccYear, CS.AccMonth,
        CS.AccQuarter, CS.REPORTED_DATE, CS.ReportedMonth, CS.ReportedQuarter,
        CS.[Close Date], CS.CloseMonth, CS.CloseQuarter, T.mth_val,
        CS.CLAIM_STATE, PS.AircraftID, PS.FAANo, PS.AircraftType, PS.Gear,
        PS.Wing, PS.AircraftTypeNameDisplay, PS.HullAge, PS.HullValue_AgreedValue,
        PS.HasClaim, PS.ClaimCauseGroup, PS.ClaimCause, PS.ClaimHullValue,
        CH.D55_CAT_CODE, CH.clm_status1, CH.clm_status2, CH.clm_status3;

    -- Write to test table: TRUNCATE preserves structure; INSERT fills it
    TRUNCATE TABLE dbo.test_aim_loss_ulae;

    INSERT INTO dbo.test_aim_loss_ulae
    (
        polid, [Claim No], Clmid, CLAIM_TYPE, CLAIM_TYPE_DESC, [policy no],
        treaty_id, Claim_state, DOL, AY, mth_loss, qtr_loss,
        REPORTED_DATE, mth_rept, qtr_rept, [Close Date], mth_close, qtr_close,
        mth_val, qtr_val, mth_dev, AircraftID, FAANo, AircraftType, Gear, Wing,
        AircraftTypeNameDisplay, HullAge, HullValue_AgreedValue,
        HasClaim, ClaimCauseGroup, ClaimCause, ClaimHullValue,
        CAT_indicator, D55_CAT_CODE,
        paid_loss, paid_alae, paid_ulae, incd_loss, incd_alae, incd_ulae,
        net_paid_loss, net_incd_loss,
        clm_status1, clm_status2, clm_status3,
        WHAT_TABLE, row_hash, created_date, last_updated
    )
    SELECT
        polid, [Claim No], ClmId, CLAIM_TYPE, CLAIM_TYPE_DESC, [policy no],
        treaty_id, CLAIM_STATE, CAST(DOL AS DATE), AY, mth_loss, qtr_loss,
        REPORTED_DATE, mth_rept, qtr_rept, [Close Date], mth_close, qtr_close,
        mth_val, qtr_val, mth_dev, AircraftID, FAANo, AircraftType, Gear, Wing,
        AircraftTypeNameDisplay, HullAge, HullValue_AgreedValue,
        HasClaim, ClaimCauseGroup, ClaimCause, ClaimHullValue,
        CAT_indicator, D55_CAT_CODE,
        paid_loss, paid_alae, paid_ulae, incd_loss, incd_alae, incd_ulae,
        net_paid_loss, net_incd_loss,
        clm_status1, clm_status2, clm_status3,
        WHAT_TABLE,
        CONVERT(BINARY(32), HASHBYTES('SHA2_256',
            CONCAT_WS('|',
                CAST(mth_val        AS NVARCHAR(10)),
                CAST(AY             AS NVARCHAR(10)),
                CAST(incd_loss      AS NVARCHAR(30)),
                CAST(paid_loss      AS NVARCHAR(30)),
                CAST(incd_ulae      AS NVARCHAR(30)),
                CAST(paid_ulae      AS NVARCHAR(30))
            )
        )),
        GETDATE(), GETDATE()
    FROM #completeach;

    DROP TABLE #completeach;

    DECLARE @PROC_NAME VARCHAR(MAX) = OBJECT_NAME(@@PROCID);
    EXEC UPDATE_QUERY_TIMES @PROC_NAME, @startTime;

END TRY
BEGIN CATCH
    SELECT OBJECT_NAME(@@PROCID) AS ERROR, ERROR_MESSAGE() AS ERRORMESSAGE;
END CATCH
GO
