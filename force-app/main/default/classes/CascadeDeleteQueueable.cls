public class CascadeDeleteQueueable implements Database.Batchable<SObject> {

    private String parentObjectApi;
    private List<Id> parentIds;

    public CascadeDeleteQueueable(
        String parentObjectApi,
        List<Id> parentIds
    ) {
        this.parentObjectApi = parentObjectApi;
        this.parentIds = parentIds;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (parentIds == null || parentIds.isEmpty()) {
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        if (!Schema.getGlobalDescribe().containsKey(parentObjectApi)) {
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        return Database.getQueryLocator(
            'SELECT Id FROM ' + parentObjectApi + ' WHERE Id IN :parentIds'
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        Database.delete(scope, false);
    }

    public void finish(Database.BatchableContext context) {
    }
}