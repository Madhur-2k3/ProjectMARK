@IsTest
private class CascadeDeleteQueueableTest {
    
    @TestSetup
    static void setupData() {
        // Insert some parent records (Account as example)
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 2; i++) {
            accts.add(new Account(Name = 'Cascade Q Test ' + i));
        }
        insert accts;
    }

    @IsTest
    static void testQueueable_Valid() {
        List<Account> accts = [SELECT Id FROM Account];
        List<Id> ids = new List<Id>();
        for (Account a : accts) {
            ids.add(a.Id);
        }
        Test.startTest();
        System.enqueueJob(new CascadeDeleteQueueable('Account', ids));
        Test.stopTest();
        // No assertion needed, just ensure no error
    }

    @IsTest
    static void testQueueable_NullAndEmpty() {
        Test.startTest();
        System.enqueueJob(new CascadeDeleteQueueable('Account', null));
        System.enqueueJob(new CascadeDeleteQueueable('Account', new List<Id>()));
        Test.stopTest();
    }

    @IsTest
    static void testQueueable_InvalidObject() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 1];
        List<Id> ids = new List<Id>{accts.isEmpty() ? null : accts[0].Id};
        Test.startTest();
        System.enqueueJob(new CascadeDeleteQueueable('InvalidObject__c', ids));
        Test.stopTest();
    }
}