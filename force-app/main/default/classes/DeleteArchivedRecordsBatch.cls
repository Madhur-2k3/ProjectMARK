/**
 * @description Batch class that deletes records returned by a provided SOQL query.
 *              Used to clean up original records after they have been archived.
 */
public class DeleteArchivedRecordsBatch implements Database.Batchable<SObject> {

    private String soqlQueryStr;

    /**
     * @description Constructs a new DeleteArchivedRecordsBatch with the given SOQL query.
     * @param soqlQueryStr The SOQL query string that identifies records to delete.
     */
    public DeleteArchivedRecordsBatch(String soqlQueryStr) {

        this.soqlQueryStr = soqlQueryStr;
    }

    /**
     * @description Returns a QueryLocator for the batch to process.
     * @param batchContext The BatchableContext provided by the platform.
     * @return A Database.QueryLocator for the records to delete.
     */
    public Database.QueryLocator start(Database.BatchableContext batchContext) {

        return Database.getQueryLocator(this.soqlQueryStr);
    }

    /**
     * @description Deletes the records in the current batch scope.
     * @param batchContext The BatchableContext provided by the platform.
     * @param scopeList The list of SObject records to delete in this batch chunk.
     */
    public void execute(Database.BatchableContext batchContext, List<SObject> scopeList) {

        if (!scopeList.isEmpty()) {
            delete scopeList;
        }
    }

    /**
     * @description Called when the batch job finishes. Logs completion.
     * @param batchContext The BatchableContext provided by the platform.
     */
    public void finish(Database.BatchableContext batchContext) {

        System.debug('Delete batch completed.');
    }
}