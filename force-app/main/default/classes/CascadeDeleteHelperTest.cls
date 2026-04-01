@IsTest
private class CascadeDeleteHelperTest {

    @TestSetup
    static void setupData() {
        // Create parent Accounts
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accts.add(new Account(Name = 'Cascade Test ' + i));
        }
        insert accts;

        // Create child Contacts (lookup to Account)
        List<Contact> contacts = new List<Contact>();
        for (Account a : accts) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName  = a.Name + ' Contact',
                AccountId = a.Id
            ));
        }
        insert contacts;
    }

    @IsTest
    static void testDeleteParentWithRelations_DeletesLookupChildren() {
        List<Account> accts = [SELECT Id FROM Account];
        List<Id> ids = new List<Id>();
        for (Account a : accts) {
            ids.add(a.Id);
        }

        // Verify contacts exist before deletion
        Integer contactsBefore = [SELECT COUNT() FROM Contact WHERE AccountId IN :ids];
        System.assert(contactsBefore > 0, 'Contacts should exist before deletion');

        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('Account', ids);
        Test.stopTest();

        // Both parents and lookup children should be deleted
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id IN :ids],
            'Accounts should be deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE AccountId IN :ids],
            'Lookup child Contacts should also be deleted');
    }

    @IsTest
    static void testDeleteParentWithRelations_NullOrEmpty() {
        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('Account', null);
        CascadeDeleteHelper.deleteParentWithRelations('Account', new List<Id>());
        Test.stopTest();
        // No error expected
    }

    @IsTest
    static void testDeleteParentWithRelations_InvalidObject() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 1];
        List<Id> ids = new List<Id>();
        if (!accts.isEmpty()) ids.add(accts[0].Id);

        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('InvalidObject__c', ids);
        Test.stopTest();
        // No error expected, nothing deleted
    }

    @IsTest
    static void testDeleteParentWithRelations_NoChildren() {
        // Create an account with no children
        Account solo = new Account(Name = 'Solo Account');
        insert solo;

        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('Account', new List<Id>{ solo.Id });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :solo.Id],
            'Solo account should be deleted even with no children');
    }
}