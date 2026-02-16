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

        for (ContentVersion versionRecord : versions) {
            try {
                String partSuffix = '';
                if (!String.isBlank(versionRecord.Description)) {
                    partSuffix = '_' + versionRecord.Description.replace(' ', '_');
                }

                String s3FileName = String.valueOf(archiveRecordId) + '/' + versionRecord.Title + partSuffix;
                if (!String.isBlank(versionRecord.FileExtension)) {
                    s3FileName += '.' + versionRecord.FileExtension;
                }

                String base64Body = versionRecord.VersionData == null
                    ? ''
                    : EncodingUtil.base64Encode(versionRecord.VersionData);

                String response = S3Controller.putObjectToS3(
                    s3FileName,
                    base64Body,
                    'text/csv'
                );
                System.debug('ArchivePostProcessQueueable: S3 upload success for ' + s3FileName + ' -> ' + response);
            } catch (Exception ex) {
                System.debug('ArchivePostProcessQueueable: S3 upload failed for ContentVersion ' + versionRecord.Id + ': ' + ex.getMessage());
            }
        }
    }
}