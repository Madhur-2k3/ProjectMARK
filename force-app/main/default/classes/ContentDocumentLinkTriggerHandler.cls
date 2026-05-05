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

        // Filter to only Data_Archive__c records — also capture Storage_Provider__c for routing
        Set<Id> archiveIds = new Set<Id>();
        Map<Id, String> archiveProviderMap = new Map<Id, String>();
        for (Data_Archive__c da : [
            SELECT Id, Storage_Provider__c FROM Data_Archive__c WHERE Id IN :linkedIds
        ]) {
            archiveIds.add(da.Id);
            archiveProviderMap.put(da.Id, da.Storage_Provider__c);
        }
        System.debug('ContentDocumentLinkTriggerHandler: archiveIds=' + archiveIds);
        if (archiveIds.isEmpty()) return;

        // Build pairs of ContentDocumentId|DataArchiveId grouped by provider
        // (all links in a single trigger batch share the same parent archive, but handle edge cases)
        Map<String, List<String>> providerToPairs = new Map<String, List<String>>();
        for (ContentDocumentLink cdl : newLinks) {
            if (cdl.ContentDocumentId != null && cdl.LinkedEntityId != null
                    && archiveIds.contains(cdl.LinkedEntityId)) {
                String providerKey = archiveProviderMap.get(cdl.LinkedEntityId); // may be null for new archives
                if (!providerToPairs.containsKey(providerKey)) {
                    providerToPairs.put(providerKey, new List<String>());
                }
                providerToPairs.get(providerKey).add(
                    String.valueOf(cdl.ContentDocumentId) + '|' + String.valueOf(cdl.LinkedEntityId)
                );
            }
        }
        List<String> pairs = new List<String>(); // flattened (for backward compat logging)
        String firstProvider = null;
        for (String pKey : providerToPairs.keySet()) {
            pairs.addAll(providerToPairs.get(pKey));
            if (firstProvider == null) firstProvider = pKey;
        }
        System.debug('ContentDocumentLinkTriggerHandler: pairs=' + pairs);
        if (!pairs.isEmpty()) {
            System.debug('ContentDocumentLinkTriggerHandler: enqueueing StorageUploadQueueable with ' + pairs.size() + ' pairs, provider=' + firstProvider);
            try {
                System.enqueueJob(new StorageUploadQueueable(pairs, firstProvider));
            } catch (Exception ex) {
                System.debug('ContentDocumentLinkTriggerHandler: failed to enqueue StorageUploadQueueable: ' + ex.getMessage());
            }
        }
    }
}