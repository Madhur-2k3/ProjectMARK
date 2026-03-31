/**
 * @description Tests for DataArchiveChildBatch.
 */
@IsTest
private class DataArchiveChildBatchTest {

    @TestSetup
    static void setupData() {

        List<Account> myAccountsList = new List<Account>();

        for (Integer myIndex = 0; myIndex < 3; myIndex++) {
            myAccountsList.add(new Account(Name = 'Test Account ' + myIndex));
        }

        insert myAccountsList;
    }

    @IsTest
    static void testEmptyChildList() {

        Data_Archive__c myArchiveRecord = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c        = 'Id, Name',
            Status__c        = 'Archive In Progress',
            Name             = 'Test Archive'
        );
        insert myArchiveRecord;

        myArchiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :myArchiveRecord.Id LIMIT 1];

        List<Account> myAccountsList = [SELECT Id FROM Account];
        List<Id> myParentIdsList = new List<Id>();

        for (Account myCurrentAccount : myAccountsList) myParentIdsList.add(myCurrentAccount.Id);

        Test.startTest();
        Database.executeBatch(new DataArchiveChildBatch(
            myArchiveRecord.Id,
            myArchiveRecord.Name,
            'Account',
            new List<DataArchiveChildBatch.ChildInfo>(),
            new Map<String, List<Id>>(),
            new List<Id>(),
            myParentIdsList
        ), 1);
        Test.stopTest();

        Data_Archive__c myUpdatedRecord = [SELECT Status__c FROM Data_Archive__c WHERE Id = :myArchiveRecord.Id];
        System.assertEquals('Ready for Unarchive', myUpdatedRecord.Status__c);
    }

    @IsTest
    static void testWithOneChildObject() {

        Data_Archive__c myArchiveRecord = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c        = 'Id, Name',
            Status__c        = 'Archive In Progress',
            Name             = 'Test Archive'
        );
        insert myArchiveRecord;

        myArchiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :myArchiveRecord.Id LIMIT 1];

        List<Account> myAccountsList = [SELECT Id FROM Account];
        List<Id> myParentIdsList = new List<Id>();

        for (Account myCurrentAccount : myAccountsList) myParentIdsList.add(myCurrentAccount.Id);

        DataArchiveChildBatch.ChildInfo myChildInfo = new DataArchiveChildBatch.ChildInfo();
        myChildInfo.objectName        = 'Contact';
        myChildInfo.relationshipField = 'AccountId';
        myChildInfo.fields            = new List<String>{'Id', 'LastName'};
        myChildInfo.depth             = 1;
        myChildInfo.parentObjectName  = 'Account';

        Map<String, List<Id>> myCollectedIdsMap = new Map<String, List<Id>>();
        myCollectedIdsMap.put('Account', myParentIdsList);

        Test.startTest();
        Database.executeBatch(new DataArchiveChildBatch(
            myArchiveRecord.Id,
            myArchiveRecord.Name,
            'Account',
            new List<DataArchiveChildBatch.ChildInfo>{ myChildInfo },
            myCollectedIdsMap,
            new List<Id>(),
            myParentIdsList
        ), 1);
        Test.stopTest();

        Data_Archive__c myUpdatedRecord = [SELECT Status__c FROM Data_Archive__c WHERE Id = :myArchiveRecord.Id];
        System.assert(
            myUpdatedRecord.Status__c == 'Ready for Unarchive' || myUpdatedRecord.Status__c == 'Completed',
            'Expected Ready for Unarchive or Completed, got: ' + myUpdatedRecord.Status__c
        );
    }
}