/**
 * @description Tests for CascadeDeleteHelper methods.
 */
@IsTest
private class CascadeDeleteHelperTest {

    @TestSetup
    static void setupData() {

        List<Account> myAccountsList = new List<Account>();

        for (Integer myIndex = 0; myIndex < 2; myIndex++) {
            myAccountsList.add(new Account(Name = 'Cascade Test ' + myIndex));
        }

        insert myAccountsList;
    }

    @IsTest
    static void testDeleteParentWithRelations_Valid() {

        List<Account> myAccountsList = [SELECT Id FROM Account];
        List<Id> myIdsList = new List<Id>();

        for (Account myCurrentAccount : myAccountsList) {
            myIdsList.add(myCurrentAccount.Id);
        }

        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('Account', myIdsList);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id IN :myIdsList], 'Accounts should be deleted');
    }

    @IsTest
    static void testDeleteParentWithRelations_NullOrEmpty() {

        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('Account', null);
        CascadeDeleteHelper.deleteParentWithRelations('Account', new List<Id>());
        Test.stopTest();
    }

    @IsTest
    static void testDeleteParentWithRelations_InvalidObject() {

        List<Account> myAccountsList = [SELECT Id FROM Account LIMIT 1];
        List<Id> myIdsList = new List<Id>{myAccountsList.isEmpty() ? null : myAccountsList[0].Id};

        Test.startTest();
        CascadeDeleteHelper.deleteParentWithRelations('InvalidObject__c', myIdsList);
        Test.stopTest();
    }
}