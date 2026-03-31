/**
 * @description Queueable class that handles post-processing of Data Archive records.
 *              Uploads CSV files to S3, encrypts them, stores the encryption key,
 *              and deletes the original parent records via CascadeDeleteHelper.
 */
public with sharing class ArchivePostProcessQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> contentDocIdsList;
    private Id archiveRecordId;
    private String rootObjectNameStr;
    private List<Id> processedParentIdsList;

    /**
     * @description Constructs a new ArchivePostProcessQueueable.
     * @param contentDocIdsList List of ContentDocument IDs to upload to S3.
     * @param archiveRecordId The ID of the Data_Archive__c record.
     * @param rootObjectNameStr The API name of the root SObject being archived.
     * @param processedParentIdsList List of parent record IDs for deletion.
     */
    public ArchivePostProcessQueueable(List<Id> contentDocIdsList, Id archiveRecordId,
                                        String rootObjectNameStr, List<Id> processedParentIdsList) {

        this.contentDocIdsList = contentDocIdsList;
        this.archiveRecordId = archiveRecordId;
        this.rootObjectNameStr = rootObjectNameStr;
        this.processedParentIdsList = processedParentIdsList;
    }

    /**
     * @description Executes the post-processing: uploads linked CSV files to S3,
     *              encrypts them, stores the encryption key, updates archive status,
     *              and deletes original records.
     * @param context The QueueableContext provided by the platform.
     */
    public void execute(QueueableContext context) {

        // ── 1. Generate AES-256 encryption key ──
        Blob aesKeyBlob = Crypto.generateAesKey(256);
        String aesKeyBase64Str = EncodingUtil.base64Encode(aesKeyBlob);

        // ── 2. Get ContentVersions for the given doc IDs ──
        List<ContentVersion> versionsList = new List<ContentVersion>();

        if (contentDocIdsList != null && !contentDocIdsList.isEmpty()) {
            versionsList = [
                SELECT Id, Title, FileExtension, VersionData, Description, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocIdsList
                AND IsLatest = true
            ];
        }

        // ── 3. Upload each file to S3 (encrypted) ──
        if (archiveRecordId != null) {
            for (ContentVersion currentVersion : versionsList) {

                String fileNameStr = String.valueOf(archiveRecordId) + '/' + currentVersion.Title;

                if (String.isNotBlank(currentVersion.FileExtension)) {
                    fileNameStr += '.' + currentVersion.FileExtension;
                }

                // Encrypt the content
                Blob encryptedBlob = Crypto.encryptWithManagedIV('AES256', aesKeyBlob, currentVersion.VersionData);
                fileNameStr += '.enc';
                String base64BodyStr = EncodingUtil.base64Encode(encryptedBlob);

                try {
                    S3Controller.putObjectToS3(fileNameStr, base64BodyStr, 'application/octet-stream');
                } catch (Exception ex) {
                    System.debug('S3 upload failed for ' + fileNameStr + ': ' + ex.getMessage());
                }
            }

            // ── 4. Store encryption key and update status ──
            Data_Archive__c archiveRecord = new Data_Archive__c(
                Id = archiveRecordId,
                Status__c = 'Completed',
                Encryption_Key__c = aesKeyBase64Str
            );
            update archiveRecord;
        }

        // ── 5. Delete original parent records ──
        if (processedParentIdsList != null && !processedParentIdsList.isEmpty()) {
            CascadeDeleteHelper.deleteParentWithRelations(rootObjectNameStr, processedParentIdsList);
        }
    }
}