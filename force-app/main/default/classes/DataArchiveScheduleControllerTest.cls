@IsTest
private class DataArchiveScheduleControllerTest {

    // ─────────────────────────────────────────────────
    //  Test: getActiveSchedules returns records
    // ─────────────────────────────────────────────────
    @IsTest
    static void testGetActiveSchedules() {
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Account',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 30,
            Cron_Expression__c = '0 0 2 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '02:00',
            Day_Of_Week__c     = 'MON'
        );

        Test.startTest();
        List<DataArchiveScheduleController.ScheduleInfo> results =
            DataArchiveScheduleController.getActiveSchedules();
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should return at least one active schedule');
        System.assertEquals('Account', results[0].objectName);
    }

    // ─────────────────────────────────────────────────
    //  Test: getActiveSchedules returns empty when none
    // ─────────────────────────────────────────────────
    @IsTest
    static void testGetActiveSchedules_Empty() {
        Test.startTest();
        List<DataArchiveScheduleController.ScheduleInfo> results =
            DataArchiveScheduleController.getActiveSchedules();
        Test.stopTest();

        System.assert(results.isEmpty(), 'Should return empty when no active schedules');
    }

    // ─────────────────────────────────────────────────
    //  Test: getSchedulesForObject returns matching
    // ─────────────────────────────────────────────────
    @IsTest
    static void testGetSchedulesForObject() {
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Contact',
            Frequency__c       = 'WEEKLY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 60,
            Cron_Expression__c = '0 0 2 ? * MON',
            Status__c          = 'Active',
            Preferred_Time__c  = '09:00',
            Day_Of_Week__c     = 'MON'
        );

        Test.startTest();
        List<DataArchiveScheduleController.ScheduleInfo> results =
            DataArchiveScheduleController.getSchedulesForObject('Contact');
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should return schedules for Contact');
        System.assertEquals('Contact', results[0].objectName);
    }

    // ─────────────────────────────────────────────────
    //  Test: getSchedulesForObject returns empty
    // ─────────────────────────────────────────────────
    @IsTest
    static void testGetSchedulesForObject_Empty() {
        Test.startTest();
        List<DataArchiveScheduleController.ScheduleInfo> results =
            DataArchiveScheduleController.getSchedulesForObject('NoSuchObject__c');
        Test.stopTest();

        System.assert(results.isEmpty(), 'Should return empty list');
    }

    // ─────────────────────────────────────────────────
    //  Test: scheduleArchive with text filter (success)
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_TextFilter() {
        Test.startTest();
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'DAILY', 'Name', 0, 'TestAccount',
            '14:30', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return success message');
        System.assert(result.contains('Successfully'), 'Message should confirm schedule creation');
    }

    // ─────────────────────────────────────────────────
    //  Test: Duplicate schedule throws validation error
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_DuplicateValidation() {
        // First, create a real scheduled job so the existing schedule has a valid Job_Id
        Id jobId = System.schedule(
            'TestDupJob_' + Datetime.now().getTime(),
            '0 0 2 * * ?',
            new DataArchiveScheduler('Account', 'Name', 30, null)
        );
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Account',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'Name',
            Days__c            = 30,
            Cron_Expression__c = '0 30 14 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '14:30',
            Day_Of_Week__c     = null,
            Job_Id__c          = jobId
        );

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            DataArchiveScheduleController.scheduleArchive(
                'Account', 'DAILY', 'Name', 30, null,
                '14:30', null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('already exists'),
                'Error message should mention duplicate: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException for duplicate schedule');
    }

    // ─────────────────────────────────────────────────
    //  Test: Different criteria replaces existing (with real job)
    //  Covers lines 205-210: abort existing + delete + create new
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_ReplacesExistingSchedule() {
        // Create a real scheduled job for the first schedule
        Id jobId = System.schedule(
            'TestReplaceJob_' + Datetime.now().getTime(),
            '0 0 2 * * ?',
            new DataArchiveScheduler('Account', 'Name', 0, 'First')
        );

        // Insert a schedule record with the real Job_Id
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Account',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'Name',
            Days__c            = 0,
            Cron_Expression__c = '0 0 2 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '02:00',
            Day_Of_Week__c     = null,
            Job_Id__c          = jobId
        );

        Test.startTest();
        // Second schedule: same object+field but different frequency → replaces
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'MONTHLY', 'Name', 0, 'Second',
            '03:00', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('Successfully'), 'Should report success');

        // Old schedule should be deleted, new one should exist
        List<Data_Archive_Schedule__c> remaining = [
            SELECT Id, Frequency__c, Job_Id__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Date_Field__c = 'Name'
            AND Status__c = 'Active'
        ];
        System.assertEquals(1, remaining.size(), 'Only one active schedule should remain');
        System.assertEquals('MONTHLY', remaining[0].Frequency__c, 'New schedule should be MONTHLY');
    }

    // ─────────────────────────────────────────────────
    //  Test: Orphaned schedule in scheduleArchive
    //  (existing schedule with stale Job_Id__c)
    //  Covers lines 167-183: job deleted from Setup
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_CleansOrphanedExistingSchedule() {
        // Insert a schedule with a fake Job_Id that doesn't exist in CronTrigger
        // Simulate a job that was deleted from Setup
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Account',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 15,
            Cron_Expression__c = '0 0 2 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '02:00',
            Day_Of_Week__c     = null,
            Job_Id__c          = null  // null Job_Id simulates orphaned job
        );

        Test.startTest();
        // The schedule method should detect the stale record, delete it, then create new
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'DAILY', 'CreatedDate', 15, null,
            '02:00', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('Successfully'), 'Should succeed after cleaning orphan');

        // Should only have one active schedule
        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Job_Id__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Date_Field__c = 'CreatedDate'
            AND Status__c = 'Active'
        ];
        System.assertEquals(1, schedules.size(), 'Should have exactly one active schedule');
        System.assertNotEquals(null, schedules[0].Job_Id__c, 'New schedule should have a valid Job_Id');
    }

    // ─────────────────────────────────────────────────
    //  Test: All frequency branches covered
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_AllFrequencies() {
        List<String> frequencies = new List<String>{
            'WEEKLY', 'MONTHLY', 'YEARLY', 'UNKNOWN'
        };

        Test.startTest();
        Integer idx = 0;
        for (String freq : frequencies) {
            // Use different dateField for each to avoid duplicate issues
            String result = DataArchiveScheduleController.scheduleArchive(
                'Account', freq, 'Name' + idx, 0, 'FreqTest',
                '08:00', 'FRI'
            );
            System.assertNotEquals(null, result);
            idx++;
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────
    //  Test: Custom preferred time in cron
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_CustomTime() {
        Test.startTest();
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'DAILY', 'Name', 10, 'TimeTest',
            '16:45', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);

        Data_Archive_Schedule__c saved = [
            SELECT Cron_Expression__c, Preferred_Time__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Days__c = 10
            LIMIT 1
        ];

        System.assertEquals('16:45', saved.Preferred_Time__c);
        System.assert(saved.Cron_Expression__c.contains('45'), 'Cron should contain minute 45');
        System.assert(saved.Cron_Expression__c.contains('16'), 'Cron should contain hour 16');
    }

    // ─────────────────────────────────────────────────
    //  Test: Null preferred time defaults to 02:00
    //  Covers buildCronExpression default time branch
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_NullPreferredTime() {
        Test.startTest();
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'DAILY', 'Name', 20, 'NullTimeTest',
            null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);

        Data_Archive_Schedule__c saved = [
            SELECT Cron_Expression__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Days__c = 20
            LIMIT 1
        ];

        // Default cron should be: 0 0 2 * * ?
        System.assertEquals('0 0 2 * * ?', saved.Cron_Expression__c,
            'Should default to 02:00 when preferredTime is null');
    }

    // ─────────────────────────────────────────────────
    //  Test: Weekly with custom day
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_WeeklyWithDay() {
        Test.startTest();
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'WEEKLY', 'Name', 5, 'DayTest',
            '10:00', 'WED'
        );
        Test.stopTest();

        System.assertNotEquals(null, result);

        Data_Archive_Schedule__c saved = [
            SELECT Cron_Expression__c, Day_Of_Week__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Days__c = 5
            LIMIT 1
        ];

        System.assertEquals('WED', saved.Day_Of_Week__c);
        System.assert(saved.Cron_Expression__c.contains('WED'), 'Cron should contain WED');
    }

    // ─────────────────────────────────────────────────
    //  Test: Weekly with null dayOfWeek defaults to MON
    //  Covers buildCronExpression WEEKLY default branch
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_WeeklyDefaultDay() {
        Test.startTest();
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'WEEKLY', 'Name', 7, 'DefaultDayTest',
            '09:00', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);

        Data_Archive_Schedule__c saved = [
            SELECT Cron_Expression__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Days__c = 7
            LIMIT 1
        ];

        System.assert(saved.Cron_Expression__c.contains('MON'),
            'WEEKLY with null dayOfWeek should default to MON');
    }

    // ─────────────────────────────────────────────────
    //  Test: Weekly with empty string dayOfWeek defaults to MON
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_WeeklyEmptyDay() {
        Test.startTest();
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'WEEKLY', 'Name', 8, 'EmptyDayTest',
            '09:00', ''
        );
        Test.stopTest();

        System.assertNotEquals(null, result);

        Data_Archive_Schedule__c saved = [
            SELECT Cron_Expression__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Days__c = 8
            LIMIT 1
        ];

        System.assert(saved.Cron_Expression__c.contains('MON'),
            'WEEKLY with empty dayOfWeek should default to MON');
    }

    // ─────────────────────────────────────────────────
    //  Test: deactivateSchedule with no Job_Id
    //  (schedule was created without scheduling a real job)
    // ─────────────────────────────────────────────────
    @IsTest
    static void testDeactivateSchedule_NoJobId() {
        Data_Archive_Schedule__c sched = new Data_Archive_Schedule__c(
            Object_Name__c     = 'Account',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 30,
            Cron_Expression__c = '0 0 2 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '02:00',
            Day_Of_Week__c     = 'MON',
            Job_Id__c          = null
        );
        insert sched;

        Test.startTest();
        String result = DataArchiveScheduleController.deactivateSchedule(sched.Id);
        Test.stopTest();

        System.assert(result.contains('deactivated'), 'Should confirm deactivation');

        Data_Archive_Schedule__c updated = [
            SELECT Status__c FROM Data_Archive_Schedule__c WHERE Id = :sched.Id
        ];
        System.assertEquals('Stopped', updated.Status__c, 'Status should be Stopped');
    }

    // ─────────────────────────────────────────────────
    //  Test: deactivateSchedule with a real Job_Id
    //  Covers System.abortJob path (lines 308-310)
    // ─────────────────────────────────────────────────
    @IsTest
    static void testDeactivateSchedule_WithRealJobId() {
        // Create a real scheduled job
        Id jobId = System.schedule(
            'TestDeactivateJob_' + Datetime.now().getTime(),
            '0 0 3 * * ?',
            new DataArchiveScheduler('Account', 'CreatedDate', 30, null)
        );

        Data_Archive_Schedule__c sched = new Data_Archive_Schedule__c(
            Object_Name__c     = 'Account',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 30,
            Cron_Expression__c = '0 0 3 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '03:00',
            Day_Of_Week__c     = null,
            Job_Id__c          = jobId
        );
        insert sched;

        Test.startTest();
        String result = DataArchiveScheduleController.deactivateSchedule(sched.Id);
        Test.stopTest();

        System.assert(result.contains('deactivated'), 'Should confirm deactivation');

        Data_Archive_Schedule__c updated = [
            SELECT Status__c FROM Data_Archive_Schedule__c WHERE Id = :sched.Id
        ];
        System.assertEquals('Stopped', updated.Status__c, 'Status should be Stopped after deactivation');

        // Verify the job was actually aborted
        List<CronTrigger> remaining = [
            SELECT Id, State FROM CronTrigger WHERE Id = :jobId
        ];
        if (!remaining.isEmpty()) {
            System.assertEquals('DELETED', remaining[0].State,
                'CronTrigger should be DELETED/aborted');
        }
    }

    // ─────────────────────────────────────────────────
    //  Test: deactivateSchedule with invalid Id throws
    // ─────────────────────────────────────────────────
    @IsTest
    static void testDeactivateSchedule_NotFound() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            DataArchiveScheduleController.deactivateSchedule('a0B000000000000AAA');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException for missing record');
    }

    // ─────────────────────────────────────────────────
    //  Test: Orphaned schedule (null Job_Id) is auto-deactivated
    //  via getActiveSchedules
    // ─────────────────────────────────────────────────
    @IsTest
    static void testGetActiveSchedules_CleansOrphans() {
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Lead',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 10,
            Cron_Expression__c = '0 0 2 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '02:00',
            Job_Id__c          = null
        );

        Test.startTest();
        List<DataArchiveScheduleController.ScheduleInfo> results =
            DataArchiveScheduleController.getActiveSchedules();
        Test.stopTest();

        Boolean foundLead = false;
        for (DataArchiveScheduleController.ScheduleInfo si : results) {
            if (si.objectName == 'Lead') {
                foundLead = true;
                break;
            }
        }
        System.assert(!foundLead, 'Orphaned Lead schedule should NOT be returned');

        Data_Archive_Schedule__c updated = [
            SELECT Status__c FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Lead' LIMIT 1
        ];
        System.assertEquals('Inactive', updated.Status__c,
            'Orphaned schedule should be auto-deactivated');
    }

    // ─────────────────────────────────────────────────
    //  Test: getSchedulesForObject also cleans orphans
    // ─────────────────────────────────────────────────
    @IsTest
    static void testGetSchedulesForObject_CleansOrphans() {
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Contact',
            Frequency__c       = 'WEEKLY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 20,
            Cron_Expression__c = '0 0 2 ? * MON',
            Status__c          = 'Active',
            Preferred_Time__c  = '09:00',
            Day_Of_Week__c     = 'MON',
            Job_Id__c          = null
        );

        Test.startTest();
        List<DataArchiveScheduleController.ScheduleInfo> results =
            DataArchiveScheduleController.getSchedulesForObject('Contact');
        Test.stopTest();

        System.assert(results.isEmpty(),
            'Orphaned Contact schedule should not be returned');

        Data_Archive_Schedule__c updated = [
            SELECT Status__c FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Contact' LIMIT 1
        ];
        System.assertEquals('Inactive', updated.Status__c,
            'Orphaned schedule should be auto-deactivated');
    }

    // ─────────────────────────────────────────────────
    //  Test: ScheduleInfo wrapper field coverage
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleInfoWrapper() {
        DataArchiveScheduleController.ScheduleInfo info =
            new DataArchiveScheduleController.ScheduleInfo();

        info.id             = 'testId';
        info.objectName     = 'Account';
        info.frequency      = 'DAILY';
        info.dateField      = 'CreatedDate';
        info.days           = 30;
        info.status         = 'Active';
        info.cronExpression = '0 0 2 * * ?';
        info.createdDate    = Datetime.now();
        info.preferredTime  = '02:00';
        info.dayOfWeek      = 'MON';

        System.assertEquals('testId', info.id);
        System.assertEquals('Account', info.objectName);
        System.assertEquals('DAILY', info.frequency);
        System.assertEquals('CreatedDate', info.dateField);
        System.assertEquals(30, info.days);
        System.assertEquals('Active', info.status);
        System.assertEquals('0 0 2 * * ?', info.cronExpression);
        System.assertNotEquals(null, info.createdDate);
        System.assertEquals('02:00', info.preferredTime);
        System.assertEquals('MON', info.dayOfWeek);
    }

    // ─────────────────────────────────────────────────
    //  Test: scheduleArchive with existing schedule
    //  that has a Job_Id but no matching CronTrigger
    //  (Job_Id__c is non-null but orphaned)
    //  Covers the jobStillExists = false branch in
    //  scheduleArchive (lines 169-182)
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_ExistingWithStaleJobId() {
        // Create a real job, then abort it to simulate a deleted job
        Id jobId = System.schedule(
            'TestStaleJob_' + Datetime.now().getTime(),
            '0 0 4 * * ?',
            new DataArchiveScheduler('Account', 'CreatedDate', 25, null)
        );
        // Abort the job so the CronTrigger is deleted
        System.abortJob(jobId);

        // Insert schedule record that references the now-deleted job
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Account',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 25,
            Cron_Expression__c = '0 0 4 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '04:00',
            Day_Of_Week__c     = null,
            Job_Id__c          = jobId
        );

        Test.startTest();
        // scheduleArchive should detect the stale Job_Id, delete the record,
        // then create a new schedule
        String result = DataArchiveScheduleController.scheduleArchive(
            'Account', 'DAILY', 'CreatedDate', 25, null,
            '04:00', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('Successfully'), 'Should create new schedule after cleaning stale');

        // Verify only one active schedule exists
        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Job_Id__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Account'
            AND Date_Field__c = 'CreatedDate'
            AND Status__c = 'Active'
        ];
        System.assertEquals(1, schedules.size(), 'Should have exactly one active schedule');
    }

    // ─────────────────────────────────────────────────
    //  Test: Existing schedule with valid job 
    //  but different frequency → abort + delete + recreate
    //  Covers lines 205-210 with non-null Job_Id
    // ─────────────────────────────────────────────────
    @IsTest
    static void testScheduleArchive_AbortsExistingValidJob() {
        // Create a real scheduled job
        Id jobId = System.schedule(
            'TestAbortJob_' + Datetime.now().getTime(),
            '0 0 5 * * ?',
            new DataArchiveScheduler('Case', 'CreatedDate', 30, null)
        );

        // Insert a schedule record with the real Job_Id
        // Use different Days__c so it won't be caught as a duplicate
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = 'Case',
            Frequency__c       = 'DAILY',
            Date_Field__c      = 'CreatedDate',
            Days__c            = 30,
            Cron_Expression__c = '0 0 5 * * ?',
            Status__c          = 'Active',
            Preferred_Time__c  = '05:00',
            Day_Of_Week__c     = null,
            Job_Id__c          = jobId
        );

        Test.startTest();
        // Schedule with same object+field but different frequency
        // This hits the existing[0].Job_Id__c != null → System.abortJob path
        String result = DataArchiveScheduleController.scheduleArchive(
            'Case', 'WEEKLY', 'CreatedDate', 30, null,
            '06:00', 'TUE'
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('Successfully'), 'Should succeed');

        // Old schedule should be replaced
        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Frequency__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = 'Case'
            AND Status__c = 'Active'
        ];
        System.assertEquals(1, schedules.size(), 'Only one active schedule');
        System.assertEquals('WEEKLY', schedules[0].Frequency__c, 'Should be the new WEEKLY schedule');
    }
}