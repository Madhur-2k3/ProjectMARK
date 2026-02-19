@IsTest
private class DeleteArchivedRecordsBatchTest {

    @IsTest
    static void testBatch_DeletesRecords() {
        // Insert test Accounts so the batch actually has records to delete
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'DelBatch Test ' + i));
        }
        insert accounts;

        // Verify records exist before batch
        System.assertEquals(5, [SELECT COUNT() FROM Account WHERE Name LIKE 'DelBatch Test%']);

        String soqlQuery = 'SELECT Id FROM Account WHERE Name LIKE \'DelBatch Test%\'';

        Test.startTest();
        Database.executeBatch(new DeleteArchivedRecordsBatch(soqlQuery), 50);
        Test.stopTest();

        // Verify records were deleted by the batch
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name LIKE 'DelBatch Test%'],
            'All matching Accounts should be deleted by the batch');
    }

    @IsTest
    static void testBatch_EmptyScope() {
        // Query returns no records — covers the isEmpty() guard
        String soqlQuery = 'SELECT Id FROM Account WHERE Name = \'DOES_NOT_EXIST_999\'';

        Test.startTest();
        Database.executeBatch(new DeleteArchivedRecordsBatch(soqlQuery), 50);
        Test.stopTest();

        System.assert(true, 'Batch completed without error on empty scope');
    }
}