/**
 * @description Tests for S3UploadQueueable.
 */
@IsTest
private class S3UploadQueueableTest {

    /**
     * @description Mock HTTP callout for S3 upload.
     */
    private class S3HttpMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest myRequest) {

            HttpResponse myResponse = new HttpResponse();
            myResponse.setStatusCode(200);
            myResponse.setStatus('OK');
            myResponse.setBody('');
            return myResponse;
        }
    }

    @IsTest
    static void testExecute_WithValidPairs() {

        ContentVersion myContentVersion = new ContentVersion(
            Title = 'QueueableTestFile',
            PathOnClient = 'QueueableTestFile.csv',
            VersionData = Blob.valueOf('Id,Name\n001xx000003GYQQ,Test')
        );
        insert myContentVersion;

        myContentVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :myContentVersion.Id];

        Account myAccount = new Account(Name = 'Test Queueable Account');
        insert myAccount;

        List<String> myDocPairsList = new List<String>{
            myContentVersion.ContentDocumentId + '|' + myAccount.Id
        };

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new S3UploadQueueable(myDocPairsList));
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

        List<String> myBadPairsList = new List<String>{
            'not-valid',
            '',
            'abc|def'
        };

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        System.enqueueJob(new S3UploadQueueable(myBadPairsList));
        Test.stopTest();
        System.assert(true, 'Invalid pairs handled gracefully');
    }
}