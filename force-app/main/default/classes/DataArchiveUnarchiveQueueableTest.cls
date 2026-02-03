/**
 * @description Tests for DataArchiveUnarchiveQueueable
 * Ensures queueable parses CSVs, inserts records, and cleans up archive + documents
 */
@IsTest
private class DataArchiveUnarchiveQueueableTest {

    @TestSetup
    static void setup() {
        // Create an archive header for Account
        Data_Archive__c da = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c = 'Name,Phone',
            Status__c = 'Ready for Unarchive'
        );
        insert da;

        da = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :da.Id];

        // Create a CSV content for two accounts
        String csv = 'Name,Phone\n"Restored One","111"\n"Restored Two","222"';
        ContentVersion cv = new ContentVersion(
            Title = da.Name,
            PathOnClient = da.Name + '.csv',
            VersionData = Blob.valueOf(csv),
            Description = 'Part 1'
        );
        insert cv;

        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion WHERE Id = :cv.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId    = da.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
    }

    @IsTest
    static void testQueueable_UnarchivesAndDeletesArtifacts() {
        Data_Archive__c da = [
            SELECT Id, Name FROM Data_Archive__c LIMIT 1
        ];

        Test.startTest();
        System.enqueueJob(new DataArchiveUnarchiveQueueable(new List<Id>{da.Id}));
        Test.stopTest();

        // Accounts inserted from CSV
        Integer acctCount = [SELECT COUNT() FROM Account WHERE Name IN ('Restored One','Restored Two')];
        System.assertEquals(2, acctCount, 'Expected two accounts inserted from CSV');

        // Archive and documents deleted
        Integer remArchives = [SELECT COUNT() FROM Data_Archive__c WHERE Id = :da.Id];
        System.assertEquals(0, remArchives, 'Archive header should be deleted');

        Integer remLinks = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :da.Id];
        System.assertEquals(0, remLinks, 'Links should be deleted as ContentDocument is removed');
    }

    @IsTest
    static void testQueueable_IgnoresInvalidFieldValues() {
        // Create an archive for Account with an invalid Integer field mapping via CSV to trigger catch and continue
        Data_Archive__c da = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c = 'Name,NumberOfEmployees',
            Status__c = 'Ready for Unarchive'
        );
        insert da;
        da = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :da.Id];

        // invalid integer for NumberOfEmployees should be ignored safely
        String csv = 'Name,NumberOfEmployees\n"Invalid Emp","NotANumber"';
        ContentVersion cv = new ContentVersion(
            Title = da.Name,
            PathOnClient = da.Name + '.csv',
            VersionData = Blob.valueOf(csv)
        );
        insert cv;

        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion WHERE Id = :cv.Id
        ];
        insert new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId    = da.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        Test.startTest();
        System.enqueueJob(new DataArchiveUnarchiveQueueable(new List<Id>{da.Id}));
        Test.stopTest();

        // Record should insert with only Name set (hasData true because Name is valid)
        Account a = [SELECT Id, Name, NumberOfEmployees FROM Account WHERE Name = 'Invalid Emp' LIMIT 1];
        System.assertEquals('Invalid Emp', a.Name);
    }
}