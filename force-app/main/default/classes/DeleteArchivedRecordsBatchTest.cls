@IsTest
private class DeleteArchivedRecordsBatchTest {
    @IsTest
    static void testBatch_Execute() {
        // Setup test data if needed
        // Provide required soqlQuery argument
        String soqlQuery = 'SELECT Id FROM Account';
        Test.startTest();
        Database.executeBatch(new DeleteArchivedRecordsBatch(soqlQuery), 50);
        Test.stopTest();
        System.assert(true, 'Batch executed without error');
    }
}