/**
 * @description Batchable class that handles post-processing of Data Archive records.
 *              Processes CSV files ONE AT A TIME to avoid heap/callout governor limits.
 *              Each execute() encrypts and uploads a single file to S3.
 *              On finish, stores the encryption key and chains to CascadeDeleteQueueable.
 */
public with sharing class ArchivePostProcessQueueable
    implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    private List<Id> contentDocIdsList;
    private Id archiveRecordId;
    private String rootObjectNameStr;
    private List<Id> processedParentIdsList;
    private String aesKeyBase64Str;

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

        // Generate AES-256 key upfront; stored as Base64 string for safe serialization
        Blob aesKeyBlob = Crypto.generateAesKey(256);
        this.aesKeyBase64Str = EncodingUtil.base64Encode(aesKeyBlob);
    }

    /**
     * @description Returns a QueryLocator for the ContentVersion records to process.
     *              Run with batch scope = 1 so each execute() handles one file.
     * @param batchContext The BatchableContext provided by the platform.
     * @return A Database.QueryLocator for the ContentVersion records.
     */
    public Database.QueryLocator start(Database.BatchableContext batchContext) {

        if (contentDocIdsList == null || contentDocIdsList.isEmpty()) {
            return Database.getQueryLocator(
                'SELECT Id, Title, FileExtension, VersionData, ContentDocumentId ' +
                'FROM ContentVersion WHERE Id = null'
            );
        }

        return Database.getQueryLocator(
            'SELECT Id, Title, FileExtension, VersionData, ContentDocumentId ' +
            'FROM ContentVersion ' +
            'WHERE ContentDocumentId IN :contentDocIdsList ' +
            'AND IsLatest = true'
        );
    }

    /**
     * @description Processes one ContentVersion per batch chunk: encrypts and uploads to S3.
     * @param batchContext The BatchableContext provided by the platform.
     * @param scopeList The list of ContentVersion records in this batch chunk.
     */
    public void execute(Database.BatchableContext batchContext, List<SObject> scopeList) {

        if (scopeList == null || scopeList.isEmpty()) return;

        Blob aesKeyBlob = EncodingUtil.base64Decode(this.aesKeyBase64Str);

        for (SObject record : scopeList) {
            ContentVersion currentVersion = (ContentVersion) record;

            String fileNameStr = String.valueOf(archiveRecordId) + '/' + currentVersion.Title;

            if (String.isNotBlank(currentVersion.FileExtension)) {
                fileNameStr += '.' + currentVersion.FileExtension;
            }

            // Encrypt the content
            Blob encryptedBlob = Crypto.encryptWithManagedIV(
                'AES256', aesKeyBlob, currentVersion.VersionData
            );
            fileNameStr += '.enc';
            String base64BodyStr = EncodingUtil.base64Encode(encryptedBlob);

            try {
                S3Controller.putObjectToS3(fileNameStr, base64BodyStr, 'application/octet-stream');
                System.debug('Uploaded to S3: ' + fileNameStr);
            } catch (Exception ex) {
                System.debug('S3 upload failed for ' + fileNameStr + ': ' + ex.getMessage());
            }
        }
    }

    /**
     * @description Called after all files are uploaded. Stores the encryption key
     *              and chains to CascadeDeleteQueueable for record cleanup.
     * @param batchContext The BatchableContext provided by the platform.
     */
    public void finish(Database.BatchableContext batchContext) {

        System.debug('ArchivePostProcessQueueable batch finished');

        // Store encryption key on the archive record
        if (archiveRecordId != null) {
            try {
                Data_Archive__c archiveRecord = new Data_Archive__c(
                    Id                = archiveRecordId,
                    Encryption_Key__c = aesKeyBase64Str
                );

                // Only set 'Completed' if there are no records to delete
                if (processedParentIdsList == null || processedParentIdsList.isEmpty()) {
                    archiveRecord.Status__c = 'Completed';
                }

                update archiveRecord;
            } catch (Exception ex) {
                System.debug('Failed to update archive record: ' + ex.getMessage());
            }
        }

        // Chain to cascade deletion batch (it will set status to 'Completed' when done)
        if (processedParentIdsList != null && !processedParentIdsList.isEmpty()) {
            Database.executeBatch(
                new CascadeDeleteQueueable(rootObjectNameStr, processedParentIdsList, archiveRecordId),
                200
            );
            System.debug('CascadeDeleteQueueable batch started for: ' + rootObjectNameStr);
        }
    }
}