@IsTest
private class DataArchiveChildBatchTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accs.add(new Account(Name = 'Test Account ' + i));
        }
        insert accs;
    }

    @IsTest
    static void testEmptyChildList() {
        Data_Archive__c archive = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c        = 'Id, Name',
            Status__c        = 'Archive In Progress',
            Name             = 'Test Archive'
        );
        insert archive;
        archive = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archive.Id LIMIT 1];

        List<Account> accs = [SELECT Id FROM Account];
        List<Id> parentIds = new List<Id>();
        for (Account a : accs) parentIds.add(a.Id);

        Test.startTest();
        Database.executeBatch(new DataArchiveChildBatch(
            archive.Id,
            archive.Name,
            'Account',
            new List<DataArchiveChildBatch.ChildInfo>(),
            new Map<String, List<Id>>(),
            new List<Id>(),
            parentIds
        ), 1);
        Test.stopTest();

        Data_Archive__c updated = [SELECT Status__c FROM Data_Archive__c WHERE Id = :archive.Id];
        System.assertEquals('Ready for Unarchive', updated.Status__c);
    }

    @IsTest
    static void testWithOneChildObject() {
        Data_Archive__c archive = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c        = 'Id, Name',
            Status__c        = 'Archive In Progress',
            Name             = 'Test Archive'
        );
        insert archive;
        archive = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archive.Id LIMIT 1];

        List<Account> accs = [SELECT Id FROM Account];
        List<Id> parentIds = new List<Id>();
        for (Account a : accs) parentIds.add(a.Id);

        DataArchiveChildBatch.ChildInfo info = new DataArchiveChildBatch.ChildInfo();
        info.objectName        = 'Contact';
        info.relationshipField = 'AccountId';
        info.fields            = new List<String>{'Id', 'LastName'};
        info.depth             = 1;
        info.parentObjectName  = 'Account';

        Map<String, List<Id>> collectedIds = new Map<String, List<Id>>();
        collectedIds.put('Account', parentIds);

        Test.startTest();
        Database.executeBatch(new DataArchiveChildBatch(
            archive.Id,
            archive.Name,
            'Account',
            new List<DataArchiveChildBatch.ChildInfo>{ info },
            collectedIds,
            new List<Id>(),
            parentIds
        ), 1);
        Test.stopTest();

        Data_Archive__c updated = [SELECT Status__c FROM Data_Archive__c WHERE Id = :archive.Id];
        System.assert(
            updated.Status__c == 'Ready for Unarchive' || updated.Status__c == 'Completed',
            'Expected Ready for Unarchive or Completed, got: ' + updated.Status__c
        );
    }
}
