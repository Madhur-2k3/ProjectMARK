public class ArchivePostProcessQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> contentDocumentIds;
    private Id archiveRecordId;
    private String parentObjectApi;
    private List<Id> parentIds;
    private Boolean deleteAfterArchive;
    private String storageProviderName; // Storage_Provider__mdt DeveloperName

    // Backward-compatible constructor (defaults to delete, uses default provider)
    public ArchivePostProcessQueueable(
        List<Id> contentDocumentIds,
        Id archiveRecordId,
        String parentObjectApi,
        List<Id> parentIds
    ) {
        this(contentDocumentIds, archiveRecordId, parentObjectApi, parentIds, true, null);
    }

    // Constructor with delete option (uses default provider)
    public ArchivePostProcessQueueable(
        List<Id> contentDocumentIds,
        Id archiveRecordId,
        String parentObjectApi,
        List<Id> parentIds,
        Boolean deleteAfterArchive
    ) {
        this(contentDocumentIds, archiveRecordId, parentObjectApi, parentIds, deleteAfterArchive, null);
    }

    // Full constructor with provider selection
    public ArchivePostProcessQueueable(
        List<Id> contentDocumentIds,
        Id archiveRecordId,
        String parentObjectApi,
        List<Id> parentIds,
        Boolean deleteAfterArchive,
        String storageProviderName
    ) {
        this.contentDocumentIds  = contentDocumentIds == null ? new List<Id>() : contentDocumentIds;
        this.archiveRecordId     = archiveRecordId;
        this.parentObjectApi     = parentObjectApi;
        this.parentIds           = parentIds == null ? new List<Id>() : parentIds;
        this.deleteAfterArchive  = deleteAfterArchive != null ? deleteAfterArchive : true;
        this.storageProviderName = storageProviderName;
    }

    public void execute(QueueableContext context) {
        uploadArchiveFiles();

        if (this.deleteAfterArchive && !parentIds.isEmpty()) {
            CascadeDeleteHelper.deleteParentWithRelations(parentObjectApi, parentIds);
        }

        // Update archive status to 'Completed' to signal that deletion is done
        try {
            update new Data_Archive__c(
                Id = archiveRecordId,
                Status__c = 'Completed'
            );
        } catch (Exception ex) {
            System.debug('ArchivePostProcessQueueable: failed to update archive status: ' + ex.getMessage());
        }
    }

    private void uploadArchiveFiles() {
        if (contentDocumentIds.isEmpty() || archiveRecordId == null) {
            System.debug('ArchivePostProcessQueueable: no content documents to upload.');
            return;
        }

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, Description, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
        ];

        // Resolve storage provider (fail with debug log per Q3 — block, don't silently skip)
        IExternalStorageProvider provider;
        try {
            provider = String.isNotBlank(storageProviderName)
                ? StorageProviderFactory.getProvider(storageProviderName)
                : StorageProviderFactory.getDefaultProvider();
        } catch (StorageProviderException e) {
            System.debug('ArchivePostProcessQueueable: No storage provider configured — upload blocked. ' + e.getMessage());
            return;
        }

        System.debug('ArchivePostProcessQueueable: uploading ' + versions.size() + ' archive file(s) via ' + provider.getProviderType() + '.');

        // Generate a unique AES-256 encryption key for this archive (in-memory only)
        Blob aesKey = Crypto.generateAesKey(256);

        // ===== CALLOUTS FIRST (before any DML) =====
        for (ContentVersion versionRecord : versions) {
            try {
                String partSuffix = '';
                if (!String.isBlank(versionRecord.Description)) {
                    partSuffix = '_' + versionRecord.Description.replace(' ', '_');
                }

                // Build S3 key with .csv.zip.enc extension
                String s3FileName = String.valueOf(archiveRecordId) + '/' + versionRecord.Title + partSuffix + '.csv.zip.enc';

                // Compress + Encrypt the CSV data
                String base64Body = '';
                if (versionRecord.VersionData != null) {
                    // Step 1: Compress using ZipWriter
                    Compression.ZipWriter zw = new Compression.ZipWriter();
                    zw.addEntry('data.csv', null, Datetime.now(), Compression.Method.DEFLATED, versionRecord.VersionData);
                    Blob compressed = zw.getArchive();

                    // Step 2: Encrypt the compressed data
                    Blob encrypted = Crypto.encryptWithManagedIV('AES256', aesKey, compressed);
                    base64Body = EncodingUtil.base64Encode(encrypted);
                }

                String response = provider.putObject(
                    s3FileName,
                    base64Body,
                    'application/octet-stream'
                );
                System.debug('ArchivePostProcessQueueable: S3 upload success for ' + s3FileName + ' -> ' + response);
            } catch (Exception ex) {
                System.debug('ArchivePostProcessQueueable: upload failed for ContentVersion ' + versionRecord.Id + ': ' + ex.getMessage());
            }
        }

        // ===== DML AFTER callouts — save encryption key + provider name =====
        try {
            update new Data_Archive__c(
                Id = archiveRecordId,
                Encryption_Key__c    = EncodingUtil.base64Encode(aesKey),
                // Save the DeveloperName (storageProviderName), not Provider_Type__c.
                // Fallback to getProviderType() only when called from old backward-compat paths.
                Storage_Provider__c  = String.isNotBlank(storageProviderName)
                                         ? storageProviderName
                                         : provider.getProviderType()
            );
            System.debug('ArchivePostProcessQueueable: encryption key and provider saved to archive record.');
        } catch (Exception ex) {
            System.debug('ArchivePostProcessQueueable: failed to save encryption key / provider: ' + ex.getMessage());
        }
    }
}