@IsTest
private class DataArchiveSchedulerTest {

    @IsTest
    static void testScheduler_DateCriteria() {
        DataArchiveScheduler sched =
            new DataArchiveScheduler('Account', 'CreatedDate', 30, null);

        Test.startTest();
        sched.execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'DataArchiveBatch'
        ];
        System.assert(!jobs.isEmpty(), 'Batch should be enqueued for date criteria');
    }

    @IsTest
    static void testScheduler_TextCriteria() {
        DataArchiveScheduler sched =
            new DataArchiveScheduler('Account', 'Name', null, 'Acme Corp');

        Test.startTest();
        sched.execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'DataArchiveBatch'
        ];
        System.assert(!jobs.isEmpty(), 'Batch should be enqueued for text criteria');
    }
}