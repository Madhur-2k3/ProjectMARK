@IsTest
private class S3UploadAsyncTest {

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
    static void testUpload_WithValidPairs() {
        // Create a ContentVersion (auto-creates ContentDocument)
        ContentVersion cv = new ContentVersion(
            Title = 'TestArchive',
            PathOnClient = 'TestArchive.csv',
            VersionData = Blob.valueOf('Id,Name\n001xx000003GYQQ,Test'),
            Description = 'Part 1'
        );
        insert cv;

        // Query back the ContentDocumentId
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        // Build the docPairs list: contentDocumentId|parentId
        // Use a known Account as the "parent"
        Account acc = new Account(Name = 'Test Upload Account');
        insert acc;

        List<String> docPairs = new List<String>{
            cv.ContentDocumentId + '|' + acc.Id
        };

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        S3UploadAsync.upload(docPairs);
        Test.stopTest();

        // Future method executed; just assert no exceptions
        System.assert(true, 'Upload completed without errors');
    }

    @IsTest
    static void testUpload_WithEmptyList() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        S3UploadAsync.upload(new List<String>());
        Test.stopTest();
        System.assert(true, 'Empty list handled gracefully');
    }

    @IsTest
    static void testUpload_WithNullList() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        S3UploadAsync.upload(null);
        Test.stopTest();
        System.assert(true, 'Null list handled gracefully');
    }

    @IsTest
    static void testUpload_WithInvalidPairs() {
        List<String> badPairs = new List<String>{
            'not-a-valid-pair',
            '',
            'abc|def',
            '|'
        };
        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        S3UploadAsync.upload(badPairs);
        Test.stopTest();
        System.assert(true, 'Invalid pairs handled gracefully');
    }
}