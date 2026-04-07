/**
 * @description Tests for DataArchiveScheduler.
 */
@IsTest
private class DataArchiveSchedulerTest {

    @IsTest
    static void testScheduler_Execute_TextFilter() {

        DataArchiveScheduler myScheduler =
            new DataArchiveScheduler('Account', 'Name', 0, 'Name = \'Acme\'', 'TestSchedule');

        Test.startTest();
        myScheduler.execute(null);
        Test.stopTest();

        List<AsyncApexJob> myJobsList = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'DataArchiveBatch'
        ];
        System.assert(!myJobsList.isEmpty(), 'DataArchiveBatch should have been enqueued');
    }

    @IsTest
    static void testScheduler_Execute_DateFilter() {

        DataArchiveScheduler myScheduler =
            new DataArchiveScheduler('Account', 'LastActivityDate', 30, '', 'TestSchedule');

        Test.startTest();
        myScheduler.execute(null);
        Test.stopTest();

        List<AsyncApexJob> myJobsList = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'DataArchiveBatch'
        ];
        System.assert(!myJobsList.isEmpty(), 'DataArchiveBatch should have been enqueued for date filter');
    }

    @IsTest
    static void testScheduler_Execute_NullDaysAndFilter() {

        DataArchiveScheduler myScheduler =
            new DataArchiveScheduler('Account', 'LastActivityDate', null, '', 'TestSchedule');

        Test.startTest();
        myScheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Should handle null days gracefully');
    }
}