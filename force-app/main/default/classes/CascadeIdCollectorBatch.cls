/**
 * Batch class that collects child record IDs one relationship at a time.
 * Uses Database.getQueryLocator in start() to support up to 50 million rows.
 * After all relationships are collected, starts the CascadeDeleteQueueable chain.
 */
public class CascadeIdCollectorBatch implements Database.Batchable<SObject>, Database.Stateful {

    private List<CascadeDeleteHelper.ChildRelInfo> allRelations;
    private CascadeDeleteHelper.ChildRelInfo       currentRel;
    private Map<String, List<Id>>                  collectedIds;
    private String                                 rootObjectName;
    private List<Id>                               rootParentIds;

    // Per-relationship accumulator (Stateful across execute() calls)
    private List<Id> batchIds;

    public CascadeIdCollectorBatch(
        List<CascadeDeleteHelper.ChildRelInfo> allRelations,
        Map<String, List<Id>> collectedIds,
        String rootObjectName,
        List<Id> rootParentIds
    ) {
        this.allRelations   = allRelations;
        this.collectedIds   = collectedIds;
        this.rootObjectName = rootObjectName;
        this.rootParentIds  = rootParentIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        currentRel = null;
        batchIds   = new List<Id>();
        List<Id> parentIds = null;

        // Pop relationships until we find one with valid parent IDs
        while (!allRelations.isEmpty()) {
            CascadeDeleteHelper.ChildRelInfo candidate = allRelations.remove(0);
            List<Id> candidateParentIds = collectedIds.get(candidate.parentObjectName);

            if (candidateParentIds != null && !candidateParentIds.isEmpty()) {
                currentRel = candidate;
                parentIds  = candidateParentIds;
                break;
            }
            System.debug('CascadeIdCollectorBatch: no parent IDs for '
                       + candidate.parentObjectName + ' — skipping ' + candidate.objectName);
        }

        if (currentRel == null) {
            System.debug('CascadeIdCollectorBatch: no valid relationships to collect');
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        System.debug('CascadeIdCollectorBatch: collecting IDs for ' + currentRel.objectName
                   + ' via ' + currentRel.relationshipField
                   + ' (' + (currentRel.isCascadeDelete ? 'MD' : 'Lookup') + ')');

        return Database.getQueryLocator(
            'SELECT Id FROM ' + currentRel.objectName
            + ' WHERE ' + currentRel.relationshipField + ' IN :parentIds'
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        for (SObject rec : scope) {
            batchIds.add(rec.Id);
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Store collected IDs for this relationship
        if (currentRel != null && !batchIds.isEmpty()) {
            collectedIds.put(currentRel.objectName, batchIds);
            System.debug('CascadeIdCollectorBatch: collected ' + batchIds.size()
                       + ' IDs for ' + currentRel.objectName);
        }

        // Chain to next relationship or start deletion
        if (!allRelations.isEmpty()) {
            Database.executeBatch(new CascadeIdCollectorBatch(
                allRelations, collectedIds, rootObjectName, rootParentIds
            ), 10000);
            System.debug('CascadeIdCollectorBatch: chaining to next relationship');
        } else {
            System.debug('CascadeIdCollectorBatch: all IDs collected — starting deletion chain');
            CascadeDeleteHelper.startDeletionChain(collectedIds, rootObjectName, rootParentIds);
        }
    }
}