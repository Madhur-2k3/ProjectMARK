@IsTest
private class CascadeDeleteHelperTest {
    @TestSetup
    static void setupData() {
        // Insert some parent records (Account as example)
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 2; i++) {
            accts.add(new Account(Name = 'Cascade Test ' + i));
        }
        insert accts;
    }

    @IsTest
    static void testDeleteParentWithRelations_Valid() {
        List<Account> accts = [SELECT Id FROM Account];
        List<Id> ids = new List<Id>();
        for (Account a : accts) {
            ids.add(a.Id);
        }
        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('Account', ids);
        Test.stopTest();
        // Assert that records are deleted
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id IN :ids], 'Accounts should be deleted');
    }

    @IsTest
    static void testDeleteParentWithRelations_NullOrEmpty() {
        // Should not throw error
        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('Account', null);
        CascadeDeleteHelper.deleteParentWithRelations('Account', new List<Id>());
        Test.stopTest();
    }

    @IsTest
    static void testDeleteParentWithRelations_InvalidObject() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 1];
        List<Id> ids = new List<Id>{accts.isEmpty() ? null : accts[0].Id};
        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('InvalidObject__c', ids);
        Test.stopTest();
        // No error expected, nothing deleted
    }
}