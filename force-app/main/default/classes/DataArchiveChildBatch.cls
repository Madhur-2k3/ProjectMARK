public class DataArchiveChildBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Serializable child metadata
    public class ChildInfo {
        public String       objectName;
        public String       relationshipField;
        public List<String> fields;
        public Integer      depth;
        public String       parentObjectName;
    }

    private static final Integer MAX_CSV_LENGTH = Integer.valueOf(Label.MAX_CSV_LENGTH);

    private Id              archiveRecordId;
    private String          archiveRecordName;
    private String          rootObjectName;
    private List<ChildInfo> sortedChildren;
    private Map<String, List<Id>> collectedIds;
    private List<Id>        contentDocumentIds;
    private List<Id>        processedParentIds;
    private Boolean         deleteAfterArchive;
    private String          storageProviderName;

    // Per-child state — reset in start(), accumulated across execute() via Stateful
    private ChildInfo currentChild;
    private String    csvHeader;
    private String    csvBuffer;
    private Integer   partNum;
    private Integer   totalRecords;
    private List<Id>  currentChildIds;

    // Backward-compatible constructor (defaults to delete)
    public DataArchiveChildBatch(Id archiveRecordId, String archiveRecordName,
                                  String rootObjectName,
                                  List<ChildInfo> sortedChildren,
                                  Map<String, List<Id>> collectedIds,
                                  List<Id> contentDocumentIds,
                                  List<Id> processedParentIds) {
        this(archiveRecordId, archiveRecordName, rootObjectName, sortedChildren,
             collectedIds, contentDocumentIds, processedParentIds, true, null);
    }

    // Constructor with delete option
    public DataArchiveChildBatch(Id archiveRecordId, String archiveRecordName,
                                  String rootObjectName,
                                  List<ChildInfo> sortedChildren,
                                  Map<String, List<Id>> collectedIds,
                                  List<Id> contentDocumentIds,
                                  List<Id> processedParentIds,
                                  Boolean deleteAfterArchive) {
        this(archiveRecordId, archiveRecordName, rootObjectName, sortedChildren,
             collectedIds, contentDocumentIds, processedParentIds, deleteAfterArchive, null);
    }

    // Full constructor with provider selection
    public DataArchiveChildBatch(Id archiveRecordId, String archiveRecordName,
                                  String rootObjectName,
                                  List<ChildInfo> sortedChildren,
                                  Map<String, List<Id>> collectedIds,
                                  List<Id> contentDocumentIds,
                                  List<Id> processedParentIds,
                                  Boolean deleteAfterArchive,
                                  String storageProviderName) {
        this.archiveRecordId    = archiveRecordId;
        this.archiveRecordName  = archiveRecordName;
        this.rootObjectName     = rootObjectName;
        this.sortedChildren     = sortedChildren;
        this.collectedIds       = collectedIds;
        this.contentDocumentIds = contentDocumentIds;
        this.processedParentIds = processedParentIds;
        this.deleteAfterArchive = deleteAfterArchive != null ? deleteAfterArchive : true;
        this.storageProviderName = storageProviderName;
    }

    /**
     * start() — getQueryLocator here supports up to 50 MILLION rows.
     * Pops the first child with valid parent IDs and builds its query.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        currentChild = null;
        List<Id> parentIds = null;

        // Pop children until we find one with valid parent IDs
        while (!sortedChildren.isEmpty()) {
            ChildInfo candidate = sortedChildren.remove(0);
            List<Id> candidateParentIds = collectedIds.get(candidate.parentObjectName);

            if (candidateParentIds != null && !candidateParentIds.isEmpty()) {
                currentChild = candidate;
                parentIds    = candidateParentIds;
                break;
            }
            System.debug('DataArchiveChildBatch: no parent IDs for '
                       + candidate.parentObjectName + ' — skipping ' + candidate.objectName);
        }

        if (currentChild == null) {
            System.debug('DataArchiveChildBatch: no valid children to process');
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        // Initialize per-child CSV state
        csvHeader       = String.join(currentChild.fields, ',') + '\n';
        csvBuffer       = csvHeader;
        partNum         = 1;
        totalRecords    = 0;
        currentChildIds = new List<Id>();

        String fieldsStr  = String.join(currentChild.fields, ', ');
        String childQuery = 'SELECT ' + fieldsStr
                         + ' FROM '   + currentChild.objectName
                         + ' WHERE '  + currentChild.relationshipField
                         + ' IN :parentIds';

        System.debug('DataArchiveChildBatch: starting child ' + currentChild.objectName
                   + ' (depth ' + currentChild.depth + '), remaining: ' + sortedChildren.size());

        return Database.getQueryLocator(childQuery);
    }

    /**
     * execute() — Process a batch of child records.
     * Builds CSV rows and collects child IDs for depth chaining.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (currentChild == null || scope.isEmpty()) return;

        for (SObject row : scope) {
            totalRecords++;
            currentChildIds.add(row.Id);

            String line = buildSingleCsvRow(row, currentChild.fields);

            if ((csvBuffer.length() + line.length() + 1) > MAX_CSV_LENGTH) {
                saveCsvFile(csvBuffer, partNum, currentChild.objectName);
                partNum++;
                csvBuffer = csvHeader;
            }

            csvBuffer += line + '\n';
        }
    }

    /**
     * finish() — Save remaining CSV, store child IDs, then chain to next
     * child batch or finalize the archive.
     */
    public void finish(Database.BatchableContext bc) {
        // Save remaining CSV buffer for current child
        if (currentChild != null) {
            if (csvBuffer != null && csvBuffer.length() > csvHeader.length()) {
                saveCsvFile(csvBuffer, partNum, currentChild.objectName);
            }

            if (currentChildIds != null && !currentChildIds.isEmpty()) {
                collectedIds.put(currentChild.objectName, currentChildIds);
                System.debug('Stored ' + currentChildIds.size() + ' IDs for ' + currentChild.objectName);
            }

            System.debug('Done: ' + currentChild.objectName + ' ('
                       + totalRecords + ' records, ' + partNum + ' part(s))');
        }

        // Chain to next child or finalize
        if (!sortedChildren.isEmpty()) {
            Database.executeBatch(new DataArchiveChildBatch(
                archiveRecordId, archiveRecordName, rootObjectName,
                sortedChildren, collectedIds, contentDocumentIds, processedParentIds,
                deleteAfterArchive, storageProviderName
            ), 2000);
            System.debug('DataArchiveChildBatch: chaining to next child');
        } else {
            finalizeArchive();
        }
    }

    // ===================== FINALIZE =====================

    private void finalizeArchive() {
        System.debug('DataArchiveChildBatch: all children processed');
        System.debug('Total files: ' + contentDocumentIds.size());
        System.debug('Delete after archive: ' + this.deleteAfterArchive);

        update new Data_Archive__c(
            Id        = archiveRecordId,
            Status__c = 'Ready for Unarchive'
        );

        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new ArchivePostProcessQueueable(
                contentDocumentIds,
                archiveRecordId,
                rootObjectName,
                processedParentIds,
                this.deleteAfterArchive,
                this.storageProviderName
            ));
            System.debug('ArchivePostProcessQueueable enqueued');
        } else if (this.deleteAfterArchive) {
            System.debug('Queueable limit reached — running deletion inline');
            if (!processedParentIds.isEmpty()) {
                CascadeDeleteHelper.deleteParentWithRelations(rootObjectName, processedParentIds);
            }
            update new Data_Archive__c(
                Id        = archiveRecordId,
                Status__c = 'Completed'
            );
        } else {
            System.debug('Delete after archive disabled — skipping deletion');
            update new Data_Archive__c(
                Id        = archiveRecordId,
                Status__c = 'Completed'
            );
        }
    }

    // ===================== CSV HELPERS =====================

    private void saveCsvFile(String csvData, Integer partNum, String objectType) {
        String fileName = this.archiveRecordName + '-' + objectType
                        + (partNum > 1 ? '-Part' + partNum : '');
        String title    = objectType + (partNum > 1 ? ' Part ' + partNum : '');

        ContentVersion cv = new ContentVersion(
            Title        = title,
            PathOnClient = fileName + '.csv',
            Description  = objectType + ' - ' + this.archiveRecordName,
            VersionData  = Blob.valueOf(csvData)
        );
        insert cv;

        ContentVersion inserted = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ];
        contentDocumentIds.add(inserted.ContentDocumentId);

        insert new ContentDocumentLink(
            ContentDocumentId = inserted.ContentDocumentId,
            LinkedEntityId    = this.archiveRecordId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        System.debug('Saved: ' + fileName + '.csv (' + (csvData.length() / 1024) + ' KB)');
    }

    private static String buildSingleCsvRow(SObject row, List<String> fields) {
        List<String> cols = new List<String>();
        for (String f : fields) {
            Object value;
            if (f.contains('.')) {
                List<String> parts = f.split('\\\\.');
                SObject parent = row.getSObject(parts[0]);
                value = parent != null ? parent.get(parts[1]) : null;
            } else {
                value = row.get(f);
            }
            cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
        }
        return String.join(cols, ',');
    }

    private static String escapeCsv(String v) {
        String s = v.replace('"', '""');
        return (s.contains(',') || s.contains('\n') || s.contains('"'))
            ? '"' + s + '"' : s;
    }
}