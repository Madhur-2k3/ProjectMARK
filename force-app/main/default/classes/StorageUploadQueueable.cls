/**
 * Provider-agnostic replacement for S3UploadQueueable.
 * Uploads ContentDocumentLink attachments to the configured storage provider
 * when files are attached directly to a Data_Archive__c record.
 */
public class StorageUploadQueueable implements Queueable, Database.AllowsCallouts {

    private List<String> docPairs;          // "ContentDocumentId|DataArchiveId"
    private String storageProviderName;     // Storage_Provider__mdt DeveloperName (nullable → default)

    public StorageUploadQueueable(List<String> docPairs, String storageProviderName) {
        this.docPairs            = docPairs == null ? new List<String>() : docPairs;
        this.storageProviderName = storageProviderName;
    }

    // Backward-compatible: uses default provider
    public StorageUploadQueueable(List<String> docPairs) {
        this(docPairs, null);
    }

    public void execute(QueueableContext context) {
        if (docPairs.isEmpty()) return;

        // Resolve provider — fail gracefully per Q3 (block with error, not silent fallback)
        IExternalStorageProvider provider;
        try {
            provider = String.isNotBlank(storageProviderName)
                ? StorageProviderFactory.getProvider(storageProviderName)
                : StorageProviderFactory.getDefaultProvider();
        } catch (StorageProviderException e) {
            System.debug('StorageUploadQueueable: No storage provider available — upload blocked. ' + e.getMessage());
            return;
        }

        // Parse docPairs → Map<ContentDocumentId, DataArchiveId>
        Map<Id, Id> docToParent = new Map<Id, Id>();
        Set<Id> docIds = new Set<Id>();
        for (String p : docPairs) {
            if (String.isBlank(p)) continue;
            Integer sep = p.indexOf('|');
            if (sep > 0 && sep < p.length() - 1) {
                try {
                    Id docId    = (Id) p.substring(0, sep);
                    Id parentId = (Id) p.substring(sep + 1);
                    docToParent.put(docId, parentId);
                    docIds.add(docId);
                } catch (Exception ex) {
                    System.debug('StorageUploadQueueable: could not parse pair: ' + p + ' — ' + ex.getMessage());
                }
            }
        }
        if (docIds.isEmpty()) return;

        List<ContentVersion> cvs = [
            SELECT Id, ContentDocumentId, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
        ];

        for (ContentVersion cv : cvs) {
            try {
                Id parentId = docToParent.get(cv.ContentDocumentId);
                if (parentId == null) continue;
                String fileName = String.valueOf(parentId) + '/' + cv.Title;
                if (String.isNotBlank(cv.FileExtension)) {
                    fileName += '.' + cv.FileExtension;
                }
                String base64Body = cv.VersionData != null
                    ? EncodingUtil.base64Encode(cv.VersionData) : '';
                String resp = provider.putObject(fileName, base64Body, 'application/octet-stream');
                System.debug('StorageUploadQueueable: uploaded ' + fileName + ' → ' + resp);
            } catch (Exception ex) {
                System.debug('StorageUploadQueueable: upload failed for CV ' + cv.Id + ': ' + ex.getMessage());
            }
        }
    }
}
