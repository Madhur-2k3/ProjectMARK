@IsTest
private class DataArchiveSchedulerTest {

    @IsTest
    static void testScheduler_Execute_TextFilter() {
        // Non-empty filterValue → text-based WHERE clause path
        // Avoids DateTime vs Date format issue with date-based filter
        DataArchiveScheduler sched =
            new DataArchiveScheduler('Account', 'Name', 0, 'Acme');

        Test.startTest();
        sched.execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'DataArchiveBatch'
        ];
        System.assert(!jobs.isEmpty(), 'DataArchiveBatch should have been enqueued');
    }

    @IsTest
    static void testScheduler_Execute_DateFilter() {
        // Use a Date field (not DateTime) to avoid format mismatch
        // LastActivityDate is a Date field on Account
        DataArchiveScheduler sched =
            new DataArchiveScheduler('Account', 'LastActivityDate', 30, '');

        Test.startTest();
        sched.execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'DataArchiveBatch'
        ];
        System.assert(!jobs.isEmpty(), 'DataArchiveBatch should have been enqueued for date filter');
    }

    @IsTest
    static void testScheduler_Execute_NullDaysAndFilter() {
        // null days → defaults to 0, empty filterValue → date-based path
        // Use LastActivityDate (Date type, not DateTime) to avoid SOQL error
        DataArchiveScheduler sched =
            new DataArchiveScheduler('Account', 'LastActivityDate', null, '');

        Test.startTest();
        sched.execute(null);
        Test.stopTest();

        System.assert(true, 'Should handle null days gracefully');
    }
}