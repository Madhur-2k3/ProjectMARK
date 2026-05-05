/**
 * GoogleDriveStorageProvider — IExternalStorageProvider implementation for Google Drive API v3.
 *
 * Upload strategy: 2-step (create metadata → PATCH content) to avoid Apex blob-concat limitations.
 * Folder structure: rootFolder (Base_Path__c) / archiveRecordId / filename
 *
 * Named Credential URL must be: https://www.googleapis.com
 */
public class GoogleDriveStorageProvider implements IExternalStorageProvider {

    private final String namedCredential;
    private final String rootFolderId;

    private static final String FOLDER_MIME = 'application/vnd.google-apps.folder';
    private static final String DRIVE_BASE  = '/drive/v3';

    public GoogleDriveStorageProvider(String namedCredential, String rootFolderId) {
        if (String.isBlank(namedCredential)) {
            throw new StorageProviderException('GoogleDriveStorageProvider: namedCredential is required.');
        }
        if (String.isBlank(rootFolderId)) {
            throw new StorageProviderException('GoogleDriveStorageProvider: rootFolderId (Base_Path__c) is required.');
        }
        this.namedCredential = namedCredential;
        this.rootFolderId    = rootFolderId;
    }

    public String getProviderType() { return 'Google_Drive'; }

    // ── PUT ──────────────────────────────────────────────────────────────────
    // 2-step: (1) POST metadata → get fileId, (2) PATCH binary content
    public String putObject(String filePath, String base64Body, String contentType) {
        String folderName = filePath.contains('/') ? filePath.substringBefore('/') : filePath;
        String fileName   = filePath.contains('/') ? filePath.substringAfterLast('/') : filePath;

        // Step 1 — find or create archive subfolder
        String archiveFolderId = findOrCreateFolder(folderName, rootFolderId);

        // Step 2 — create file metadata (no content yet)
        String metaJson = JSON.serialize(new Map<String, Object>{
            'name'    => fileName,
            'parents' => new List<String>{ archiveFolderId }
        });
        HttpRequest createReq = buildJsonRequest('POST', DRIVE_BASE + '/files?fields=id', metaJson);
        Map<String, Object> createResp = (Map<String, Object>) JSON.deserializeUntyped(send(createReq).getBody());
        String fileId = (String) createResp.get('id');

        // Step 3 — PATCH binary content
        Blob fileBlob = (base64Body != null && base64Body.trim().length() > 0)
            ? EncodingUtil.base64Decode(base64Body) : Blob.valueOf('');
        HttpRequest uploadReq = new HttpRequest();
        uploadReq.setMethod('PATCH');
        uploadReq.setEndpoint('callout:' + namedCredential + '/upload' + DRIVE_BASE
            + '/files/' + fileId + '?uploadType=media&fields=id');
        uploadReq.setHeader('Content-Type',
            String.isBlank(contentType) ? 'application/octet-stream' : contentType);
        uploadReq.setBodyAsBlob(fileBlob);
        Map<String, Object> uploadResp = (Map<String, Object>) JSON.deserializeUntyped(send(uploadReq).getBody());
        return 'OK - Google Drive file ID: ' + uploadResp.get('id');
    }

