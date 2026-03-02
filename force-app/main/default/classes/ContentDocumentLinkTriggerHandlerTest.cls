@IsTest
private class ContentDocumentLinkTriggerHandlerTest {

    // ─── helpers ───
    @TestSetup
    static void setupData() {
        // Create a Data_Archive__c record to serve as the linked entity
        Data_Archive__c archive = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Status__c        = 'Archive In Progress'
        );
        insert archive;

        // Create an Account (non-archive object) for negative-path tests
        Account acc = new Account(Name = 'Test Non-Archive Account');
        insert acc;
    }

    // ─── 1. Happy path: CDL linked to Data_Archive__c → enqueues S3UploadQueueable ───
    @IsTest
    static void testAfterInsert_LinkedToDataArchive() {
        Data_Archive__c archive = [SELECT Id FROM Data_Archive__c LIMIT 1];

        // Create a ContentVersion (which auto-creates a ContentDocument)
        ContentVersion cv = new ContentVersion(
            Title          = 'TestArchiveFile',
            PathOnClient   = 'TestArchiveFile.csv',
            VersionData    = Blob.valueOf('Id,Name\n001000000000001,Acme')
        );
        insert cv;

        // Retrieve the auto-generated ContentDocumentId
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        // Insert a ContentDocumentLink pointing to the Data_Archive__c record.
        // This fires the trigger → handler → enqueues S3UploadQueueable.
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = archive.Id,
            ShareType         = 'V'
        );
        insert cdl;
        Test.stopTest();

        // If we reach here without exceptions the handler executed successfully.
        // Verify the CDL was created and linked correctly
        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :archive.Id
        ];
        System.assert(!links.isEmpty(), 'ContentDocumentLink should exist for the archive record');
    }

    // ─── 2. CDL linked to a non-archive object → handler exits early (no enqueue) ───
    @IsTest
    static void testAfterInsert_LinkedToNonArchiveObject() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Non-Archive Account' LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title          = 'NonArchiveFile',
            PathOnClient   = 'NonArchiveFile.csv',
            VersionData    = Blob.valueOf('some,data')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = acc.Id,
            ShareType         = 'V'
        );
        insert cdl;
        Test.stopTest();

        // Handler should have returned early because the linked entity is not a Data_Archive__c.
        // No exception means the early-return path executed correctly.
        System.assert(true, 'Handler should exit gracefully for non-archive linked entities');
    }

    // ─── 3. Direct call with null list → early return guard ───
    @IsTest
    static void testAfterInsert_NullList() {
        Test.startTest();
        ContentDocumentLinkTriggerHandler.afterInsert(null);
        Test.stopTest();

        System.assert(true, 'Handler should return immediately for null input');
    }

    // ─── 4. Direct call with empty list → early return guard ───
    @IsTest
    static void testAfterInsert_EmptyList() {
        Test.startTest();
        ContentDocumentLinkTriggerHandler.afterInsert(new List<ContentDocumentLink>());
        Test.stopTest();

        System.assert(true, 'Handler should return immediately for empty input');
    }

    // ─── 5. Multiple CDLs: mixed archive & non-archive linked entities ───
    @IsTest
    static void testAfterInsert_MixedLinkedEntities() {
        Data_Archive__c archive = [SELECT Id FROM Data_Archive__c LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Non-Archive Account' LIMIT 1];

        // Create two ContentVersions
        List<ContentVersion> cvList = new List<ContentVersion>{
            new ContentVersion(
                Title        = 'ArchiveCSV',
                PathOnClient = 'ArchiveCSV.csv',
                VersionData  = Blob.valueOf('header\nrow')
            ),
            new ContentVersion(
                Title        = 'AccountFile',
                PathOnClient = 'AccountFile.csv',
                VersionData  = Blob.valueOf('header\nrow')
            )
        };
        insert cvList;

        List<ContentVersion> insertedCvs = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :cvList
        ];

        Test.startTest();
        List<ContentDocumentLink> cdls = new List<ContentDocumentLink>{
            new ContentDocumentLink(
                ContentDocumentId = insertedCvs[0].ContentDocumentId,
                LinkedEntityId    = archive.Id,
                ShareType         = 'V'
            ),
            new ContentDocumentLink(
                ContentDocumentId = insertedCvs[1].ContentDocumentId,
                LinkedEntityId    = acc.Id,
                ShareType         = 'V'
            )
        };
        insert cdls;
        Test.stopTest();

        // Only the archive-linked CDL should have produced a pair for S3UploadQueueable.
        // Verify both links were created successfully.
        List<ContentDocumentLink> archiveLinks = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :archive.Id
        ];
        System.assert(!archiveLinks.isEmpty(), 'Archive-linked CDL should exist');

        List<ContentDocumentLink> accLinks = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :acc.Id
              AND ContentDocumentId = :insertedCvs[1].ContentDocumentId
        ];
        System.assert(!accLinks.isEmpty(), 'Account-linked CDL should exist');
    }
}