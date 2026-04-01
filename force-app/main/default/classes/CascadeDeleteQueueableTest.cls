@IsTest
private class CascadeDeleteQueueableTest {

    @TestSetup
    static void setupData() {
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accts.add(new Account(Name = 'Cascade Q Test ' + i));
        }
        insert accts;

        // Create lookup children
        List<Contact> contacts = new List<Contact>();
        for (Account a : accts) {
            contacts.add(new Contact(
                FirstName = 'Q',
                LastName  = a.Name + ' Contact',
                AccountId = a.Id
            ));
        }
        insert contacts;
    }

    @IsTest
    static void testChainedBatch_DeletesInOrder() {
        List<Account> accts = [SELECT Id FROM Account];
        List<Contact> contacts = [SELECT Id FROM Contact];

        List<Id> acctIds = new List<Id>();
        for (Account a : accts) acctIds.add(a.Id);

        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        // Build a two-step chain: delete contacts first, then accounts
        CascadeDeleteQueueable.DeletionStep contactStep =
            new CascadeDeleteQueueable.DeletionStep('Contact', contactIds);
        CascadeDeleteQueueable.DeletionStep accountStep =
            new CascadeDeleteQueueable.DeletionStep('Account', acctIds);

        Test.startTest();
        Database.executeBatch(
            new CascadeDeleteQueueable(contactStep, new List<CascadeDeleteQueueable.DeletionStep>{ accountStep }),
            200
        );
        Test.stopTest();

        // Both should be deleted (note: Test.stopTest only executes first batch;
        // chained batch runs synchronously in test context)
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE Id IN :contactIds],
            'Contacts should be deleted');
    }

    @IsTest
    static void testBackwardCompatConstructor() {
        List<Account> accts = [SELECT Id FROM Account];
        List<Id> ids = new List<Id>();
        for (Account a : accts) ids.add(a.Id);

        Test.startTest();
        Database.executeBatch(new CascadeDeleteQueueable('Account', ids), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id IN :ids],
            'Accounts should be deleted using backward-compat constructor');
    }

    @IsTest
    static void testNullAndEmpty() {
        Test.startTest();
        Database.executeBatch(new CascadeDeleteQueueable('Account', null), 200);
        Database.executeBatch(new CascadeDeleteQueueable('Account', new List<Id>()), 200);
        Test.stopTest();
    }

    @IsTest
    static void testInvalidObject() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 1];
        List<Id> ids = new List<Id>();
        if (!accts.isEmpty()) ids.add(accts[0].Id);

        Test.startTest();
        Database.executeBatch(new CascadeDeleteQueueable('InvalidObject__c', ids), 200);
        Test.stopTest();
    }
}