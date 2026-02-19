@IsTest
private class ArchivePostProcessQueueableTest {

    private class S3HttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('');
            return res;
        }
    }

    @IsTest
    static void testExecute_UploadsAndDeletes() {
        // Create an Account to serve as the record to be deleted
        Account acc = new Account(Name = 'Archive Delete Test');
        insert acc;

        // Create a ContentVersion (archive CSV file)
        ContentVersion cv = new ContentVersion(
            Title = 'ArchiveExport',
            PathOnClient = 'ArchiveExport.csv',
            VersionData = Blob.valueOf('Id,Name\n001xx000003GYQQ,Acme'),
            Description = 'Part 1'
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        // Use the Account Id as both the archiveRecordId and the parent to delete
        List<Id> contentDocIds = new List<Id>{ cv.ContentDocumentId };
        List<Id> parentIds = new List<Id>{ acc.Id };

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new ArchivePostProcessQueueable(
            contentDocIds,
            acc.Id,
            'Account',
            parentIds
        ));
        Test.stopTest();

        // Verify the Account was deleted
        List<Account> remaining = [SELECT Id FROM Account WHERE Id = :acc.Id];
        System.assertEquals(0, remaining.size(), 'Account should have been deleted');
    }

    @IsTest
    static void testExecute_NoContentDocs() {
        Account acc = new Account(Name = 'No Docs Test');
        insert acc;

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new ArchivePostProcessQueueable(
            new List<Id>(),
            null,
            'Account',
            new List<Id>{ acc.Id }
        ));
        Test.stopTest();

        // Upload skipped but delete should still fire
        List<Account> remaining = [SELECT Id FROM Account WHERE Id = :acc.Id];
        System.assertEquals(0, remaining.size(), 'Account should have been deleted even without docs');
    }

    @IsTest
    static void testExecute_NullArchiveId() {
        ContentVersion cv = new ContentVersion(
            Title = 'NullArchiveTest',
            PathOnClient = 'NullArchiveTest.csv',
            VersionData = Blob.valueOf('test')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new ArchivePostProcessQueueable(
            new List<Id>{ cv.ContentDocumentId },
            null,
            'Account',
            new List<Id>()
        ));
        Test.stopTest();

        // archiveRecordId is null so upload is skipped, no parents to delete either
        System.assert(true, 'Executed without errors when archiveRecordId is null');
    }

    @IsTest
    static void testExecute_NoParentIds() {
        Account acc = new Account(Name = 'No Parents Test');
        insert acc;

        ContentVersion cv = new ContentVersion(
            Title = 'NoParentsFile',
            PathOnClient = 'NoParentsFile.csv',
            VersionData = Blob.valueOf('data'),
            Description = 'export'
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new ArchivePostProcessQueueable(
            new List<Id>{ cv.ContentDocumentId },
            acc.Id,
            'Account',
            new List<Id>()
        ));
        Test.stopTest();

        // Upload should run, but no parents to delete
        List<Account> remaining = [SELECT Id FROM Account WHERE Id = :acc.Id];
        System.assertEquals(1, remaining.size(), 'Account should NOT be deleted when parentIds is empty');
    }

    @IsTest
    static void testExecute_NullConstructorArgs() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new ArchivePostProcessQueueable(
            null,
            null,
            'Account',
            null
        ));
        Test.stopTest();
        System.assert(true, 'Null constructor args handled safely');
    }
}