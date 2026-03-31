/**
 * @description Controller for AWS S3 interactions including get, put, list operations.
 *              Handles CSV filtering by FLS, encryption/decryption, and file key encoding.
 */
public with sharing class S3Controller {

    /**
     * @description Fetches data from S3 as a plain text string.
     * @param fileNameStr The S3 key (file path) to retrieve.
     * @return The file content as a string. Decrypted if the file has .enc extension.
     */
    @AuraEnabled(cacheable=false)
    public static String getDataFromS3(String fileNameStr) {

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        String endpointStr = 'callout:aws_s3';

        if (fileNameStr != null && fileNameStr.trim().length() > 0) {
            if (!endpointStr.endsWith('/')) endpointStr += '/';
            endpointStr += encodeS3KeyPreserveSlashes(fileNameStr);
        }

        request.setEndpoint(endpointStr);
        request.setHeader('Accept', '*/*');

        Http http = new Http();
        HttpResponse response;

        try {
            response = http.send(request);
        } catch (Exception ex) {
            String errorStr = 's3Controller.getDataFromS3 exception: ' + ex.getMessage() + '\n' + ex.getStackTraceString();
            throw new AuraHandledException(errorStr);
        }

        if (response == null) {
            throw new AuraHandledException('s3Controller.getDataFromS3 error: Empty HttpResponse');
        }

        Integer statusInt = response.getStatusCode();

        if (statusInt == 200) {
            if (fileNameStr != null && fileNameStr.endsWith('.enc')) {
                Blob bodyBlob = response.getBodyAsBlob();
                return decryptFromS3(bodyBlob, fileNameStr);
            }
            return response.getBody();
        } else {
            String bodyStr = '';
            try { bodyStr = response.getBody(); } catch (Exception ex) { bodyStr = '<could not read response body>'; }
            String errorStr = 'Error fetching data from S3: status=' + statusInt + ' statusText=' + response.getStatus() + ' body=' + bodyStr;
            throw new AuraHandledException(errorStr);
        }
    }

    /**
     * @description Fetches data from S3 and returns it as a base64-encoded string.
     * @param fileNameStr The S3 key (file path) to retrieve.
     * @return The file content as a base64-encoded string.
     */
    @AuraEnabled(cacheable=false)
    public static String getDataFromS3AsBase64(String fileNameStr) {

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        String endpointStr = 'callout:aws_s3';

        if (fileNameStr != null && fileNameStr.trim().length() > 0) {
            if (!endpointStr.endsWith('/')) endpointStr += '/';
            endpointStr += encodeS3KeyPreserveSlashes(fileNameStr);
        }

        request.setEndpoint(endpointStr);
        request.setHeader('Accept', '*/*');

        Http http = new Http();
        HttpResponse response;

        try {
            response = http.send(request);
        } catch (Exception ex) {
            String errorStr = 's3Controller.getDataFromS3AsBase64 exception: ' + ex.getMessage() + '\n' + ex.getStackTraceString();
            throw new AuraHandledException(errorStr);
        }

        if (response == null) {
            throw new AuraHandledException('s3Controller.getDataFromS3AsBase64 error: Empty HttpResponse');
        }

        Integer statusInt = response.getStatusCode();

        if (statusInt == 200) {
            Blob bodyBlob = response.getBodyAsBlob();

            if (fileNameStr != null && fileNameStr.endsWith('.enc')) {
                String decryptedStr = decryptFromS3(bodyBlob, fileNameStr);
                return EncodingUtil.base64Encode(Blob.valueOf(decryptedStr));
            }

            return EncodingUtil.base64Encode(bodyBlob);
        } else {
            String bodyStr = '';
            try { bodyStr = response.getBody(); } catch (Exception ex) { bodyStr = '<could not read response body>'; }
            String errorStr = 'Error fetching data from S3: status=' + statusInt + ' statusText=' + response.getStatus() + ' body=' + bodyStr;
            throw new AuraHandledException(errorStr);
        }
    }

    /**
     * @description Lists all objects in the S3 bucket using ListObjectsV2 API.
     * @return A JSON-serialized list of S3 object metadata maps.
     */
    @AuraEnabled(cacheable=false)
    public static String listObjectsFromS3() {

        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            String endpointStr = 'callout:aws_s3?list-type=2';
            request.setEndpoint(endpointStr);

            Http http = new Http();
            HttpResponse response = http.send(request);

            if (response.getStatusCode() == 200) {

                String bodyStr = response.getBody();
                Dom.Document document = new Dom.Document();
                document.load(bodyStr);
                Dom.XmlNode rootNode = document.getRootElement();

                List<Map<String, Object>> itemsList = new List<Map<String, Object>>();

                for (Dom.XmlNode childNode : rootNode.getChildElements()) {

                    if (childNode.getName() == 'Contents') {

                        Map<String, Object> itemMap = new Map<String, Object>();

                        for (Dom.XmlNode contentChild : childNode.getChildElements()) {
                            itemMap.put(contentChild.getName(), contentChild.getText());
                        }

                        itemsList.add(itemMap);
                    }
                }

                return JSON.serialize(itemsList);
            } else {
                throw new AuraHandledException('Error listing S3 objects: ' + response.getStatusCode() + ' ' + response.getStatus());
            }
        } catch (Exception ex) {
            throw new AuraHandledException('s3Controller.listObjectsFromS3 error: ' + ex.getMessage());
        }
    }

    /**
     * @description Uploads a file to S3 as a PUT request.
     * @param fileNameStr The S3 key (file path) for the uploaded file.
     * @param base64BodyStr The file content as a base64-encoded string.
     * @param contentTypeStr The MIME content type of the file.
     * @return A status string indicating success.
     */
    @AuraEnabled(cacheable=false)
    public static String putObjectToS3(String fileNameStr, String base64BodyStr, String contentTypeStr) {

        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('PUT');
            String endpointStr = 'callout:aws_s3';

            if (fileNameStr != null && fileNameStr.trim().length() > 0) {
                if (!endpointStr.endsWith('/')) endpointStr += '/';
                endpointStr += encodeS3KeyPreserveSlashes(fileNameStr);
            }

            request.setEndpoint(endpointStr);

            if (contentTypeStr != null) {
                request.setHeader('Content-Type', contentTypeStr);
            }

            if (base64BodyStr != null && base64BodyStr.trim().length() > 0) {
                Blob bodyBlob = EncodingUtil.base64Decode(base64BodyStr);
                request.setBodyAsBlob(bodyBlob);
            } else {
                request.setBody('');
            }

            Http http = new Http();
            HttpResponse response = http.send(request);

            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                return response.getStatus() + ' (' + response.getStatusCode() + ')';
            } else {
                String responseBodyStr = '';
                try { responseBodyStr = response.getBody(); } catch (Exception bodyEx) { responseBodyStr = '<could not read response body>'; }
                System.debug('S3Controller.putObjectToS3 error response: ' + response.getStatusCode() + ' ' + response.getStatus() + ' body: ' + responseBodyStr);
                throw new S3ControllerException('Error uploading to S3: ' + response.getStatusCode() + ' ' + response.getStatus() + ' body=' + responseBodyStr);
            }
        } catch (Exception ex) {
            throw new S3ControllerException('s3Controller.putObjectToS3 error: ' + ex.getMessage());
        }
    }

    /**
     * @description Lists S3 objects filtered by a given prefix.
     * @param prefixStr The prefix to filter S3 objects by.
     * @return A JSON-serialized list of matching S3 object metadata maps.
     */
    @AuraEnabled(cacheable=false)
    public static String listObjectsByPrefix(String prefixStr) {

        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            String encodedPrefixStr = EncodingUtil.urlEncode(prefixStr, 'UTF-8').replace('+', '%20');
            String endpointStr = 'callout:aws_s3?list-type=2&prefix=' + encodedPrefixStr + '/';
            request.setEndpoint(endpointStr);

            Http http = new Http();
            HttpResponse response = http.send(request);

            if (response.getStatusCode() == 200) {

                String bodyStr = response.getBody();
                Dom.Document document = new Dom.Document();
                document.load(bodyStr);
                Dom.XmlNode rootNode = document.getRootElement();

                List<Map<String, Object>> itemsList = new List<Map<String, Object>>();

                for (Dom.XmlNode childNode : rootNode.getChildElements()) {

                    if (childNode.getName() == 'Contents') {

                        Map<String, Object> itemMap = new Map<String, Object>();

                        for (Dom.XmlNode contentChild : childNode.getChildElements()) {
                            itemMap.put(contentChild.getName(), contentChild.getText());
                        }

                        String keyStr = (String) itemMap.get('Key');

                        if (keyStr != null && keyStr != prefixStr + '/') {
                            itemsList.add(itemMap);
                        }
                    }
                }

                return JSON.serialize(itemsList);
            } else {
                throw new AuraHandledException('Error listing S3 objects by prefix: ' + response.getStatusCode() + ' ' + response.getStatus());
            }
        } catch (Exception ex) {
            System.debug('S3Controller.listObjectsByPrefix error: ' + ex.getMessage());
            throw new AuraHandledException('s3Controller.listObjectsByPrefix error: ' + ex.getMessage());
        }
    }

    /**
     * @description Fetches CSV from S3 and filters columns based on Field-Level Security.
     * @param fileNameStr The S3 key of the CSV file.
     * @return The filtered CSV content with only accessible columns.
     */
    @AuraEnabled(cacheable=false)
    public static String getFilteredCsvFromS3(String fileNameStr) {

        String rawCsvStr = getDataFromS3(fileNameStr);

        if (String.isBlank(rawCsvStr)) {
            return rawCsvStr;
        }

        String objectNameStr = extractObjectNameFromKey(fileNameStr);

        if (String.isBlank(objectNameStr)) {
            return rawCsvStr;
        }

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectNameStr);

        if (objType == null) {
            return rawCsvStr;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        List<String> linesList = rawCsvStr.split('\n');

        if (linesList.isEmpty()) {
            return rawCsvStr;
        }

        List<String> headersList = parseCsvLine(linesList[0]);

        List<Integer> accessibleIndicesList = new List<Integer>();
        List<String>  accessibleHeadersList = new List<String>();

        for (Integer colIndex = 0; colIndex < headersList.size(); colIndex++) {

            String fieldNameStr = headersList[colIndex].trim();

            String baseFieldStr = fieldNameStr.contains('.')
                ? fieldNameStr.substringBefore('.')
                : fieldNameStr;

            Schema.SObjectField sField = fieldMap.get(baseFieldStr.toLowerCase());

            if (sField != null && sField.getDescribe().isAccessible()) {
                accessibleIndicesList.add(colIndex);
                accessibleHeadersList.add(fieldNameStr);
            } else if (sField == null) {
                accessibleIndicesList.add(colIndex);
                accessibleHeadersList.add(fieldNameStr);
            }
        }

        if (accessibleIndicesList.size() == headersList.size()) {
            return rawCsvStr;
        }

        List<String> filteredLinesList = new List<String>();
        filteredLinesList.add(String.join(accessibleHeadersList, ','));

        for (Integer lineIndex = 1; lineIndex < linesList.size(); lineIndex++) {

            String currentLineStr = linesList[lineIndex];
            if (String.isBlank(currentLineStr)) continue;

            List<String> cellsList = parseCsvLine(currentLineStr);
            List<String> filteredCellsList = new List<String>();

            for (Integer accessibleIdx : accessibleIndicesList) {

                if (accessibleIdx < cellsList.size()) {
                    filteredCellsList.add(escapeCsvField(cellsList[accessibleIdx]));
                } else {
                    filteredCellsList.add('');
                }
            }

            filteredLinesList.add(String.join(filteredCellsList, ','));
        }

        return String.join(filteredLinesList, '\n');
    }

    /**
     * @description Returns field metadata (apiName, label, type) for CSV column headers.
     * @param objectNameStr The API name of the SObject.
     * @param fieldNamesList List of field API names from the CSV header.
     * @return A list of maps containing apiName, label, and type for each field.
     */
    @AuraEnabled
    public static List<Map<String, String>> getCsvFieldMetadata(String objectNameStr, List<String> fieldNamesList) {

        List<Map<String, String>> resultList = new List<Map<String, String>>();

        if (String.isBlank(objectNameStr) || fieldNamesList == null || fieldNamesList.isEmpty()) {
            return resultList;
        }

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectNameStr);

        if (objType == null) {
            for (String fieldNameStr : fieldNamesList) {

                Map<String, String> fieldMetaMap = new Map<String, String>();
                fieldMetaMap.put('apiName', fieldNameStr);
                fieldMetaMap.put('label', fieldNameStr);
                fieldMetaMap.put('type', 'STRING');
                resultList.add(fieldMetaMap);
            }

            return resultList;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String fieldNameStr : fieldNamesList) {

            Map<String, String> fieldMetaMap = new Map<String, String>();
            String trimmedStr = fieldNameStr.trim();
            fieldMetaMap.put('apiName', trimmedStr);

            String lookupFieldStr = trimmedStr.contains('.')
                ? trimmedStr.substringBefore('.')
                : trimmedStr;

            Schema.SObjectField sField = fieldMap.get(lookupFieldStr.toLowerCase());

            if (sField != null) {
                Schema.DescribeFieldResult fieldDescribe = sField.getDescribe();
                fieldMetaMap.put('label', fieldDescribe.getLabel());
                fieldMetaMap.put('type', mapFieldType(fieldDescribe.getType()));
            } else {
                fieldMetaMap.put('label', trimmedStr);
                fieldMetaMap.put('type', 'STRING');
            }

            resultList.add(fieldMetaMap);
        }

        return resultList;
    }

    /**
     * @description Maps Salesforce DisplayType to filter builder operator-map keys.
     * @param displayType The Schema.DisplayType to map.
     * @return A string representing the filter type.
     */
    private static String mapFieldType(Schema.DisplayType displayType) {

        switch on displayType {
            when DATE {
                return 'DATE';
            }
            when DATETIME {
                return 'DATETIME';
            }
            when INTEGER, LONG {
                return 'INTEGER';
            }
            when DOUBLE, PERCENT {
                return 'DOUBLE';
            }
            when CURRENCY {
                return 'CURRENCY';
            }
            when BOOLEAN {
                return 'BOOLEAN';
            }
            when PICKLIST, MULTIPICKLIST {
                return 'PICKLIST';
            }
            when else {
                return 'STRING';
            }
        }
    }

    /**
     * @description Extracts the SObject API name from an S3 key.
     * @param keyStr The S3 file key to parse.
     * @return The SObject API name, or null if it cannot be determined.
     */
    @TestVisible
    private static String extractObjectNameFromKey(String keyStr) {

        if (String.isBlank(keyStr)) return null;

        String fileNameStr = keyStr.contains('/') ? keyStr.substringAfterLast('/') : keyStr;

        if (fileNameStr.endsWith('.enc')) {
            fileNameStr = fileNameStr.substringBeforeLast('.');
        }

        if (fileNameStr.endsWith('.zip')) {
            fileNameStr = fileNameStr.substringBeforeLast('.');
        }

        if (fileNameStr.contains('.')) {
            fileNameStr = fileNameStr.substringBeforeLast('.');
        }

        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();

        Integer daIdx = fileNameStr.indexOf('_-_DA-');

        if (daIdx > 0) {

            String beforeDaStr = fileNameStr.substring(0, daIdx);

            if (globalDescribeMap.containsKey(beforeDaStr)) {
                return beforeDaStr;
            }

            for (String suffixStr : new List<String>{'__c', '__mdt', '__e', '__b', '__x'}) {

                Integer suffixIdx = beforeDaStr.indexOf(suffixStr);

                if (suffixIdx > 0) {
                    String candidateStr = beforeDaStr.substring(0, suffixIdx + suffixStr.length());

                    if (globalDescribeMap.containsKey(candidateStr)) {
                        return candidateStr;
                    }
                }
            }

            List<String> segmentsList = beforeDaStr.split('_');

            if (segmentsList.size() > 0 && globalDescribeMap.containsKey(segmentsList[0])) {
                return segmentsList[0];
            }
        }

        if (globalDescribeMap.containsKey(fileNameStr)) {
            return fileNameStr;
        }

        return null;
    }

    /**
     * @description Parses a single CSV line, handling quoted fields that contain commas.
     * @param lineStr The CSV line to parse.
     * @return A list of field values extracted from the line.
     */
    private static List<String> parseCsvLine(String lineStr) {

        List<String> fieldsList = new List<String>();
        if (String.isBlank(lineStr)) return fieldsList;

        String currentStr = '';
        Boolean inQuotesFlag = false;

        for (Integer charIndex = 0; charIndex < lineStr.length(); charIndex++) {

            String charStr = lineStr.substring(charIndex, charIndex + 1);

            if (inQuotesFlag) {
                if (charStr == '"') {
                    if (charIndex + 1 < lineStr.length() && lineStr.substring(charIndex + 1, charIndex + 2) == '"') {
                        currentStr += '"';
                        charIndex++;
                    } else {
                        inQuotesFlag = false;
                    }
                } else {
                    currentStr += charStr;
                }
            } else {
                if (charStr == '"') {
                    inQuotesFlag = true;
                } else if (charStr == ',') {
                    fieldsList.add(currentStr.trim());
                    currentStr = '';
                } else if (charStr == '\r') {
                    continue;
                } else {
                    currentStr += charStr;
                }
            }
        }

        fieldsList.add(currentStr.trim());
        return fieldsList;
    }

    /**
     * @description Re-escapes a CSV field value if it contains commas, quotes, or newlines.
     * @param valueStr The field value to escape.
     * @return The CSV-escaped field value.
     */
    private static String escapeCsvField(String valueStr) {

        if (String.isBlank(valueStr)) return valueStr;

        Boolean needsQuotingFlag = valueStr.contains(',') || valueStr.contains('"') || valueStr.contains('\n');

        if (needsQuotingFlag) {
            return '"' + valueStr.replace('"', '""') + '"';
        }

        return valueStr;
    }

    /**
     * @description Decrypts an encrypted blob fetched from S3 using AES256.
     * @param encryptedBlob The encrypted blob data.
     * @param s3KeyStr The S3 key used to locate the archive record for the encryption key.
     * @return The decrypted content as a string.
     */
    private static String decryptFromS3(Blob encryptedBlob, String s3KeyStr) {

        String archiveIdStr = extractArchiveIdFromKey(s3KeyStr);

        if (String.isBlank(archiveIdStr)) {
            throw new AuraHandledException('Cannot determine archive record from S3 key: ' + s3KeyStr);
        }

        List<Data_Archive__c> archivesList = [
            SELECT Encryption_Key__c
            FROM Data_Archive__c
            WHERE Id = :archiveIdStr
            LIMIT 1
        ];

        if (archivesList.isEmpty() || String.isBlank(archivesList[0].Encryption_Key__c)) {
            throw new AuraHandledException('Encryption key not found for archive: ' + archiveIdStr);
        }

        Blob aesKeyBlob = EncodingUtil.base64Decode(archivesList[0].Encryption_Key__c);
        Blob decryptedBlob = Crypto.decryptWithManagedIV('AES256', aesKeyBlob, encryptedBlob);

        if (s3KeyStr != null && s3KeyStr.toLowerCase().contains('.zip.enc')) {
            Compression.ZipReader zipReader = new Compression.ZipReader(decryptedBlob);
            List<Compression.ZipEntry> entriesList = zipReader.getEntries();

            if (!entriesList.isEmpty()) {
                Blob csvBlob = zipReader.extract(entriesList[0]);
                return csvBlob.toString();
            }
        }

        return decryptedBlob.toString();
    }

    /**
     * @description Extracts the Data_Archive__c record ID from an S3 key.
     * @param s3KeyStr The S3 key following the pattern: archiveRecordId/filename.csv.
     * @return The archive record ID string, or null if not found.
     */
    @TestVisible
    private static String extractArchiveIdFromKey(String s3KeyStr) {

        if (String.isBlank(s3KeyStr) || !s3KeyStr.contains('/')) {
            return null;
        }

        return s3KeyStr.substringBefore('/');
    }

    /**
     * @description URL-encodes an S3 key while preserving forward slashes.
     * @param keyStr The S3 key to encode.
     * @return The URL-encoded key with slashes preserved.
     */
    private static String encodeS3KeyPreserveSlashes(String keyStr) {

        if (keyStr == null) return null;

        List<String> partsList = keyStr.split('/');
        List<String> encodedPartsList = new List<String>();

        for (String partStr : partsList) {
            String encodedStr = EncodingUtil.urlEncode(partStr, 'UTF-8');
            encodedStr = encodedStr.replace('+', '%20');
            encodedPartsList.add(encodedStr);
        }

        return String.join(encodedPartsList, '/');
    }
}