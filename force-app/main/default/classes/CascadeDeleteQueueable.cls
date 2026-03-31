/**
 * @description Queueable and Batchable class that performs cascade deletion of
 *              child records for specified parent record IDs.
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
     * @description Executes the cascade delete via Queueable interface.
     * @param context The QueueableContext provided by the platform.
     */
    public void execute(QueueableContext context) {

        if (parentIdsList == null || parentIdsList.isEmpty()) return;

        CascadeDeleteHelper.deleteParentWithRelations(objectNameStr, parentIdsList);
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
     * @description Processes each batch chunk by deleting the records.
     * @param batchContext The BatchableContext provided by the platform.
     * @param scopeList The list of SObject records in this batch chunk.
     */
    public void execute(Database.BatchableContext batchContext, List<SObject> scopeList) {

        if (scopeList == null || scopeList.isEmpty()) return;

        List<Id> scopeIdsList = new List<Id>();
        for (SObject currentRecord : scopeList) {
            scopeIdsList.add(currentRecord.Id);
        }

        CascadeDeleteHelper.deleteParentWithRelations(objectNameStr, scopeIdsList);
    }

    /**
     * @description Called after all batch chunks are processed.
     * @param batchContext The BatchableContext provided by the platform.
     */
    public void finish(Database.BatchableContext batchContext) {

        System.debug('CascadeDeleteQueueable batch finished for: ' + objectNameStr);
    }
}