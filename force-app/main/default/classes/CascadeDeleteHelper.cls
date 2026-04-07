public with sharing class CascadeDeleteHelper {

    /**
     * Entry point: discovers all child relationships (both master-detail and lookup)
     * for the given parent object, then starts a CascadeIdCollectorBatch to collect
     * child IDs using getQueryLocator (50M row limit) before deletion.
     *
     * Master-detail children are auto-cascade-deleted by Salesforce when their
     * parent is deleted, so only lookup children need manual deletion.
     */
    public static void deleteParentWithRelations(
        String parentObjectApi,
        List<Id> parentIds
    ) {
        if (parentIds == null || parentIds.isEmpty()) return;
        if (!Schema.getGlobalDescribe().containsKey(parentObjectApi)) return;

        // 1. Discover all child relationships recursively (MD + lookup)
        List<ChildRelInfo> allRelations = new List<ChildRelInfo>();
        Set<String> visited = new Set<String>();
        visited.add(parentObjectApi);
        discoverChildren(parentObjectApi, 1, allRelations, visited);

        System.debug('CascadeDeleteHelper: discovered ' + allRelations.size()
                   + ' child relationships for ' + parentObjectApi);

        if (allRelations.isEmpty()) {
            // No children — just delete the parents directly
            Database.executeBatch(
                new CascadeDeleteQueueable(parentObjectApi, parentIds),
                200
            );
            return;
        }

        // 2. Sort by depth ascending for top-down ID collection
        allRelations.sort();

        // 3. Seed collectedIds with root parent IDs
        Map<String, List<Id>> collectedIds = new Map<String, List<Id>>();
        collectedIds.put(parentObjectApi, parentIds);

        // 4. Start CascadeIdCollectorBatch — collects child IDs one relationship
        //    at a time using getQueryLocator in start() (50M row limit).
        //    After all IDs are collected, it calls startDeletionChain().
        Database.executeBatch(new CascadeIdCollectorBatch(
            allRelations, collectedIds, parentObjectApi, parentIds
        ), 10000);

        System.debug('CascadeDeleteHelper: started CascadeIdCollectorBatch with '
                   + allRelations.size() + ' relationships');
    }

    /**
     * Called by CascadeIdCollectorBatch after all child IDs are collected.
     * Builds deletion steps (bottom-up) and starts CascadeDeleteQueueable chain.
     */
    public static void startDeletionChain(
        Map<String, List<Id>> collectedIds,
        String rootObjectName,
        List<Id> rootParentIds
    ) {
        // Re-discover relationships to get metadata for building deletion steps
        List<ChildRelInfo> allRelations = new List<ChildRelInfo>();
        Set<String> visited = new Set<String>();
        visited.add(rootObjectName);
        discoverChildren(rootObjectName, 1, allRelations, visited);
        allRelations.sort();

        // Build deletion steps for LOOKUP children only (bottom-up / deepest first).
        // Master-detail children auto-cascade when their parent is deleted.
        List<CascadeDeleteQueueable.DeletionStep> steps =
            new List<CascadeDeleteQueueable.DeletionStep>();

        for (Integer i = allRelations.size() - 1; i >= 0; i--) {
            ChildRelInfo rel = allRelations[i];

            // Skip master-detail — Salesforce handles cascade delete automatically
            if (rel.isCascadeDelete) continue;

            List<Id> ids = collectedIds.get(rel.objectName);
            if (ids == null || ids.isEmpty()) continue;

            steps.add(new CascadeDeleteQueueable.DeletionStep(rel.objectName, ids));
            System.debug('CascadeDeleteHelper: queued deletion of ' + ids.size()
                       + ' ' + rel.objectName + ' records (depth ' + rel.depth + ')');
        }

        // Add root parent deletion as the final step
        steps.add(new CascadeDeleteQueueable.DeletionStep(rootObjectName, rootParentIds));

        // Start the chained batch — first step first
        if (!steps.isEmpty()) {
            CascadeDeleteQueueable.DeletionStep firstStep = steps.remove(0);
            Database.executeBatch(
                new CascadeDeleteQueueable(firstStep, steps),
                200
            );
            System.debug('CascadeDeleteHelper: started cascade delete chain with '
                       + (steps.size() + 1) + ' total steps');
        }
    }

    // ===================== RELATIONSHIP DISCOVERY =====================

    private static void discoverChildren(String parentObjName, Integer depth,
                                          List<ChildRelInfo> allRelations,
                                          Set<String> visited) {
        if (depth > Integer.valueOf(Label.MAX_CHAIN_DEPTH)) return;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjName);
        if (objType == null) return;

        for (Schema.ChildRelationship childRel : objType.getDescribe().getChildRelationships()) {

            Schema.DescribeFieldResult fieldDesc = childRel.getField().getDescribe();
            if (fieldDesc.getType() != Schema.DisplayType.REFERENCE) continue;

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            String childObjectName   = childDescribe.getName();
            String relationshipField = fieldDesc.getName();
            String relationshipName  = childRel.getRelationshipName();

            if (relationshipName == null) continue;
            if (visited.contains(childObjectName)) continue;

            // Skip system objects (same filters as DataArchiveBatch)
            if (childObjectName.endsWith('Share')        ||
                childObjectName.endsWith('History')      ||
                childObjectName.endsWith('Feed')         ||
                childObjectName.endsWith('ChangeEvent')) continue;

            if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) continue;
            if (!childDescribe.isDeletable()) continue;

            visited.add(childObjectName);

            ChildRelInfo rel = new ChildRelInfo();
            rel.objectName        = childObjectName;
            rel.relationshipField = relationshipField;
            rel.parentObjectName  = parentObjName;
            rel.depth             = depth;
            rel.isCascadeDelete   = childRel.isCascadeDelete();
            allRelations.add(rel);

            System.debug('CascadeDeleteHelper: found [depth-' + depth + '] ['
                       + (rel.isCascadeDelete ? 'MD' : 'Lookup') + '] '
                       + childObjectName + ' via ' + relationshipField
                       + ' → ' + parentObjName);

            // Recurse into children of this child
            discoverChildren(childObjectName, depth + 1, allRelations, visited);
        }
    }

    // ===================== INNER CLASS =====================

    public class ChildRelInfo implements Comparable {
        public String  objectName;
        public String  relationshipField;
        public String  parentObjectName;
        public Integer depth;
        public Boolean isCascadeDelete;

        public Integer compareTo(Object other) {
            return this.depth - ((ChildRelInfo) other).depth;
        }
    }
}