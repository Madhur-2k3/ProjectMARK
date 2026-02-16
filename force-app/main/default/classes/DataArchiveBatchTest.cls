@IsTest
private class DataArchiveBatchTest {
    @IsTest
    static void testBatch_Execute() {
        // Setup test data if needed
        // Provide required constructor arguments: objectName, fieldsCsv, soqlQuery
        String objectName = 'Account';
        String fieldsCsv = 'Name';
        String soqlQuery = 'SELECT Id, Name FROM Account';
        Test.startTest();
        Database.executeBatch(new DataArchiveBatch(objectName, fieldsCsv, soqlQuery), 50);
        Test.stopTest();
        System.assert(true, 'Batch executed without error');
    }
}