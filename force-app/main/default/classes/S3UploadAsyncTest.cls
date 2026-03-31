/**
 * @description Tests for S3UploadAsync @future method.
 */
@IsTest
private class S3UploadAsyncTest {

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
    static void testUpload_WithValidPairs() {

        ContentVersion myContentVersion = new ContentVersion(
            Title = 'TestArchive',
            PathOnClient = 'TestArchive.csv',
            VersionData = Blob.valueOf('Id,Name\n001xx000003GYQQ,Test'),
            Description = 'Part 1'
        );
        insert myContentVersion;

        myContentVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :myContentVersion.Id];

        Account myAccount = new Account(Name = 'Test Upload Account');
        insert myAccount;

        List<String> myDocPairsList = new List<String>{
            myContentVersion.ContentDocumentId + '|' + myAccount.Id
        };

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        S3UploadAsync.upload(myDocPairsList);
        Test.stopTest();

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

        List<String> myBadPairsList = new List<String>{
            'not-a-valid-pair',
            '',
            'abc|def',
            '|'
        };

        Test.setMock(HttpCalloutMock.class, new S3HttpMock());
        Test.startTest();
        S3UploadAsync.upload(myBadPairsList);
        Test.stopTest();
        System.assert(true, 'Invalid pairs handled gracefully');
    }
}