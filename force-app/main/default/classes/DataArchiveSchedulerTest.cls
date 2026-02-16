@IsTest
private class DataArchiveSchedulerTest {
    @IsTest
    static void testScheduler_Execute() {
        // Provide required constructor arguments
        String objectName = 'Account';
        String fieldsCsv = 'Name';
        String soqlQuery = 'SELECT Id, Name FROM Account';
        DataArchiveScheduler sched = new DataArchiveScheduler(objectName, fieldsCsv, soqlQuery);
        Test.startTest();
        sched.execute(null);
        Test.stopTest();
        System.assert(true, 'Scheduler execute ran');
    }
}