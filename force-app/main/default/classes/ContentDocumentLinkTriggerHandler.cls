/**
 * @description Trigger handler for ContentDocumentLink that automatically uploads
 *              linked files to S3 when they are associated with Data_Archive__c records.
 */
public with sharing class ContentDocumentLinkTriggerHandler {

    /**
     * @description Processes newly inserted ContentDocumentLinks. If any link's
     *              LinkedEntityId references a Data_Archive__c record, queues an
     *              S3 upload for those documents.
     * @param newLinksList List of newly inserted ContentDocumentLink records.
     */
    public static void afterInsert(List<ContentDocumentLink> newLinksList) {

        List<String> docPairsList = new List<String>();

        String archivePrefixStr = Data_Archive__c.SObjectType.getDescribe().getKeyPrefix();

        for (ContentDocumentLink currentLink : newLinksList) {

            String linkedEntityIdStr = String.valueOf(currentLink.LinkedEntityId);

            if (linkedEntityIdStr.startsWith(archivePrefixStr)) {
                docPairsList.add(currentLink.ContentDocumentId + '|' + currentLink.LinkedEntityId);
            }
        }

        if (!docPairsList.isEmpty()) {

            if (!System.isBatch() && !System.isFuture() && !System.isQueueable()) {
                System.enqueueJob(new S3UploadQueueable(docPairsList));
            }
            // Skip S3 upload in batch/future/queueable context —
            // ArchivePostProcessQueueable handles uploads for archive CSVs.
        }
    }
}