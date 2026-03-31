/**
 * @description Tests for CascadeDeleteQueueable.
 */
@IsTest
private class CascadeDeleteQueueableTest {

    @TestSetup
    static void setupData() {

        List<Account> myAccountsList = new List<Account>();

        for (Integer myIndex = 0; myIndex < 2; myIndex++) {
            myAccountsList.add(new Account(Name = 'Cascade Q Test ' + myIndex));
        }

        insert myAccountsList;
    }

    @IsTest
    static void testQueueable_Valid() {

        List<Account> myAccountsList = [SELECT Id FROM Account];
        List<Id> myIdsList = new List<Id>();

        for (Account myCurrentAccount : myAccountsList) {
            myIdsList.add(myCurrentAccount.Id);
        }

        Test.startTest();
        Database.executeBatch(new CascadeDeleteQueueable('Account', myIdsList), 200);
        Test.stopTest();
    }

    @IsTest
    static void testQueueable_NullAndEmpty() {

        Test.startTest();
        Database.executeBatch(new CascadeDeleteQueueable('Account', null), 200);
        Database.executeBatch(new CascadeDeleteQueueable('Account', new List<Id>()), 200);
        Test.stopTest();
    }

    @IsTest
    static void testQueueable_InvalidObject() {

        List<Account> myAccountsList = [SELECT Id FROM Account LIMIT 1];
        List<Id> myIdsList = new List<Id>{myAccountsList.isEmpty() ? null : myAccountsList[0].Id};

        Test.startTest();
        Database.executeBatch(new CascadeDeleteQueueable('InvalidObject__c', myIdsList), 200);
        Test.stopTest();
    }
}