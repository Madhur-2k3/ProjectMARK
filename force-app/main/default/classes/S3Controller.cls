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