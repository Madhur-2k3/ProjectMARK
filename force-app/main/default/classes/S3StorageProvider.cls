/**
 * S3 implementation of IExternalStorageProvider.
 * Refactored from S3Controller — all S3-specific logic lives here.
 * The Named Credential name and optional base path are injected via constructor.
 */
public class S3StorageProvider implements IExternalStorageProvider {

    private final String namedCredential;
    private final String basePath; // optional prefix folder

    public S3StorageProvider(String namedCredential, String basePath) {
        if (String.isBlank(namedCredential)) {
            throw new StorageProviderException('S3StorageProvider: namedCredential is required.');
        }
        this.namedCredential = namedCredential;
        this.basePath = basePath;
    }

    public String getProviderType() {
        return 'S3';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PUT
    // ─────────────────────────────────────────────────────────────────────────
    public String putObject(String filePath, String base64Body, String contentType) {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('PUT');
            String endpoint = buildEndpoint(filePath);
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
                throw new StorageProviderException(
                    'Error uploading to S3: ' + res.getStatusCode() + ' ' + res.getStatus() + ' body=' + responseBody
                );
            }
        } catch (StorageProviderException spe) {
            throw spe;
        } catch (Exception e) {
            throw new StorageProviderException('S3StorageProvider.putObject error: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET (raw)
    // ─────────────────────────────────────────────────────────────────────────
    public String getObject(String filePath) {
        HttpResponse res = doGet(filePath);
        if (filePath != null && filePath.endsWith('.enc')) {
            Blob bodyBlob = res.getBodyAsBlob();
            return decryptFromS3(bodyBlob, filePath);
        }
        return res.getBody();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET (base64)
    // ─────────────────────────────────────────────────────────────────────────
    public String getObjectAsBase64(String filePath) {
        HttpResponse res = doGet(filePath);
        Blob bodyBlob = res.getBodyAsBlob();
        if (filePath != null && filePath.endsWith('.enc')) {
            String decrypted = decryptFromS3(bodyBlob, filePath);
            return EncodingUtil.base64Encode(Blob.valueOf(decrypted));
        }
        return EncodingUtil.base64Encode(bodyBlob);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LIST all
    // ─────────────────────────────────────────────────────────────────────────
    public String listObjects() {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            String endpoint = 'callout:' + namedCredential + '?list-type=2';
            request.setEndpoint(endpoint);
            Http http = new Http();
            HttpResponse res = http.send(request);
            if (res.getStatusCode() == 200) {
                return parseS3ListXml(res.getBody(), null);
            } else {
                throw new StorageProviderException(
                    'Error listing S3 objects: ' + res.getStatusCode() + ' ' + res.getStatus()
                );
            }
        } catch (StorageProviderException spe) {
            throw spe;
        } catch (Exception e) {
            throw new StorageProviderException('S3StorageProvider.listObjects error: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LIST by prefix
    // ─────────────────────────────────────────────────────────────────────────
    public String listObjectsByPrefix(String prefix) {
        try {
            String encodedPrefix = EncodingUtil.urlEncode(prefix, 'UTF-8').replace('+', '%20');
            String endpoint = 'callout:' + namedCredential + '?list-type=2&prefix=' + encodedPrefix + '/';
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setEndpoint(endpoint);
            Http http = new Http();
            HttpResponse res = http.send(request);
            if (res.getStatusCode() == 200) {
                return parseS3ListXml(res.getBody(), prefix);
            } else {
                throw new StorageProviderException(
                    'Error listing S3 objects by prefix: ' + res.getStatusCode() + ' ' + res.getStatus()
                );
            }
        } catch (StorageProviderException spe) {
            throw spe;
        } catch (Exception e) {
            throw new StorageProviderException('S3StorageProvider.listObjectsByPrefix error: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private HttpResponse doGet(String filePath) {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(buildEndpoint(filePath));
        request.setHeader('Accept', '*/*');
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(request);
        } catch (Exception e) {
            throw new StorageProviderException('S3StorageProvider.getObject callout error: ' + e.getMessage());
        }
        if (res == null) {
            throw new StorageProviderException('S3StorageProvider.getObject: Empty HttpResponse');
        }
        Integer status = res.getStatusCode();
        if (status != 200) {
            String body = '';
            try { body = res.getBody(); } catch (Exception e) { body = '<could not read response body>'; }
            throw new StorageProviderException('Error fetching from S3: status=' + status + ' body=' + body);
        }
        return res;
    }

    private String buildEndpoint(String filePath) {
        String endpoint = 'callout:' + namedCredential;
        if (String.isNotBlank(basePath)) {
            endpoint += '/' + encodeKeyPreserveSlashes(basePath);
        }
        if (String.isNotBlank(filePath)) {
            if (!endpoint.endsWith('/')) endpoint += '/';
            endpoint += encodeKeyPreserveSlashes(filePath);
        }
        return endpoint;
    }

    private String parseS3ListXml(String xmlBody, String skipPrefix) {
        Dom.Document doc = new Dom.Document();
        doc.load(xmlBody);
        Dom.XmlNode root = doc.getRootElement();
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        for (Dom.XmlNode child : root.getChildElements()) {
            if (child.getName() == 'Contents') {
                Map<String, Object> mapItem = new Map<String, Object>();
                for (Dom.XmlNode contentChild : child.getChildElements()) {
                    mapItem.put(contentChild.getName(), contentChild.getText());
                }
                String key = (String) mapItem.get('Key');
                // Skip the folder-level entry itself
                if (skipPrefix != null && key == skipPrefix + '/') continue;
                items.add(mapItem);
            }
        }
        return JSON.serialize(items);
    }

    private String decryptFromS3(Blob encryptedBlob, String s3Key) {
        String archiveId = extractArchiveIdFromKey(s3Key);
        if (String.isBlank(archiveId)) {
            throw new StorageProviderException('Cannot determine archive record from key: ' + s3Key);
        }
        List<Data_Archive__c> archives = [
            SELECT Encryption_Key__c FROM Data_Archive__c WHERE Id = :archiveId LIMIT 1
        ];
        if (archives.isEmpty() || String.isBlank(archives[0].Encryption_Key__c)) {
            throw new StorageProviderException('Encryption key not found for archive: ' + archiveId);
        }
        Blob aesKey = EncodingUtil.base64Decode(archives[0].Encryption_Key__c);
        Blob decrypted = Crypto.decryptWithManagedIV('AES256', aesKey, encryptedBlob);
        if (s3Key != null && s3Key.toLowerCase().contains('.zip.enc')) {
            Compression.ZipReader zr = new Compression.ZipReader(decrypted);
            List<Compression.ZipEntry> entries = zr.getEntries();
            if (!entries.isEmpty()) {
                Blob csvBlob = zr.extract(entries[0]);
                return csvBlob.toString();
            }
        }
        return decrypted.toString();
    }

    private static String extractArchiveIdFromKey(String key) {
        if (String.isBlank(key) || !key.contains('/')) return null;
        return key.substringBefore('/');
    }

    private static String encodeKeyPreserveSlashes(String key) {
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
