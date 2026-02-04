public class DeleteArchivedRecordsBatch implements Database.Batchable<SObject> {
    
    private String soqlQuery;
    
    public DeleteArchivedRecordsBatch(String soqlQuery) {
        this.soqlQuery = soqlQuery;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(this.soqlQuery);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (!scope.isEmpty()) {
            delete scope;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Delete batch completed.');
    }
}