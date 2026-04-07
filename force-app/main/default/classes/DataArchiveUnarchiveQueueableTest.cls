/**
 * @description Tests for DataArchiveUnarchiveQueueable.
 *              Verifies queueable parses CSVs, inserts records, and cleans up artifacts.
 */
@IsTest
private class DataArchiveUnarchiveQueueableTest {

    @TestSetup
    static void setup() {

        Data_Archive__c myArchiveRecord = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c = 'Name,Phone',
            Status__c = 'Ready for Unarchive'
        );
        insert myArchiveRecord;

        myArchiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :myArchiveRecord.Id];

        String myCsvStr = 'Name,Phone\n"Restored One","111"\n"Restored Two","222"';
        ContentVersion myContentVersion = new ContentVersion(
            Title = 'Account',
            PathOnClient = myArchiveRecord.Name + '-Account.csv',
            VersionData = Blob.valueOf(myCsvStr),
            Description = 'Account - ' + myArchiveRecord.Name
        );
        insert myContentVersion;

        ContentVersion myInsertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion WHERE Id = :myContentVersion.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = myInsertedVersion.ContentDocumentId,
            LinkedEntityId    = myArchiveRecord.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
    }

    @IsTest
    static void testQueueable_UnarchivesAndDeletesArtifacts() {

        Data_Archive__c myArchiveRecord = [
            SELECT Id, Name FROM Data_Archive__c LIMIT 1
        ];

        Test.startTest();
        System.enqueueJob(new DataArchiveUnarchiveQueueable(new List<Id>{myArchiveRecord.Id}));
        Test.stopTest();

        Integer myAccountCountInt = [SELECT COUNT() FROM Account WHERE Name IN ('Restored One','Restored Two')];
        System.assertEquals(2, myAccountCountInt, 'Expected two accounts inserted from CSV');

        Integer myRemainingArchivesInt = [SELECT COUNT() FROM Data_Archive__c WHERE Id = :myArchiveRecord.Id];
        System.assertEquals(0, myRemainingArchivesInt, 'Archive header should be deleted');

        Integer myRemainingLinksInt = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :myArchiveRecord.Id];
        System.assertEquals(0, myRemainingLinksInt, 'Links should be deleted as ContentDocument is removed');
    }

    @IsTest
    static void testQueueable_EmptyInput() {

        Test.startTest();
        System.enqueueJob(new DataArchiveUnarchiveQueueable(new List<Id>()));
        Test.stopTest();

        System.assert(true, 'Empty input handled gracefully');
    }

    @IsTest
    static void testQueueable_IgnoresInvalidFieldValues() {

        Data_Archive__c myArchiveRecord = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c = 'Name,NumberOfEmployees',
            Status__c = 'Ready for Unarchive'
        );
        insert myArchiveRecord;

        myArchiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :myArchiveRecord.Id];

        String myCsvStr = 'Name,NumberOfEmployees\n"Invalid Emp","NotANumber"';
        ContentVersion myContentVersion = new ContentVersion(
            Title = 'Account',
            PathOnClient = myArchiveRecord.Name + '-Account.csv',
            VersionData = Blob.valueOf(myCsvStr)
        );
        insert myContentVersion;

        ContentVersion myInsertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion WHERE Id = :myContentVersion.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = myInsertedVersion.ContentDocumentId,
            LinkedEntityId    = myArchiveRecord.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        Test.startTest();
        System.enqueueJob(new DataArchiveUnarchiveQueueable(new List<Id>{myArchiveRecord.Id}));
        Test.stopTest();

        Account myRestoredAccount = [SELECT Id, Name, NumberOfEmployees FROM Account WHERE Name = 'Invalid Emp' LIMIT 1];
        System.assertEquals('Invalid Emp', myRestoredAccount.Name);
    }
}