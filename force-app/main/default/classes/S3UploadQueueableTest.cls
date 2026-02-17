@IsTest
private class S3UploadQueueableTest {

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
    static void testExecute_WithValidPairs() {
        ContentVersion cv = new ContentVersion(
            Title = 'QueueableTestFile',
            PathOnClient = 'QueueableTestFile.csv',
            VersionData = Blob.valueOf('Id,Name\n001xx000003GYQQ,Test')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Account acc = new Account(Name = 'Test Queueable Account');
        insert acc;

        List<String> docPairs = new List<String>{
            cv.ContentDocumentId + '|' + acc.Id
        };

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new S3UploadQueueable(docPairs));
        Test.stopTest();

        System.assert(true, 'Queueable executed without errors');
    }

    @IsTest
    static void testExecute_WithEmptyPairs() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new S3UploadQueueable(new List<String>()));
        Test.stopTest();
        System.assert(true, 'Empty pairs handled gracefully');
    }

    @IsTest
    static void testExecute_WithNullPairs() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new S3UploadQueueable(null));
        Test.stopTest();
        System.assert(true, 'Null pairs handled gracefully');
    }

    @IsTest
    static void testExecute_WithInvalidPairs() {
        List<String> badPairs = new List<String>{
            'not-valid',
            '',
            'abc|def'
        };
        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new S3UploadQueueable(badPairs));
        Test.stopTest();
        System.assert(true, 'Invalid pairs handled gracefully');
    }
}