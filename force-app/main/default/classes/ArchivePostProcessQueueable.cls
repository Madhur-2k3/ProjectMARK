public class ArchivePostProcessQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> contentDocumentIds;
    private Id archiveRecordId;
    private String parentObjectApi;
    private List<Id> parentIds;

    public ArchivePostProcessQueueable(
        List<Id> contentDocumentIds,
        Id archiveRecordId,
        String parentObjectApi,
        List<Id> parentIds
    ) {
        this.contentDocumentIds = contentDocumentIds == null ? new List<Id>() : contentDocumentIds;
        this.archiveRecordId = archiveRecordId;
        this.parentObjectApi = parentObjectApi;
        this.parentIds = parentIds == null ? new List<Id>() : parentIds;
    }

    public void execute(QueueableContext context) {
        uploadArchiveFilesToS3();

        if (!parentIds.isEmpty()) {
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

    private void uploadArchiveFilesToS3() {
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

        System.debug('ArchivePostProcessQueueable: uploading ' + versions.size() + ' archive file(s) to S3.');

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

                String response = S3Controller.putObjectToS3(
                    s3FileName,
                    base64Body,
                    'application/octet-stream'
                );
                System.debug('ArchivePostProcessQueueable: S3 upload success for ' + s3FileName + ' -> ' + response);
            } catch (Exception ex) {
                System.debug('ArchivePostProcessQueueable: S3 upload failed for ContentVersion ' + versionRecord.Id + ': ' + ex.getMessage());
            }
        }

        // ===== DML AFTER callouts — save the encryption key =====
        try {
            update new Data_Archive__c(
                Id = archiveRecordId,
                Encryption_Key__c = EncodingUtil.base64Encode(aesKey)
            );
            System.debug('ArchivePostProcessQueueable: encryption key saved to archive record.');
        } catch (Exception ex) {
            System.debug('ArchivePostProcessQueueable: failed to save encryption key: ' + ex.getMessage());
        }
    }
}