/**
 * @description Helper class that provides utility methods for cascade deletion
 *              of child records related to a parent SObject.
 */
public with sharing class CascadeDeleteHelper {

    /**
     * @description Retrieves a set of child object API names that have a
     *              lookup or master-detail relationship to the given parent object.
     * @param parentObjectStr The API name of the parent SObject.
     * @return A Set of child object API names related to the parent.
     */
    public static Set<String> getChildObjects(String parentObjectStr) {

        Set<String> childObjectsSet = new Set<String>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjectStr);

        if (objType == null) {
            return childObjectsSet;
        }

        for (Schema.ChildRelationship relationship : objType.getDescribe().getChildRelationships()) {
            childObjectsSet.add(relationship.getChildSObject().getDescribe().getName());
        }

        return childObjectsSet;
    }

    /**
     * @description Deletes parent records and ALL their descendant records recursively.
     *              Collects the full hierarchy bottom-up (deepest children first),
     *              then deletes in that order to avoid FK constraint errors.
     * @param parentObjectStr The API name of the parent SObject.
     * @param parentIdsList List of parent record IDs to delete along with their children.
     */
    public static void deleteParentWithRelations(String parentObjectStr, List<Id> parentIdsList) {

        if (parentIdsList == null || parentIdsList.isEmpty()) return;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjectStr);
        if (objType == null) return;

        // Collect all descendant records bottom-up (deepest first)
        List<DeletionUnit> deletionPlan = new List<DeletionUnit>();
        Set<String> visitedSet = new Set<String>();

        collectChildDeletions(parentObjectStr, parentIdsList, deletionPlan, visitedSet);

        // Add parent records at the end (deleted last)
        deletionPlan.add(new DeletionUnit(parentObjectStr, parentIdsList));

        // Execute deletions in order (deepest children first, parent last)
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