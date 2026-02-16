public with sharing class ContentDocumentLinkTriggerHandler {
    public static void afterInsert(List<ContentDocumentLink> newLinks) {
        if (newLinks == null || newLinks.isEmpty()) return;

        // Avoid enqueueing S3 upload jobs from async contexts (Batch/Future/Queueable),
        // otherwise archival batch flow can fail to enqueue its own delete queueable.
        if (System.isBatch() || System.isFuture() || System.isQueueable()) {
            System.debug('ContentDocumentLinkTriggerHandler: skipping S3 enqueue in async context.');
            return;
        }

        System.debug('ContentDocumentLinkTriggerHandler.afterInsert invoked, newLinks size: ' + (newLinks == null ? 0 : newLinks.size()));

        // Collect linked entity ids and content document ids
        Set<Id> linkedIds = new Set<Id>();
        for (ContentDocumentLink cdl : newLinks) {
            if (cdl.LinkedEntityId != null) linkedIds.add(cdl.LinkedEntityId);
        }
        System.debug('ContentDocumentLinkTriggerHandler: linkedIds=' + linkedIds);
        if (linkedIds.isEmpty()) return;

        // Filter to only Data_Archive__c records
        Set<Id> archiveIds = new Set<Id>();
        for (Data_Archive__c da : [SELECT Id FROM Data_Archive__c WHERE Id IN :linkedIds]) {
            archiveIds.add(da.Id);
        }
        System.debug('ContentDocumentLinkTriggerHandler: archiveIds=' + archiveIds);
        if (archiveIds.isEmpty()) return;

        // Build pairs of ContentDocumentId|DataArchiveId to pass to queueable
        List<String> pairs = new List<String>();
        for (ContentDocumentLink cdl : newLinks) {
            if (cdl.ContentDocumentId != null && cdl.LinkedEntityId != null && archiveIds.contains(cdl.LinkedEntityId)) {
                pairs.add(String.valueOf(cdl.ContentDocumentId) + '|' + String.valueOf(cdl.LinkedEntityId));
            }
        }
        System.debug('ContentDocumentLinkTriggerHandler: pairs=' + pairs);
        if (!pairs.isEmpty()) {
            // Enqueue queueable uploader to perform callouts and upload to S3
            System.debug('ContentDocumentLinkTriggerHandler: enqueueing S3UploadQueueable with ' + pairs.size() + ' pairs');
            try {
                System.enqueueJob(new S3UploadQueueable(pairs));
            } catch (Exception ex) {
                System.debug('ContentDocumentLinkTriggerHandler: failed to enqueue S3UploadQueueable: ' + ex.getMessage());
            }
        }
    }
}