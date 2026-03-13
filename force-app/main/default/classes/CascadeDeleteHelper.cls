public with sharing class CascadeDeleteHelper {

    public static void deleteParentWithRelations(
        String parentObjectApi,
        List<Id> parentIds
    ) {
        if (parentIds == null || parentIds.isEmpty()) return;

        if (!Schema.getGlobalDescribe().containsKey(parentObjectApi)) return;

        Database.executeBatch(new CascadeDeleteQueueable(parentObjectApi, parentIds), 200);
    }
}