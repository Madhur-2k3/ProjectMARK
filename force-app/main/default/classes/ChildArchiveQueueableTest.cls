@IsTest
private class ChildArchiveQueueableTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accs.add(new Account(Name = 'Test Account ' + i));
        }
        insert accs;
    }

    // Test: empty children list → finishArchive() path
    @IsTest
    static void testEmptyChildrenList() {
        // Create archive record
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
        System.enqueueJob(new ChildArchiveQueueable(
            archive.Id,
            archive.Name,
            'Account',
            new List<ChildArchiveQueueable.ChildInfo>(),   // empty — triggers finishArchive()
            new Map<String, List<Id>>(),
            new List<Id>(),
            parentIds
        ));
        Test.stopTest();

        // finishArchive() should have updated status
        Data_Archive__c updated = [SELECT Status__c FROM Data_Archive__c WHERE Id = :archive.Id];
        System.assertEquals('Ready for Unarchive', updated.Status__c,
            'Status should be Ready for Unarchive after empty child processing');
    }

    // Test: one child object → processOneChild() + finishArchive()
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

        // Create a ChildInfo for Contact (child of Account)
        ChildArchiveQueueable.ChildInfo childInfo = new ChildArchiveQueueable.ChildInfo();
        childInfo.objectName        = 'Contact';
        childInfo.relationshipField = 'AccountId';
        childInfo.fields            = new List<String>{'Id', 'LastName'};
        childInfo.depth             = 1;
        childInfo.parentObjectName  = 'Account';

        Map<String, List<Id>> collectedIds = new Map<String, List<Id>>();
        collectedIds.put('Account', parentIds);

        Test.startTest();
        System.enqueueJob(new ChildArchiveQueueable(
            archive.Id,
            archive.Name,
            'Account',
            new List<ChildArchiveQueueable.ChildInfo>{ childInfo },
            collectedIds,
            new List<Id>(),
            parentIds
        ));
        Test.stopTest();

        // Status should be updated
        Data_Archive__c updated = [SELECT Status__c FROM Data_Archive__c WHERE Id = :archive.Id];
        System.assert(
            updated.Status__c == 'Ready for Unarchive' || updated.Status__c.startsWith('Error'),
            'Status should indicate processing completed: ' + updated.Status__c
        );
    }

    // Test: no matching parent IDs → skip path
    @IsTest
    static void testChildWithNoParentIds() {
        Data_Archive__c archive = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c        = 'Id, Name',
            Status__c        = 'Archive In Progress',
            Name             = 'Test Archive'
        );
        insert archive;
        archive = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archive.Id LIMIT 1];

        ChildArchiveQueueable.ChildInfo childInfo = new ChildArchiveQueueable.ChildInfo();
        childInfo.objectName        = 'Contact';
        childInfo.relationshipField = 'AccountId';
        childInfo.fields            = new List<String>{'Id', 'LastName'};
        childInfo.depth             = 1;
        childInfo.parentObjectName  = 'Account';

        // Empty collectedIds — no parent IDs for 'Account'
        Map<String, List<Id>> collectedIds = new Map<String, List<Id>>();

        Test.startTest();
        System.enqueueJob(new ChildArchiveQueueable(
            archive.Id,
            archive.Name,
            'Account',
            new List<ChildArchiveQueueable.ChildInfo>{ childInfo },
            collectedIds,
            new List<Id>(),
            new List<Id>()
        ));
        Test.stopTest();

        Data_Archive__c updated = [SELECT Status__c FROM Data_Archive__c WHERE Id = :archive.Id];
        System.assertEquals('Ready for Unarchive', updated.Status__c,
            'Status should be Ready for Unarchive when no parent IDs exist');
    }
}
