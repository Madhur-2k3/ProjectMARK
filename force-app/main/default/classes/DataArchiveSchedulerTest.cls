@IsTest
private class DataArchiveSchedulerTest {
    @IsTest
    static void testScheduler_Execute() {
        // Provide the new constructor arguments
        String objectName = 'Account';
        String dateField  = 'CreatedDate';
        Integer days      = 30;

        DataArchiveScheduler sched =
            new DataArchiveScheduler(objectName, dateField, days);

        Test.startTest();
        sched.execute(null);
        Test.stopTest();

        // Verify a batch job was enqueued
        List<AsyncApexJob> jobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'DataArchiveBatch'
        ];
        System.assert(!jobs.isEmpty(), 'DataArchiveBatch should have been enqueued');
    }
}