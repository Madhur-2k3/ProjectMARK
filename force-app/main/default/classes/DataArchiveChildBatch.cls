public class DataArchiveChildBatch implements Database.Batchable<String>, Database.Stateful {

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

    public DataArchiveChildBatch(Id archiveRecordId, String archiveRecordName,
                                  String rootObjectName,
                                  List<ChildInfo> sortedChildren,
                                  Map<String, List<Id>> collectedIds,
                                  List<Id> contentDocumentIds,
                                  List<Id> processedParentIds) {
        this.archiveRecordId    = archiveRecordId;
        this.archiveRecordName  = archiveRecordName;
        this.rootObjectName     = rootObjectName;
        this.sortedChildren     = sortedChildren;
        this.collectedIds       = collectedIds;
        this.contentDocumentIds = contentDocumentIds;
        this.processedParentIds = processedParentIds;
    }

    // Return child object names as iterable — batch scope = 1 means
    // each execute() handles ONE child object with its own governor limits.
    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> names = new List<String>();
        for (ChildInfo ci : sortedChildren) {
            names.add(ci.objectName);
        }
        System.debug('DataArchiveChildBatch: starting with ' + names.size() + ' child objects');
        return names;
    }

    // Process ONE child object per execute call.
    // Each call gets a fresh 50K SOQL row limit.
    public void execute(Database.BatchableContext bc, List<String> objectNames) {
        for (String objName : objectNames) {
            ChildInfo child = findChild(objName);
            if (child == null) continue;

            System.debug('Processing child: ' + child.objectName + ' (depth ' + child.depth + ')');
            processOneChild(child);
        }
    }

    // After ALL children are processed, update status and enqueue deletion.
    // Batch finish() can ALWAYS reliably enqueue a Queueable — no chaining issues.
    public void finish(Database.BatchableContext bc) {
        System.debug('DataArchiveChildBatch: all children processed');
        System.debug('Total files: ' + contentDocumentIds.size());

        update new Data_Archive__c(
            Id        = archiveRecordId,
            Status__c = 'Ready for Unarchive'
        );

        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new ArchivePostProcessQueueable(
                contentDocumentIds,
                archiveRecordId,
                rootObjectName,
                processedParentIds
            ));
            System.debug('ArchivePostProcessQueueable enqueued');
        } else {
            System.debug('Queueable limit reached — running deletion inline');
            if (!processedParentIds.isEmpty()) {
                CascadeDeleteHelper.deleteParentWithRelations(rootObjectName, processedParentIds);
            }
            update new Data_Archive__c(
                Id        = archiveRecordId,
                Status__c = 'Completed'
            );
        }
    }

    // ===================== HELPERS =====================

    private ChildInfo findChild(String objName) {
        for (ChildInfo ci : sortedChildren) {
            if (ci.objectName == objName) return ci;
        }
        return null;
    }

    private void processOneChild(ChildInfo child) {
        List<Id> parentIds = collectedIds.get(child.parentObjectName);
        if (parentIds == null || parentIds.isEmpty()) {
            System.debug('No parent IDs for ' + child.parentObjectName + ' — skipping');
            return;
        }

        String fieldsStr = String.join(child.fields, ', ');
        String header    = String.join(child.fields, ',') + '\n';
        String csvBuffer = header;
        Integer partNum  = 1;
        Integer totalRecords = 0;
        List<Id> childIds = new List<Id>();

        // Query all child records for these parent IDs
        String childQuery = 'SELECT ' + fieldsStr
                         + ' FROM '   + child.objectName
                         + ' WHERE '  + child.relationshipField
                         + ' IN :parentIds';

        List<SObject> records = Database.query(childQuery);
        if (records.isEmpty()) {
            System.debug('No records found — skipping CSV');
            return;
        }

        totalRecords = records.size();

        for (SObject rec : records) {
            childIds.add(rec.Id);
        }

        // Build CSV inline
        for (SObject row : records) {
            String line = buildSingleCsvRow(row, child.fields);

            if ((csvBuffer.length() + line.length() + 1) > MAX_CSV_LENGTH) {
                saveCsvFile(csvBuffer, partNum, child.objectName);
                partNum++;
                csvBuffer = header;
            }

            csvBuffer += line + '\n';
        }

        records = null; // help GC

        // Save remaining buffer
        if (csvBuffer.length() > header.length()) {
            saveCsvFile(csvBuffer, partNum, child.objectName);
        }

        // Store IDs for next depth level
        if (!childIds.isEmpty()) {
            collectedIds.put(child.objectName, childIds);
            System.debug('Stored ' + childIds.size() + ' IDs for ' + child.objectName);
        }

        System.debug('Done: ' + child.objectName + ' (' + totalRecords
                   + ' records, ' + partNum + ' part(s))');
    }

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