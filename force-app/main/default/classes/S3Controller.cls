public with sharing class S3Controller {
    //get data from s3
    @AuraEnabled(cacheable=false)
    public static String getDataFromS3(String fileName) {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        String endpoint = 'callout:aws_s3';
        if (fileName != null && fileName.trim().length() > 0) {
            if (!endpoint.endsWith('/')) endpoint += '/';
            endpoint += encodeS3KeyPreserveSlashes(fileName);
        }
        request.setEndpoint(endpoint);
        request.setHeader('Accept', '*/*');

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(request);
        } catch (Exception e) {
            String err = 's3Controller.getDataFromS3 exception: ' + e.getMessage() + '\n' + e.getStackTraceString();
            throw new AuraHandledException(err);
        }

        if (res == null) {
            throw new AuraHandledException('s3Controller.getDataFromS3 error: Empty HttpResponse');
        }

        Integer status = res.getStatusCode();
        if (status == 200) {
            return res.getBody();
        } else {
            String body = '';
            try { body = res.getBody(); } catch (Exception e) { body = '<could not read response body>'; }
            String err = 'Error fetching data from S3: status=' + status + ' statusText=' + res.getStatus() + ' body=' + body;
            throw new AuraHandledException(err);
        }
    }

    @AuraEnabled(cacheable=false)
    public static String getDataFromS3AsBase64(String fileName) {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        String endpoint = 'callout:aws_s3';
        if (fileName != null && fileName.trim().length() > 0) {
            if (!endpoint.endsWith('/')) endpoint += '/';
            endpoint += encodeS3KeyPreserveSlashes(fileName);
        }
        request.setEndpoint(endpoint);
        request.setHeader('Accept', '*/*');

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(request);
        } catch (Exception e) {
            String err = 's3Controller.getDataFromS3AsBase64 exception: ' + e.getMessage() + '\n' + e.getStackTraceString();
            throw new AuraHandledException(err);
        }

        if (res == null) {
            throw new AuraHandledException('s3Controller.getDataFromS3AsBase64 error: Empty HttpResponse');
        }

        Integer status = res.getStatusCode();
        if (status == 200) {
            Blob bodyBlob = res.getBodyAsBlob();
            return EncodingUtil.base64Encode(bodyBlob);
        } else {
            String body = '';
            try { body = res.getBody(); } catch (Exception e) { body = '<could not read response body>'; }
            String err = 'Error fetching data from S3: status=' + status + ' statusText=' + res.getStatus() + ' body=' + body;
            throw new AuraHandledException(err);
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static String listObjectsFromS3() {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            // Use S3 ListObjectsV2 via query param. Named credential should point to the bucket root.
            String endpoint = 'callout:aws_s3?list-type=2';
            request.setEndpoint(endpoint);
            Http http = new Http();
            HttpResponse res = http.send(request);
            if (res.getStatusCode() == 200) {
                String body = res.getBody();
                // S3 returns XML for ListObjectsV2. Parse and convert to JSON list of objects.
                Dom.Document doc = new Dom.Document();
                doc.load(body);
                Dom.XmlNode root = doc.getRootElement();
                List<Map<String, Object>> items = new List<Map<String, Object>>();
                for (Dom.XmlNode child : root.getChildElements()) {
                    if (child.getName() == 'Contents') {
                        Map<String, Object> mapItem = new Map<String, Object>();
                        for (Dom.XmlNode contentChild : child.getChildElements()) {
                            mapItem.put(contentChild.getName(), contentChild.getText());
                        }
                        items.add(mapItem);
                    }
                }
                return JSON.serialize(items);
            } else {
                throw new AuraHandledException('Error listing S3 objects: ' + res.getStatusCode() + ' ' + res.getStatus());
            }
        } catch (Exception e) {
            throw new AuraHandledException('s3Controller.listObjectsFromS3 error: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String putObjectToS3(String fileName, String base64Body, String contentType) {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('PUT');
            String endpoint = 'callout:aws_s3';
            if (fileName != null && fileName.trim().length() > 0) {
                if (!endpoint.endsWith('/')) endpoint += '/';
                endpoint += encodeS3KeyPreserveSlashes(fileName);
            }
            request.setEndpoint(endpoint);
            if (contentType != null) {
                request.setHeader('Content-Type', contentType);
            }
            if (base64Body != null && base64Body.trim().length() > 0) {
                Blob bodyBlob = EncodingUtil.base64Decode(base64Body);
                request.setBodyAsBlob(bodyBlob);
            } else {
                request.setBody('');
            }
            Http http = new Http();
            HttpResponse res = http.send(request);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return res.getStatus() + ' (' + res.getStatusCode() + ')';
            } else {
                String responseBody = '';
                try { responseBody = res.getBody(); } catch (Exception bodyEx) { responseBody = '<could not read response body>'; }
                System.debug('S3Controller.putObjectToS3 error response: ' + res.getStatusCode() + ' ' + res.getStatus() + ' body: ' + responseBody);
                throw new S3ControllerException('Error uploading to S3: ' + res.getStatusCode() + ' ' + res.getStatus() + ' body=' + responseBody);
            }
        } catch (Exception e) {
            throw new S3ControllerException('s3Controller.putObjectToS3 error: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String listObjectsByPrefix(String prefix) {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            String encodedPrefix = EncodingUtil.urlEncode(prefix, 'UTF-8').replace('+', '%20');
            String endpoint = 'callout:aws_s3?list-type=2&prefix=' + encodedPrefix + '/';
            request.setEndpoint(endpoint);
            Http http = new Http();
            HttpResponse res = http.send(request);
            if (res.getStatusCode() == 200) {
                String body = res.getBody();
                Dom.Document doc = new Dom.Document();
                doc.load(body);
                Dom.XmlNode root = doc.getRootElement();
                List<Map<String, Object>> items = new List<Map<String, Object>>();
                for (Dom.XmlNode child : root.getChildElements()) {
                    if (child.getName() == 'Contents') {
                        Map<String, Object> mapItem = new Map<String, Object>();
                        for (Dom.XmlNode contentChild : child.getChildElements()) {
                            mapItem.put(contentChild.getName(), contentChild.getText());
                        }
                        // Skip the folder entry itself
                        String key = (String) mapItem.get('Key');
                        if (key != null && key != prefix + '/') {
                            items.add(mapItem);
                        }
                    }
                }
                return JSON.serialize(items);
            } else {
                throw new AuraHandledException('Error listing S3 objects by prefix: ' + res.getStatusCode() + ' ' + res.getStatus());
            }
        } catch (Exception e) {
            throw new AuraHandledException('s3Controller.listObjectsByPrefix error: ' + e.getMessage());
        }
    }

    /**
     * Fetches CSV from S3 and filters columns based on the running user's
     * Field-Level Security (FLS).  The object name is extracted from the
     * S3 key (e.g. "DA-00001-Account.csv" → "Account").
     *
     * If the object cannot be resolved, the full CSV is returned unfiltered.
     */
    @AuraEnabled(cacheable=false)
    public static String getFilteredCsvFromS3(String fileName) {
        // 1. Fetch raw CSV from S3
        String rawCsv = getDataFromS3(fileName);

        if (String.isBlank(rawCsv)) {
            return rawCsv;
        }

        // 2. Extract the object name from the file key
        String objectName = extractObjectNameFromKey(fileName);
        if (String.isBlank(objectName)) {
            // Cannot determine object – return full CSV
            return rawCsv;
        }

        // 3. Look up the SObject type
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) {
            // Unknown object – return full CSV
            return rawCsv;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        // 4. Parse the header row
        List<String> lines = rawCsv.split('\n');
        if (lines.isEmpty()) {
            return rawCsv;
        }

        List<String> headers = parseCsvLine(lines[0]);

        // 5. Determine which column indices the user can see
        List<Integer> accessibleIndices = new List<Integer>();
        List<String>  accessibleHeaders = new List<String>();

        for (Integer i = 0; i < headers.size(); i++) {
            String fieldName = headers[i].trim();

            // Handle relationship fields (e.g. Owner.Name)
            String baseField = fieldName.contains('.')
                ? fieldName.substringBefore('.')
                : fieldName;

            Schema.SObjectField sField = fieldMap.get(baseField.toLowerCase());

            if (sField != null && sField.getDescribe().isAccessible()) {
                accessibleIndices.add(i);
                accessibleHeaders.add(fieldName);
            } else if (sField == null) {
                // Field not found in schema – include it
                // (could be a formula alias, relationship, etc.)
                accessibleIndices.add(i);
                accessibleHeaders.add(fieldName);
            }
            // else: field exists but user has no FLS access → skip
        }

        // If all columns are accessible, return as-is
        if (accessibleIndices.size() == headers.size()) {
            return rawCsv;
        }

        // 6. Rebuild CSV with only accessible columns
        List<String> filteredLines = new List<String>();
        filteredLines.add(String.join(accessibleHeaders, ','));

        for (Integer lineIdx = 1; lineIdx < lines.size(); lineIdx++) {
            String line = lines[lineIdx];
            if (String.isBlank(line)) continue;

            List<String> cells = parseCsvLine(line);
            List<String> filteredCells = new List<String>();

            for (Integer idx : accessibleIndices) {
                if (idx < cells.size()) {
                    filteredCells.add(escapeCsvField(cells[idx]));
                } else {
                    filteredCells.add('');
                }
            }
            filteredLines.add(String.join(filteredCells, ','));
        }

        return String.join(filteredLines, '\n');
    }

    /**
     * Returns field metadata (apiName, label, type) for CSV column headers.
     * The type values match filterBuilder's operatorMap keys:
     * STRING, DATE, DATETIME, DOUBLE, INTEGER, CURRENCY, BOOLEAN, PICKLIST
     */
    @AuraEnabled
    public static List<Map<String, String>> getCsvFieldMetadata(String objectName, List<String> fieldNames) {
        List<Map<String, String>> result = new List<Map<String, String>>();

        if (String.isBlank(objectName) || fieldNames == null || fieldNames.isEmpty()) {
            return result;
        }

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) {
            // Unknown object — return all fields as STRING type
            for (String fn : fieldNames) {
                Map<String, String> fm = new Map<String, String>();
                fm.put('apiName', fn);
                fm.put('label', fn);
                fm.put('type', 'STRING');
                result.add(fm);
            }
            return result;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String fn : fieldNames) {
            Map<String, String> fm = new Map<String, String>();
            String trimmed = fn.trim();
            fm.put('apiName', trimmed);

            // Handle relationship fields (e.g., Owner.Name)
            String lookupField = trimmed.contains('.')
                ? trimmed.substringBefore('.')
                : trimmed;

            Schema.SObjectField sField = fieldMap.get(lookupField.toLowerCase());

            if (sField != null) {
                Schema.DescribeFieldResult dfr = sField.getDescribe();
                fm.put('label', dfr.getLabel());
                fm.put('type', mapFieldType(dfr.getType()));
            } else {
                fm.put('label', trimmed);
                fm.put('type', 'STRING');
            }
            result.add(fm);
        }

        return result;
    }

    /**
     * Maps Salesforce DisplayType to filterBuilder operator-map keys.
     */
    private static String mapFieldType(Schema.DisplayType dt) {
        switch on dt {
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
     * Extracts the SObject API name from an S3 key.
     *
     * S3 keys are built by ArchivePostProcessQueueable as:
     *   {recordId}/{Title}_{Description}.{ext}
     *
     * Where:
     *   Title       = object API name  (e.g. "Booking__c", "Account")
     *   Description = "ObjectName - DA-XXXX"  (spaces → underscores)
     *
     * Examples:
     *   "recId/Booking__c_Booking__c_-_DA-0359.csv"  → "Booking__c"
     *   "recId/Account_Account_-_DA-0001.csv"         → "Account"
     *   "recId/Account_Account_-_DA-0001_Part_2.csv"  → "Account"
     */
    @TestVisible
    private static String extractObjectNameFromKey(String key) {
        if (String.isBlank(key)) return null;

        // Get just the file name (after last slash)
        String fName = key.contains('/') ? key.substringAfterLast('/') : key;

        // Remove extension
        if (fName.contains('.')) {
            fName = fName.substringBeforeLast('.');
        }

        // The file name starts with the Title (object name).
        // Title is followed by '_' + Description.
        // For standard objects like "Account", the file looks like:
        //   Account_Account_-_DA-0001
        // For custom objects like "Booking__c", the file looks like:
        //   Booking__c_Booking__c_-_DA-0359
        //
        // Strategy: Try to match a valid SObject from Schema.
        // First attempt: check if the full fName or prefix is a valid SObject.

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        // Custom objects end with __c, __mdt, __e, etc.
        // Try to find the longest prefix that matches a valid SObject.
        // Look for the pattern: the object name repeats as "{Title}_{Title}_-_DA-"
        // So we can look for "_-_DA-" as a delimiter.

        Integer daIdx = fName.indexOf('_-_DA-');
        if (daIdx > 0) {
            // Everything before "_-_DA-" is "{Title}_{ObjectName}"
            // which is "{ObjectName}_{ObjectName}"
            String beforeDA = fName.substring(0, daIdx);

            // The Title (object name) is the first half.
            // For "Booking__c_Booking__c", split by trying known objects.
            // Simple approach: the description starts with the object name,
            // so {Title}_{Title} means the first half is the object name.
            // But we can also just check against Schema.

            // Try the full string first
            if (globalDescribe.containsKey(beforeDA)) {
                return beforeDA;
            }

            // For "{ObjectName}_{ObjectName}", the object name appears at the start.
            // Try progressively shorter prefixes that match a valid SObject.
            // Custom objects: look for __c, __mdt, __e, __b, __x patterns
            for (String suffix : new List<String>{'__c', '__mdt', '__e', '__b', '__x'}) {
                Integer suffixIdx = beforeDA.indexOf(suffix);
                if (suffixIdx > 0) {
                    String candidate = beforeDA.substring(0, suffixIdx + suffix.length());
                    if (globalDescribe.containsKey(candidate)) {
                        return candidate;
                    }
                }
            }

            // Standard objects: try splitting on '_' and checking each prefix
            List<String> segments = beforeDA.split('_');
            if (segments.size() > 0 && globalDescribe.containsKey(segments[0])) {
                return segments[0];
            }
        }

        // Fallback: try the whole filename against global describe
        if (globalDescribe.containsKey(fName)) {
            return fName;
        }

        return null;
    }

    /**
     * Parses a single CSV line, handling quoted fields that contain commas.
     */
    private static List<String> parseCsvLine(String line) {
        List<String> fields = new List<String>();
        if (String.isBlank(line)) return fields;

        String current = '';
        Boolean inQuotes = false;

        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);

            if (inQuotes) {
                if (ch == '"') {
                    // Check for escaped quote ("")
                    if (i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                        current += '"';
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    current += ch;
                }
            } else {
                if (ch == '"') {
                    inQuotes = true;
                } else if (ch == ',') {
                    fields.add(current.trim());
                    current = '';
                } else if (ch == '\r') {
                    // skip carriage return
                    continue;
                } else {
                    current += ch;
                }
            }
        }
        fields.add(current.trim());
        return fields;
    }

    /**
     * Re-escapes a CSV field value if it contains commas, quotes, or newlines.
     */
    private static String escapeCsvField(String value) {
        if (String.isBlank(value)) return value;

        Boolean needsQuoting = value.contains(',') || value.contains('"') || value.contains('\n');
        if (needsQuoting) {
            return '"' + value.replace('"', '""') + '"';
        }
        return value;
    }

    private static String encodeS3KeyPreserveSlashes(String key) {
        if (key == null) return null;
        List<String> parts = key.split('/');
        List<String> encodedParts = new List<String>();
        for (String part : parts) {
            String encoded = EncodingUtil.urlEncode(part, 'UTF-8');
            encoded = encoded.replace('+', '%20');
            encodedParts.add(encoded);
        }
        return String.join(encodedParts, '/');
    }
}