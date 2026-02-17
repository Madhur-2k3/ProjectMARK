@IsTest
private class S3ControllerTest {

    // ─── Reusable HTTP Mock ───────────────────────────────────────────
    private class S3HttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        S3HttpMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus(statusCode == 200 ? 'OK' : 'Error');
            res.setBody(body);
            return res;
        }
    }

    // ─── getDataFromS3 ───────────────────────────────────────────────

    @IsTest
    static void testGetDataFromS3_Success() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, '{"data":"value"}'));
        Test.startTest();
        String result = S3Controller.getDataFromS3('test-file.csv');
        Test.stopTest();
        System.assertEquals('{"data":"value"}', result, 'Should return response body on 200');
    }

    @IsTest
    static void testGetDataFromS3_Error() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(404, 'Not Found'));
        Test.startTest();
        try {
            S3Controller.getDataFromS3('missing-file.csv');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null, 'Exception message should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetDataFromS3_NullFileName() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, 'ok'));
        Test.startTest();
        String result = S3Controller.getDataFromS3(null);
        Test.stopTest();
        System.assertEquals('ok', result, 'Should still succeed with null filename');
    }

    // ─── listObjectsFromS3 ──────────────────────────────────────────

    @IsTest
    static void testListObjectsFromS3_Success() {
        String xmlBody =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
            '  <Contents>' +
            '    <Key>folder/file1.csv</Key>' +
            '    <Size>1024</Size>' +
            '  </Contents>' +
            '  <Contents>' +
            '    <Key>folder/file2.csv</Key>' +
            '    <Size>2048</Size>' +
            '  </Contents>' +
            '</ListBucketResult>';

        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, xmlBody));
        Test.startTest();
        String result = S3Controller.listObjectsFromS3();
        Test.stopTest();

        List<Object> items = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(2, items.size(), 'Should return 2 items parsed from XML');
    }

    @IsTest
    static void testListObjectsFromS3_Error() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(500, 'Internal Server Error'));
        Test.startTest();
        try {
            S3Controller.listObjectsFromS3();
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }
        Test.stopTest();
    }

    // ─── putObjectToS3 ──────────────────────────────────────────────

    @IsTest
    static void testPutObjectToS3_Success() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, ''));
        Test.startTest();
        String base64Body = EncodingUtil.base64Encode(Blob.valueOf('test data'));
        String result = S3Controller.putObjectToS3('folder/test.csv', base64Body, 'text/csv');
        Test.stopTest();
        System.assert(result.contains('200'), 'Result should contain status code 200');
    }

    @IsTest
    static void testPutObjectToS3_Error() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(403, 'Forbidden'));
        Test.startTest();
        try {
            String base64Body = EncodingUtil.base64Encode(Blob.valueOf('test data'));
            S3Controller.putObjectToS3('folder/test.csv', base64Body, 'text/csv');
            System.assert(false, 'Should have thrown S3ControllerException');
        } catch (S3ControllerException ex) {
            System.assert(ex.getMessage().contains('403'), 'Error should reference 403 status');
        }
        Test.stopTest();
    }

    @IsTest
    static void testPutObjectToS3_EmptyBody() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, ''));
        Test.startTest();
        String result = S3Controller.putObjectToS3('folder/empty.csv', '', 'text/csv');
        Test.stopTest();
        System.assert(result.contains('200'), 'Should succeed with empty body');
    }

    @IsTest
    static void testPutObjectToS3_NullContentType() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, ''));
        Test.startTest();
        String base64Body = EncodingUtil.base64Encode(Blob.valueOf('data'));
        String result = S3Controller.putObjectToS3('folder/file.csv', base64Body, null);
        Test.stopTest();
        System.assert(result.contains('200'), 'Should succeed with null content type');
    }
}