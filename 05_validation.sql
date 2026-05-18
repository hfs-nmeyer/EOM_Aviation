USE [Pricing_AIM]
GO

/*=============================================================================
  05_validation.sql
  Purpose : Compare test_ table outputs against the original production tables
            for the current prior-month period.

  Run after executing all test_ stored procedures.

  Sections:
    1. Row-count comparison (all tables)
    2. Premium totals comparison (financial spot-check)
    3. Rows in production but NOT in test (missing from test run)
    4. Rows in test but NOT in production (new in test run)
    5. Rows present in both but with changed financial values (hash mismatch)
    6. Coverage-group distribution comparison (Diamond EP)
    7. STT ratio summary comparison (aim_STT / test_aim_STT)
=============================================================================*/

SET NOCOUNT ON;

DECLARE @Year  INT = DATEPART(YEAR,  DATEADD(MONTH, -1, GETDATE()));
DECLARE @Month INT = DATEPART(MONTH, DATEADD(MONTH, -1, GETDATE()));

PRINT CONCAT('Validating for Year=', @Year, '  Month=', @Month);
PRINT REPLICATE('-', 70);

-- ============================================================================
-- 1. ROW-COUNT COMPARISON
-- ============================================================================
PRINT '1. Row counts';

SELECT
    src                     AS [Table],
    row_count               AS [Row Count]
FROM (
    SELECT 'prod: DiamondEarnedPremium_Aviation_JChenVScopy' AS src,
           COUNT(*)                                           AS row_count
    FROM dbo.DiamondEarnedPremium_Aviation_JChenVScopy
    WHERE [Year] = @Year AND AcctPer = @Month

    UNION ALL
    SELECT 'test: test_DiamondEarnedPremium_Aviation_JChenVScopy',
           COUNT(*)
    FROM dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy
    WHERE [Year] = @Year AND AcctPer = @Month

    UNION ALL
    SELECT 'prod: AIM_Apollo_Loss',
           COUNT(*)
    FROM dbo.AIM_Apollo_Loss
    WHERE [Year] = @Year AND [Month] = @Month

    UNION ALL
    SELECT 'test: test_AIM_Apollo_Loss',
           COUNT(*)
    FROM dbo.test_AIM_Apollo_Loss
    WHERE [Year] = @Year AND [Month] = @Month

    UNION ALL
    SELECT 'prod: aim_loss_data',
           COUNT(*)
    FROM dbo.aim_loss_data

    UNION ALL
    SELECT 'test: test_aim_loss_data',
           COUNT(*)
    FROM dbo.test_aim_loss_data

    UNION ALL
    SELECT 'prod: Diamond_Airport_Table',
           COUNT(*)
    FROM dbo.Diamond_Airport_Table

    UNION ALL
    SELECT 'test: test_Diamond_Airport_Table',
           COUNT(*)
    FROM dbo.test_Diamond_Airport_Table

    UNION ALL
    SELECT 'prod: aim_diamond_STT',
           COUNT(*)
    FROM dbo.aim_diamond_STT

    UNION ALL
    SELECT 'test: test_aim_diamond_STT',
           COUNT(*)
    FROM dbo.test_aim_diamond_STT

    UNION ALL
    SELECT 'prod: aim_STT',
           COUNT(*)
    FROM dbo.aim_STT

    UNION ALL
    SELECT 'test: test_aim_STT',
           COUNT(*)
    FROM dbo.test_aim_STT
) counts
ORDER BY src;


-- ============================================================================
-- 2. PREMIUM TOTALS — DiamondEarnedPremium (current period)
-- ============================================================================
PRINT '2. Diamond EP premium totals';

SELECT
    'prod'                      AS src,
    SUM(premium_written_mtd)    AS written_mtd,
    SUM(premium_earned_mtd)     AS earned_mtd,
    SUM(premium_unearned)       AS unearned,
    SUM(premium_written)        AS written_ytd
FROM dbo.DiamondEarnedPremium_Aviation_JChenVScopy
WHERE [Year] = @Year AND AcctPer = @Month

UNION ALL

SELECT
    'test',
    SUM(premium_written_mtd),
    SUM(premium_earned_mtd),
    SUM(premium_unearned),
    SUM(premium_written)
FROM dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy
WHERE [Year] = @Year AND AcctPer = @Month;


-- ============================================================================
-- 3. PREMIUM TOTALS — aim_diamond_STT
-- ============================================================================
PRINT '3. aim_diamond_STT premium totals';

SELECT 'prod' AS src, SUM(prem_written) AS prem_written, SUM(prem_annual) AS prem_annual
FROM dbo.aim_diamond_STT
UNION ALL
SELECT 'test', SUM(prem_written), SUM(prem_annual)
FROM dbo.test_aim_diamond_STT;


-- ============================================================================
-- 4. PREMIUM TOTALS — aim_STT (combined Diamond + Apollo)
-- ============================================================================
PRINT '4. aim_STT premium totals';

SELECT 'prod' AS src, SUM(prem_written) AS prem_written, SUM(prem_annual) AS prem_annual
FROM dbo.aim_STT
UNION ALL
SELECT 'test', SUM(prem_written), SUM(prem_annual)
FROM dbo.test_aim_STT;


