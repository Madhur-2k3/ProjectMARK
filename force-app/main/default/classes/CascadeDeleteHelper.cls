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
     * @description Deletes parent records and their related child records.
     *              Queries each child relationship and deletes child records first,
     *              then deletes the parent records.
     * @param parentObjectStr The API name of the parent SObject.
     * @param parentIdsList List of parent record IDs to delete along with their children.
     */
    public static void deleteParentWithRelations(String parentObjectStr, List<Id> parentIdsList) {

        if (parentIdsList == null || parentIdsList.isEmpty()) return;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjectStr);
        if (objType == null) return;

        // Delete child records first
        for (Schema.ChildRelationship childRel : objType.getDescribe().getChildRelationships()) {

            String childObjectNameStr = childRel.getChildSObject().getDescribe().getName();
            String relationshipFieldStr = childRel.getField().getDescribe().getName();
            String relationshipNameStr = childRel.getRelationshipName();

            if (relationshipNameStr == null) continue;
            if (!childRel.getChildSObject().getDescribe().isDeletable()) continue;

            try {
                String queryStr = 'SELECT Id FROM ' + childObjectNameStr +
                    ' WHERE ' + relationshipFieldStr + ' IN :parentIdsList';
                List<SObject> childRecordsList = Database.query(queryStr);

                if (!childRecordsList.isEmpty()) {
                    Database.delete(childRecordsList, false);
                }
            } catch (Exception ex) {
                System.debug('Error deleting children of ' + childObjectNameStr + ': ' + ex.getMessage());
            }
        }

        // Delete parent records
        try {
            String parentQueryStr = 'SELECT Id FROM ' + parentObjectStr + ' WHERE Id IN :parentIdsList';
            List<SObject> parentRecordsList = Database.query(parentQueryStr);

            if (!parentRecordsList.isEmpty()) {
                Database.delete(parentRecordsList, false);
            }
        } catch (Exception ex) {
            System.debug('Error deleting parent records: ' + ex.getMessage());
        }
    }
}