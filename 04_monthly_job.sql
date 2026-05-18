USE [msdb]
GO

/*=============================================================================
  04_monthly_job.sql
  Purpose : Create a SQL Server Agent job that runs the EOM_Aviation stored
            procedures in the correct sequence on the first business day of
            each month (targeting test_ tables).

  Execution order:
    1. run_aim_backup
    2. run_AIM_Apollo_Loss
    3. run_Diamond_WP_EP
    4. run_AIMLoss
    5. run_Diamond_Airport_Table
    6. run_test_Diamond_Apollo

  Prerequisites:
    - All stored procedures must already exist in [Pricing_AIM].
    - The SQL Server Agent service must be running.
    - Run this script connected to 200-ACT-DBS-01.
=============================================================================*/

-- Drop job if it already exists so this script is idempotent
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'EOM_Aviation_Monthly_Test')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'EOM_Aviation_Monthly_Test', @delete_unused_schedule = 1;
END
GO

DECLARE @jobId UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name              = N'EOM_Aviation_Monthly_Test',
    @enabled               = 1,
    @description           = N'End-of-month aviation premium processing (test_ tables). Runs on the 1st of each month.',
    @notify_level_eventlog = 2,   -- On failure
    @notify_level_email    = 0,
    @category_name         = N'[Uncategorized (Local)]',
    @job_id                = @jobId OUTPUT;

-- Step 1: Backup
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'1 - Backup AIM',
    @step_id         = 1,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_aim_backup];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 3,  -- Go to next step
    @on_fail_action    = 2;  -- Quit with failure

-- Step 2: Apollo Loss
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'2 - AIM Apollo Loss',
    @step_id         = 2,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_test_AIM_Apollo_Loss];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 3,
    @on_fail_action    = 2;

-- Step 3: Diamond WP/EP
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'3 - Diamond Written/Earned Premium',
    @step_id         = 3,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_test_Diamond_WP_EP];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 3,
    @on_fail_action    = 2;

-- Step 4: AIM Loss
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'4 - AIM Loss',
    @step_id         = 4,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_test_AIMLoss];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 3,
    @on_fail_action    = 2;

-- Step 5: Diamond Airport Table
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'5 - Diamond Airport Table',
    @step_id         = 5,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_test_Diamond_Airport_Table];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 3,
    @on_fail_action    = 2;

-- Step 6: Diamond Apollo (main rating + STT)
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'6 - Diamond Apollo Rating',
    @step_id         = 6,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_test_Diamond_Apollo];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 3,
    @on_fail_action    = 2;

-- Step 7: AIM Status Policy (Apollo + Diamond policy-status dimension)
--   Depends on: pricing_aim.dbo.rr_aim_apollo (pre-loaded), [AHI-S06].Diamond
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'7 - AIM Status Policy',
    @step_id         = 7,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_test_AIM_Status_Pol];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 3,
    @on_fail_action    = 2;

-- Step 8: Rate Monitor Table (policy-level adequacy + monthly summary)
--   Depends on: test_aim_STT (step 6), test_aim_status_pol (step 7)
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @jobId,
    @step_name       = N'8 - Rate Monitor Table',
    @step_id         = 8,
    @command         = N'EXEC [Pricing_AIM].[dbo].[run_test_Rate_Monitor_Table];',
    @database_name   = N'Pricing_AIM',
    @subsystem       = N'TSQL',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action    = 2;  -- Quit with failure

-- Set starting step
EXEC msdb.dbo.sp_update_job
    @job_id        = @jobId,
    @start_step_id = 1;

-- Schedule: 1st of every month at 06:00 AM
EXEC msdb.dbo.sp_add_jobschedule
    @job_id               = @jobId,
    @name                 = N'Monthly_1st_6AM',
    @enabled              = 1,
    @freq_type            = 16,   -- Monthly
    @freq_interval        = 1,    -- Day 1 of the month
    @freq_subday_type     = 1,    -- At a specific time
    @freq_subday_interval = 0,
    @active_start_time    = 060000;  -- 06:00:00

-- Assign to the local server
EXEC msdb.dbo.sp_add_jobserver
    @job_id     = @jobId,
    @server_name = N'(LOCAL)';

GO

PRINT 'Job EOM_Aviation_Monthly_Test created successfully.';
