/**
 * @description Queueable and Batchable class that performs recursive cascade deletion
 *              of child records for specified parent record IDs. Deletes from the
 *              deepest children up to the parent records to avoid FK constraint errors.
 */
public with sharing class CascadeDeleteQueueable implements Queueable, Database.Batchable<SObject> {

    private String objectNameStr;
    private List<Id> parentIdsList;

    /**
     * @description Constructs a new CascadeDeleteQueueable instance.
     * @param objectNameStr API name of the object whose records should be deleted.
     * @param parentIdsList List of parent record IDs to delete along with children.
     */
    public CascadeDeleteQueueable(String objectNameStr, List<Id> parentIdsList) {

        this.objectNameStr = objectNameStr;
        this.parentIdsList = parentIdsList;
    }

    /**
     * @description Executes the recursive cascade delete via Queueable interface.
     * @param context The QueueableContext provided by the platform.
     */
    public void execute(QueueableContext context) {

        if (parentIdsList == null || parentIdsList.isEmpty()) return;

        deleteRecursively(objectNameStr, parentIdsList);
    }

    /**
     * @description Returns a QueryLocator for the Batchable interface.
     * @param batchContext The BatchableContext provided by the platform.
     * @return A Database.QueryLocator for the parent records.
     */
    public Database.QueryLocator start(Database.BatchableContext batchContext) {

        if (parentIdsList == null || parentIdsList.isEmpty()) {
            return Database.getQueryLocator('SELECT Id FROM Account WHERE Id = null');
        }

        String queryStr = 'SELECT Id FROM ' + objectNameStr + ' WHERE Id IN :parentIdsList';
        return Database.getQueryLocator(queryStr);
    }

    /**
     * @description Processes each batch chunk by deleting the records recursively.
     * @param batchContext The BatchableContext provided by the platform.
     * @param scopeList The list of SObject records in this batch chunk.
     */
    public void execute(Database.BatchableContext batchContext, List<SObject> scopeList) {

        if (scopeList == null || scopeList.isEmpty()) return;

        List<Id> scopeIdsList = new List<Id>();
        for (SObject currentRecord : scopeList) {
            scopeIdsList.add(currentRecord.Id);
        }

        deleteRecursively(objectNameStr, scopeIdsList);
    }

    /**
     * @description Called after all batch chunks are processed.
     * @param batchContext The BatchableContext provided by the platform.
     */
    public void finish(Database.BatchableContext batchContext) {

        System.debug('CascadeDeleteQueueable batch finished for: ' + objectNameStr);
    }

    // =====================================================
    // RECURSIVE DELETION LOGIC
    // =====================================================

    /**
     * @description Deletes records and all their descendants recursively.
     *              Collects all child record IDs bottom-up, then deletes
     *              deepest children first, working up to the parent records.
     * @param objectName The API name of the object to delete.
     * @param recordIds The record IDs to delete along with their children.
     */
    private static void deleteRecursively(String objectName, List<Id> recordIds) {

        if (recordIds == null || recordIds.isEmpty()) return;

        List<DeletionUnit> deletionPlan = new List<DeletionUnit>();
        Set<String> visitedSet = new Set<String>();

        // Collect children bottom-up (deepest first)
        collectChildDeletions(objectName, recordIds, deletionPlan, visitedSet);

        // Add the parent itself at the end (deleted last)
        deletionPlan.add(new DeletionUnit(objectName, recordIds));

        // Execute deletions in order (children first, parent last)
        for (DeletionUnit unit : deletionPlan) {
            try {
                List<Id> unitIds = unit.recordIds;
                String queryStr = 'SELECT Id FROM ' + unit.objectName +
                    ' WHERE Id IN :unitIds';
                List<SObject> records = Database.query(queryStr);

                if (!records.isEmpty()) {
                    Database.delete(records, false);
                    System.debug('Deleted ' + records.size() + ' records from ' + unit.objectName);
                }
            } catch (Exception ex) {
                System.debug('Error deleting ' + unit.objectName + ': ' + ex.getMessage());
            }
        }
    }

    /**
     * @description Recursively collects child record IDs for deletion, deepest first.
     * @param objectName The object whose children to collect.
     * @param parentIds The parent record IDs to look up children for.
     * @param deletionPlan The list to add deletion units to (deepest first).
     * @param visitedSet Objects already visited (cycle prevention).
     */
    private static void collectChildDeletions(String objectName, List<Id> parentIds,
                                               List<DeletionUnit> deletionPlan, Set<String> visitedSet) {

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) return;

        visitedSet.add(objectName);

        for (Schema.ChildRelationship childRel : objType.getDescribe().getChildRelationships()) {

            if (childRel.getRelationshipName() == null) continue;

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            String childObjectName = childDescribe.getName();

            if (visitedSet.contains(childObjectName)) continue;
            if (!childDescribe.isDeletable()) continue;
            if (!childDescribe.isQueryable() || !childDescribe.isAccessible()) continue;

            String relField = childRel.getField().getDescribe().getName();

            try {
                String queryStr = 'SELECT Id FROM ' + childObjectName +
                    ' WHERE ' + relField + ' IN :parentIds';
                List<SObject> childRecords = Database.query(queryStr);

                if (!childRecords.isEmpty()) {
                    List<Id> childIds = new List<Id>();
                    for (SObject rec : childRecords) {
                        childIds.add(rec.Id);
                    }

                    // Recurse deeper first (grandchildren deleted before children)
                    collectChildDeletions(childObjectName, childIds, deletionPlan, visitedSet);

                    // Then add this level
                    deletionPlan.add(new DeletionUnit(childObjectName, childIds));
                }
            } catch (Exception ex) {
                System.debug('Error querying children of ' + childObjectName + ': ' + ex.getMessage());
            }
        }

        visitedSet.remove(objectName);
    }

    /**
     * @description Simple wrapper to hold an object name and its record IDs for deletion.
     */
    private class DeletionUnit {

        public String objectName;
        public List<Id> recordIds;

        public DeletionUnit(String objName, List<Id> ids) {
            this.objectName = objName;
            this.recordIds = ids;
        }
    }
}