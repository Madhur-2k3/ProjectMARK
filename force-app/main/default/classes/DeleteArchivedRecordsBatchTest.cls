/**
 * @description Tests for DeleteArchivedRecordsBatch.
 */
@IsTest
private class DeleteArchivedRecordsBatchTest {

    @IsTest
    static void testBatch_DeletesRecords() {

        List<Account> myAccountsList = new List<Account>();

        for (Integer myIndex = 0; myIndex < 5; myIndex++) {
            myAccountsList.add(new Account(Name = 'DelBatch Test ' + myIndex));
        }

        insert myAccountsList;

        System.assertEquals(5, [SELECT COUNT() FROM Account WHERE Name LIKE 'DelBatch Test%']);

        String mySoqlQueryStr = 'SELECT Id FROM Account WHERE Name LIKE \'DelBatch Test%\'';

        Test.startTest();
        Database.executeBatch(new DeleteArchivedRecordsBatch(mySoqlQueryStr), 50);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name LIKE 'DelBatch Test%'],
            'All matching Accounts should be deleted by the batch');
    }

    @IsTest
    static void testBatch_EmptyScope() {

        String mySoqlQueryStr = 'SELECT Id FROM Account WHERE Name = \'DOES_NOT_EXIST_999\'';

        Test.startTest();
        Database.executeBatch(new DeleteArchivedRecordsBatch(mySoqlQueryStr), 50);
        Test.stopTest();

        System.assert(true, 'Batch completed without error on empty scope');
    }
}