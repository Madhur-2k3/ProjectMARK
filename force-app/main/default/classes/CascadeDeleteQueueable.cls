public class CascadeDeleteQueueable implements Database.Batchable<SObject> {

    /**
     * Represents a single deletion step: delete all records of a given
     * object type by their collected IDs.
     */
    public class DeletionStep {
        public String   objectName;
        public List<Id> recordIds;

        public DeletionStep() {}

        public DeletionStep(String objectName, List<Id> recordIds) {
            this.objectName = objectName;
            this.recordIds  = recordIds;
        }
    }

    private DeletionStep currentStep;
    private List<DeletionStep> remainingSteps;

    /**
     * @param currentStep    The step to execute in this batch run
     * @param remainingSteps Steps to chain after this one completes
     */
    public CascadeDeleteQueueable(DeletionStep currentStep, List<DeletionStep> remainingSteps) {
        this.currentStep    = currentStep;
        this.remainingSteps = remainingSteps != null ? remainingSteps : new List<DeletionStep>();
    }

    /**
     * Backward-compatible constructor: delete records of a single object only.
     */
    public CascadeDeleteQueueable(String parentObjectApi, List<Id> parentIds) {
        this(
            new DeletionStep(parentObjectApi, parentIds),
            new List<DeletionStep>()
        );
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        List<Id> recordIds = currentStep.recordIds;

        if (recordIds == null || recordIds.isEmpty()) {
            System.debug('CascadeDeleteQueueable: no records for ' + currentStep.objectName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        if (!Schema.getGlobalDescribe().containsKey(currentStep.objectName)) {
            System.debug('CascadeDeleteQueueable: invalid object ' + currentStep.objectName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        System.debug('CascadeDeleteQueueable: starting deletion of '
                   + recordIds.size() + ' ' + currentStep.objectName + ' records');

        return Database.getQueryLocator(
            'SELECT Id FROM ' + currentStep.objectName + ' WHERE Id IN :recordIds'
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) return;

        System.debug('CascadeDeleteQueueable: deleting ' + scope.size()
                   + ' ' + currentStep.objectName + ' records');
        Database.delete(scope, false);
    }

    public void finish(Database.BatchableContext context) {
        System.debug('CascadeDeleteQueueable: finished ' + currentStep.objectName);

        // Chain the next step if any remain
        if (!remainingSteps.isEmpty()) {
            DeletionStep nextStep = remainingSteps.remove(0);
            System.debug('CascadeDeleteQueueable: chaining → ' + nextStep.objectName
                       + ' (' + remainingSteps.size() + ' remaining)');
            Database.executeBatch(
                new CascadeDeleteQueueable(nextStep, remainingSteps),
                200
            );
        } else {
            System.debug('CascadeDeleteQueueable: all deletion steps completed');
        }
    }
}