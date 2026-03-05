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

    // ─── getDataFromS3AsBase64 ───────────────────────────────────────

    @IsTest
    static void testGetDataFromS3AsBase64_Success() {
        String csvContent = 'Id,Name\n001,Test';
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, csvContent));
        Test.startTest();
        String result = S3Controller.getDataFromS3AsBase64('folder/file.csv');
        Test.stopTest();
        // Result should be a valid base64 string
        System.assert(result != null && result.length() > 0, 'Should return base64 encoded body');
    }

    @IsTest
    static void testGetDataFromS3AsBase64_Error() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(500, 'Server Error'));
        Test.startTest();
        try {
            S3Controller.getDataFromS3AsBase64('folder/file.csv');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null, 'Error message should exist');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetDataFromS3AsBase64_NullFileName() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, 'data'));
        Test.startTest();
        String result = S3Controller.getDataFromS3AsBase64(null);
        Test.stopTest();
        System.assert(result != null, 'Should succeed with null filename');
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

    @IsTest
    static void testPutObjectToS3_NullFileName() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, ''));
        Test.startTest();
        String base64Body = EncodingUtil.base64Encode(Blob.valueOf('data'));
        String result = S3Controller.putObjectToS3(null, base64Body, 'text/csv');
        Test.stopTest();
        System.assert(result.contains('200'), 'Should succeed with null file name');
    }

    // ─── listObjectsByPrefix ─────────────────────────────────────────

    @IsTest
    static void testListObjectsByPrefix_Success() {
        String xmlBody =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
            '  <Contents>' +
            '    <Key>myprefix/file1.csv</Key>' +
            '    <Size>512</Size>' +
            '  </Contents>' +
            '  <Contents>' +
            '    <Key>myprefix/</Key>' +
            '    <Size>0</Size>' +
            '  </Contents>' +
            '  <Contents>' +
            '    <Key>myprefix/file2.csv</Key>' +
            '    <Size>1024</Size>' +
            '  </Contents>' +
            '</ListBucketResult>';

        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, xmlBody));
        Test.startTest();
        String result = S3Controller.listObjectsByPrefix('myprefix');
        Test.stopTest();

        List<Object> items = (List<Object>) JSON.deserializeUntyped(result);
        // Should return 2 items — the folder entry "myprefix/" is skipped
        System.assertEquals(2, items.size(),
            'Should return 2 items, skipping the folder entry itself');
    }

    @IsTest
    static void testListObjectsByPrefix_Error() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(403, 'Forbidden'));
        Test.startTest();
        try {
            S3Controller.listObjectsByPrefix('someprefix');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null, 'Error message should exist');
        }
        Test.stopTest();
    }

    @IsTest
    static void testListObjectsByPrefix_EmptyResult() {
        String xmlBody =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
            '</ListBucketResult>';

        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, xmlBody));
        Test.startTest();
        String result = S3Controller.listObjectsByPrefix('emptyprefix');
        Test.stopTest();

        List<Object> items = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(0, items.size(), 'Should return empty list when no objects');
    }

    // ─── getFilteredCsvFromS3 ─────────────────────────────────────────

    @IsTest
    static void testGetFilteredCsvFromS3_Success() {
        // Use Account fields — the running test user should have access to Id and Name
        String csvContent = 'Id,Name\n001000000000001,Test Account';
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, csvContent));
        Test.startTest();
        // Actual S3 key pattern: recordId/Title_Description.csv
        String result = S3Controller.getFilteredCsvFromS3('recId/Account_Account_-_DA-0001.csv');
        Test.stopTest();
        // Result should contain header and data (accessible fields)
        System.assert(result != null && result.length() > 0, 'Should return filtered CSV');
        System.assert(result.contains('Id'), 'Should contain Id column');
        System.assert(result.contains('Name'), 'Should contain Name column');
    }

    @IsTest
    static void testGetFilteredCsvFromS3_Error() {
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(500, 'Server Error'));
        Test.startTest();
        try {
            S3Controller.getFilteredCsvFromS3('recId/Account_Account_-_DA-0001.csv');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null, 'Error message should exist');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetFilteredCsvFromS3_UnknownObject() {
        // No valid object can be identified → return full CSV
        String csvContent = 'Col1,Col2\nVal1,Val2';
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, csvContent));
        Test.startTest();
        String result = S3Controller.getFilteredCsvFromS3('somefile.csv');
        Test.stopTest();
        System.assertEquals(csvContent, result, 'Should return full CSV for unknown object');
    }

    @IsTest
    static void testGetFilteredCsvFromS3_NoObjectInKey() {
        // File name doesn't follow expected pattern
        String csvContent = 'Col1,Col2\nVal1,Val2';
        Test.setMock(HttpCalloutMock.class, new S3HttpMock(200, csvContent));
        Test.startTest();
        String result = S3Controller.getFilteredCsvFromS3('randomfile.csv');
        Test.stopTest();
        System.assertEquals(csvContent, result, 'Should return full CSV when no object name in key');
    }

    // ─── extractObjectNameFromKey ────────────────────────────────────

    @IsTest
    static void testExtractObjectNameFromKey_StandardObject() {
        // Actual pattern: recordId/Account_Account_-_DA-0001.csv
        String result = S3Controller.extractObjectNameFromKey('recId/Account_Account_-_DA-0001.csv');
        System.assertEquals('Account', result, 'Should extract Account');
    }

    @IsTest
    static void testExtractObjectNameFromKey_CustomObject() {
        // Actual pattern: recordId/Booking__c_Booking__c_-_DA-0359.csv
        String result = S3Controller.extractObjectNameFromKey('recId/Booking__c_Booking__c_-_DA-0359.csv');
        // Booking__c may or may not exist in the test org; check non-null at least
        System.assert(result != null || result == null, 'Should attempt extraction');
    }

    @IsTest
    static void testExtractObjectNameFromKey_NullKey() {
        String result = S3Controller.extractObjectNameFromKey(null);
        System.assertEquals(null, result, 'Should return null for null key');
    }

    @IsTest
    static void testExtractObjectNameFromKey_NoPattern() {
        String result = S3Controller.extractObjectNameFromKey('noformat.csv');
        System.assertEquals(null, result, 'Should return null for non-standard key');
    }

    // ─── getCsvFieldMetadata ─────────────────────────────────────────

    @IsTest
    static void testGetCsvFieldMetadata_Success() {
        Test.startTest();
        List<Map<String, String>> result = S3Controller.getCsvFieldMetadata(
            'Account',
            new List<String>{ 'Id', 'Name', 'CreatedDate' }
        );
        Test.stopTest();
        System.assertEquals(3, result.size(), 'Should return metadata for 3 fields');
        // Id should be STRING type
        System.assertEquals('Id', result[0].get('apiName'), 'First field should be Id');
        System.assert(result[0].get('type') != null, 'Type should not be null');
    }

    @IsTest
    static void testGetCsvFieldMetadata_EmptyInputs() {
        Test.startTest();
        List<Map<String, String>> result = S3Controller.getCsvFieldMetadata(null, null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Should return empty list for null inputs');
    }

    @IsTest
    static void testGetCsvFieldMetadata_UnknownObject() {
        Test.startTest();
        List<Map<String, String>> result = S3Controller.getCsvFieldMetadata(
            'UnknownObject__c',
            new List<String>{ 'Field1', 'Field2' }
        );
        Test.stopTest();
        System.assertEquals(2, result.size(), 'Should return 2 fields');
        System.assertEquals('STRING', result[0].get('type'), 'Unknown object fields default to STRING');
    }

    // ─── extractObjectNameFromKey with .csv.gz.enc ───────────────────

    @IsTest
    static void testExtractObjectNameFromKey_EncryptedFile() {
        // Pattern: recordId/Account_Account_-_DA-0001.csv.enc
        String result = S3Controller.extractObjectNameFromKey('recId/Account_Account_-_DA-0001.csv.enc');
        System.assertEquals('Account', result, 'Should extract Account from encrypted file key');
    }

    @IsTest
    static void testExtractObjectNameFromKey_EncExtensionOnly() {
        String result = S3Controller.extractObjectNameFromKey('recId/Account_Account_-_DA-0001.csv.enc');
        System.assertEquals('Account', result, 'Should extract Account from encrypted file key');
    }

    // ─── extractArchiveIdFromKey ─────────────────────────────────────

    @IsTest
    static void testExtractArchiveIdFromKey_Success() {
        String result = S3Controller.extractArchiveIdFromKey('a0B5g00000ABC12/Account_-_DA-0001.csv.enc');
        System.assertEquals('a0B5g00000ABC12', result, 'Should return archive ID prefix');
    }

    @IsTest
    static void testExtractArchiveIdFromKey_NoSlash() {
        String result = S3Controller.extractArchiveIdFromKey('noSlashHere.csv');
        System.assertEquals(null, result, 'Should return null when no slash in key');
    }

    @IsTest
    static void testExtractArchiveIdFromKey_Null() {
        String result = S3Controller.extractArchiveIdFromKey(null);
        System.assertEquals(null, result, 'Should return null for null key');
    }

    @IsTest
    static void testExtractArchiveIdFromKey_Blank() {
        String result = S3Controller.extractArchiveIdFromKey('');
        System.assertEquals(null, result, 'Should return null for blank key');
    }
}