    // ── GET raw ──────────────────────────────────────────────────────────────
    public String getObject(String filePath) {
        String fileId = resolveFileId(filePath);
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + namedCredential + DRIVE_BASE + '/files/' + fileId + '?alt=media');
        HttpResponse res = send(req);
        if (filePath != null && filePath.endsWith('.enc')) {
            return decryptBlob(res.getBodyAsBlob(), filePath);
        }
        return res.getBody();
    }

    // ── GET base64 ───────────────────────────────────────────────────────────
    public String getObjectAsBase64(String filePath) {
        String fileId = resolveFileId(filePath);
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + namedCredential + DRIVE_BASE + '/files/' + fileId + '?alt=media');
        HttpResponse res = send(req);
        Blob raw = res.getBodyAsBlob();
        if (filePath != null && filePath.endsWith('.enc')) {
            String decrypted = decryptBlob(raw, filePath);
            return EncodingUtil.base64Encode(Blob.valueOf(decrypted));
        }
        return EncodingUtil.base64Encode(raw);
    }

    // ── LIST all ─────────────────────────────────────────────────────────────
    public String listObjects() {
        return listFilesInFolder(rootFolderId, null);
    }

    // ── LIST by prefix ───────────────────────────────────────────────────────
    public String listObjectsByPrefix(String prefix) {
        String subFolderId = findFolder(prefix, rootFolderId);
        if (String.isBlank(subFolderId)) return JSON.serialize(new List<Object>());
        return listFilesInFolder(subFolderId, prefix);
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private String findFolder(String name, String parentId) {
        String q = 'mimeType=\'' + FOLDER_MIME + '\' and name=\''
            + escapeDq(name) + '\' and \'' + parentId + '\' in parents and trashed=false';
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + namedCredential + DRIVE_BASE
            + '/files?q=' + EncodingUtil.urlEncode(q, 'UTF-8') + '&fields=files(id)');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(send(req).getBody());
        List<Object> files = (List<Object>) body.get('files');
        if (files != null && !files.isEmpty()) {
            return (String) ((Map<String, Object>) files[0]).get('id');
        }
        return null;
    }

    private String findOrCreateFolder(String name, String parentId) {
        String existing = findFolder(name, parentId);
        if (existing != null) return existing;
        String body = JSON.serialize(new Map<String, Object>{
            'name' => name, 'mimeType' => FOLDER_MIME, 'parents' => new List<String>{ parentId }
        });
        Map<String, Object> resp = (Map<String, Object>)
            JSON.deserializeUntyped(send(buildJsonRequest('POST', DRIVE_BASE + '/files?fields=id', body)).getBody());
        return (String) resp.get('id');
    }

    private String resolveFileId(String filePath) {
        String folderName = filePath.contains('/') ? filePath.substringBefore('/') : null;
        String fileName   = filePath.contains('/') ? filePath.substringAfterLast('/') : filePath;
        String parentId   = rootFolderId;
        if (String.isNotBlank(folderName)) {
            parentId = findFolder(folderName, rootFolderId);
            if (String.isBlank(parentId)) throw new StorageProviderException('Folder not found: ' + folderName);
        }
        String q = 'name=\'' + escapeDq(fileName) + '\' and \'' + parentId + '\' in parents and trashed=false';
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + namedCredential + DRIVE_BASE
            + '/files?q=' + EncodingUtil.urlEncode(q, 'UTF-8') + '&fields=files(id)');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(send(req).getBody());
        List<Object> files = (List<Object>) body.get('files');
        if (files == null || files.isEmpty()) throw new StorageProviderException('File not found: ' + filePath);
        return (String) ((Map<String, Object>) files[0]).get('id');
    }

    private String listFilesInFolder(String folderId, String prefix) {
        String q = '\'' + folderId + '\' in parents and mimeType!=\'' + FOLDER_MIME + '\' and trashed=false';
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + namedCredential + DRIVE_BASE
            + '/files?q=' + EncodingUtil.urlEncode(q, 'UTF-8')
            + '&fields=files(id,name,size,modifiedTime)');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(send(req).getBody());
        List<Object> files = (List<Object>) body.get('files');
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        if (files != null) {
            for (Object f : files) {
                Map<String, Object> file = (Map<String, Object>) f;
                items.add(new Map<String, Object>{
                    'Key'          => (prefix != null ? prefix + '/' : '') + file.get('name'),
                    'Size'         => file.get('size'),
                    'LastModified' => file.get('modifiedTime'),
                    'driveFileId'  => file.get('id')
                });
            }
        }
        return JSON.serialize(items);
    }

    private String decryptBlob(Blob encryptedBlob, String filePath) {
        String archiveId = filePath.contains('/') ? filePath.substringBefore('/') : null;
        if (String.isBlank(archiveId)) throw new StorageProviderException('Cannot determine archiveId from: ' + filePath);
        List<Data_Archive__c> archives = [SELECT Encryption_Key__c FROM Data_Archive__c WHERE Id = :archiveId LIMIT 1];
        if (archives.isEmpty() || String.isBlank(archives[0].Encryption_Key__c)) {
            throw new StorageProviderException('Encryption key not found for archive: ' + archiveId);
        }
        Blob aesKey = EncodingUtil.base64Decode(archives[0].Encryption_Key__c);
        Blob decrypted = Crypto.decryptWithManagedIV('AES256', aesKey, encryptedBlob);
        if (filePath.toLowerCase().contains('.zip.enc')) {
            Compression.ZipReader zr = new Compression.ZipReader(decrypted);
            List<Compression.ZipEntry> entries = zr.getEntries();
            if (!entries.isEmpty()) return zr.extract(entries[0]).toString();
        }
        return decrypted.toString();
    }

    private HttpRequest buildJsonRequest(String method, String path, String body) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint('callout:' + namedCredential + path);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);
        return req;
    }

    private HttpResponse send(HttpRequest req) {
        HttpResponse res;
        try { res = new Http().send(req); } catch (Exception e) {
            throw new StorageProviderException('GoogleDriveStorageProvider callout error: ' + e.getMessage());
        }
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new StorageProviderException(
                'Google Drive API error: ' + res.getStatusCode() + ' body=' + res.getBody());
        }
        return res;
    }

    private static String escapeDq(String val) {
        if (val == null) return '';
        return val.replace('\\', '\\\\').replace('\'', '\\\'');
    }
}