-- ============================================================================
-- 5. ROWS IN PROD BUT MISSING FROM TEST — DiamondEarnedPremium
-- ============================================================================
PRINT '5. Rows in prod DiamondEP not in test (current period)';

SELECT p.*
FROM dbo.DiamondEarnedPremium_Aviation_JChenVScopy p
WHERE p.[Year] = @Year AND p.AcctPer = @Month
  AND NOT EXISTS (
    SELECT 1
    FROM dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy t
    WHERE t.policy_id       = p.policy_id
      AND t.policyimage_num = p.policyimage_num
      AND t.unit_num        = p.unit_num
      AND t.coveragecode    = p.coveragecode
      AND t.[Year]          = p.[Year]
      AND t.AcctPer         = p.AcctPer
  );


-- ============================================================================
-- 6. ROWS IN TEST BUT MISSING FROM PROD — DiamondEarnedPremium
-- ============================================================================
PRINT '6. Rows in test DiamondEP not in prod (current period)';

SELECT t.*
FROM dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy t
WHERE t.[Year] = @Year AND t.AcctPer = @Month
  AND NOT EXISTS (
    SELECT 1
    FROM dbo.DiamondEarnedPremium_Aviation_JChenVScopy p
    WHERE p.policy_id       = t.policy_id
      AND p.policyimage_num = t.policyimage_num
      AND p.unit_num        = t.unit_num
      AND p.coveragecode    = t.coveragecode
      AND p.[Year]          = t.[Year]
      AND p.AcctPer         = t.AcctPer
  );


-- ============================================================================
-- 7. FINANCIAL DIFFERENCES — DiamondEarnedPremium matched rows
-- ============================================================================
PRINT '7. Matched DiamondEP rows with changed financials';

SELECT
    p.policy_id, p.policyimage_num, p.unit_num, p.coveragecode,
    p.premium_written_mtd  AS prod_written_mtd,
    t.premium_written_mtd  AS test_written_mtd,
    p.premium_earned_mtd   AS prod_earned_mtd,
    t.premium_earned_mtd   AS test_earned_mtd,
    p.premium_unearned     AS prod_unearned,
    t.premium_unearned     AS test_unearned
FROM dbo.DiamondEarnedPremium_Aviation_JChenVScopy p
INNER JOIN dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy t
    ON  p.policy_id       = t.policy_id
    AND p.policyimage_num = t.policyimage_num
    AND p.unit_num        = t.unit_num
    AND p.coveragecode    = t.coveragecode
    AND p.[Year]          = t.[Year]
    AND p.AcctPer         = t.AcctPer
WHERE p.[Year]   = @Year
  AND p.AcctPer  = @Month
  AND (
      ABS(ISNULL(p.premium_written_mtd, 0) - ISNULL(t.premium_written_mtd, 0)) > 0.01
   OR ABS(ISNULL(p.premium_earned_mtd,  0) - ISNULL(t.premium_earned_mtd,  0)) > 0.01
   OR ABS(ISNULL(p.premium_unearned,    0) - ISNULL(t.premium_unearned,    0)) > 0.01
  )
ORDER BY ABS(ISNULL(p.premium_written_mtd, 0) - ISNULL(t.premium_written_mtd, 0)) DESC;


-- ============================================================================
-- 8. COVERAGE-GROUP DISTRIBUTION — DiamondEarnedPremium
-- ============================================================================
PRINT '8. Coverage-group distribution (current period)';

SELECT
    ISNULL(p.CoverageCodeGrouped, '(null)') AS CoverageGroup,
    SUM(p.premium_written_mtd)              AS prod_written_mtd,
    SUM(t.premium_written_mtd)              AS test_written_mtd,
    SUM(p.premium_written_mtd) - SUM(t.premium_written_mtd) AS diff
FROM dbo.DiamondEarnedPremium_Aviation_JChenVScopy p
FULL OUTER JOIN dbo.test_DiamondEarnedPremium_Aviation_JChenVScopy t
    ON  p.CoverageCodeGrouped = t.CoverageCodeGrouped
    AND p.[Year] = t.[Year]
    AND p.AcctPer = t.AcctPer
WHERE ISNULL(p.[Year], t.[Year])   = @Year
  AND ISNULL(p.AcctPer, t.AcctPer) = @Month
GROUP BY ISNULL(p.CoverageCodeGrouped, t.CoverageCodeGrouped)
ORDER BY CoverageGroup;


-- ============================================================================
-- 9. STT RATIO SUMMARY — aim_STT
-- ============================================================================
PRINT '9. STT ratio summary (aim_STT vs test_aim_STT)';

SELECT
    'prod'          AS src,
    AVG(STT)        AS avg_STT,
    AVG(r_STT)      AS avg_r_STT,
    AVG(rr_STT)     AS avg_rr_STT,
    COUNT(*)        AS row_count
FROM dbo.aim_STT
WHERE STT IS NOT NULL AND STT <> 0

UNION ALL

SELECT
    'test',
    AVG(STT),
    AVG(r_STT),
    AVG(rr_STT),
    COUNT(*)
FROM dbo.test_aim_STT
WHERE STT IS NOT NULL AND STT <> 0;
