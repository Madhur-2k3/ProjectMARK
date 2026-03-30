public class ChildArchiveQueueable implements Queueable {

    // Serializable child metadata — mirrors DataArchiveBatch.ChildMetadata
    public class ChildInfo {
        public String       objectName;
        public String       relationshipField;
        public List<String> fields;
        public Integer      depth;
        public String       parentObjectName;
    }

    // ===================== CONSTANTS =====================
    private static final Integer PARENT_ID_CHUNK_SIZE = Integer.valueOf(Label.PARENT_ID_CHUNK_SIZE);
    private static final Integer MAX_CSV_LENGTH = Integer.valueOf(Label.MAX_CSV_LENGTH);

    // ===================== STATE =====================
    private Id              archiveRecordId;
    private String          archiveRecordName;
    private String          rootObjectName;
    private List<ChildInfo> childrenToProcess;      // sorted by depth — we pop from the front
    private Map<String, List<Id>> collectedIds;     // IDs per object for depth chaining
    private List<Id>        contentDocumentIds;     // accumulate across Queueable chain
    private List<Id>        processedParentIds;     // root parent IDs for deletion

    // ===================== CONSTRUCTOR =====================
    public ChildArchiveQueueable(Id archiveRecordId, String archiveRecordName,
                                  String rootObjectName,
                                  List<ChildInfo> childrenToProcess,
                                  Map<String, List<Id>> collectedIds,
                                  List<Id> contentDocumentIds,
                                  List<Id> processedParentIds) {
        this.archiveRecordId    = archiveRecordId;
        this.archiveRecordName  = archiveRecordName;
        this.rootObjectName     = rootObjectName;
        this.childrenToProcess  = childrenToProcess;
        this.collectedIds       = collectedIds;
        this.contentDocumentIds = contentDocumentIds;
        this.processedParentIds = processedParentIds;
    }

    // ===================== EXECUTE =====================
    // Each execution processes ONE child object, then chains to the next.
    // This gives each child object its own 50K SOQL-row budget.
    public void execute(QueueableContext ctx) {
        try {
            if (childrenToProcess.isEmpty()) {
                finishArchive();
                return;
            }

            // Pop the first child object from the list
            ChildInfo current = childrenToProcess.remove(0);
            System.debug('========== ChildArchiveQueueable ==========');
            System.debug('Processing: ' + current.objectName + ' (depth ' + current.depth + ')');

            processOneChild(current);

            // Chain to next child or finish
            if (!childrenToProcess.isEmpty()) {
                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                    System.enqueueJob(new ChildArchiveQueueable(
                        archiveRecordId, archiveRecordName, rootObjectName,
                        childrenToProcess, collectedIds,
                        contentDocumentIds, processedParentIds
                    ));
                    System.debug('Chained to next child object');
                } else {
                    System.debug('Queueable limit reached — finishing early');
                    finishArchive();
                }
            } else {
                finishArchive();
            }

        } catch (Exception e) {
            System.debug('ERROR in ChildArchiveQueueable: ' + e.getTypeName());
            System.debug('Message: ' + e.getMessage());
            System.debug('Line   : ' + e.getLineNumber());
            System.debug('Stack  : ' + e.getStackTraceString());

            try {
                update new Data_Archive__c(
                    Id        = archiveRecordId,
                    Status__c = 'Error: ' + e.getMessage().abbreviate(255)
                );
            } catch (Exception ex) {
                System.debug('Could not update status: ' + ex.getMessage());
            }
        }
    }

    // ===================== PROCESS ONE CHILD OBJECT =====================
    // Queries child records in parent-ID chunks to control heap usage.
    // Builds CSV inline (no intermediate List<String>).
    private void processOneChild(ChildInfo child) {
        List<Id> parentIds = collectedIds.get(child.parentObjectName);
        if (parentIds == null || parentIds.isEmpty()) {
            System.debug('No parent IDs for ' + child.parentObjectName
                       + ' — skipping ' + child.objectName);
            return;
        }

        String fieldsStr = String.join(child.fields, ', ');
        String header    = String.join(child.fields, ',') + '\n';
        String csvBuffer = header;
        Integer partNum  = 1;
        Integer totalRecords = 0;
        List<Id> childIds = new List<Id>();

        // Process parent IDs in chunks
        for (Integer chunkStart = 0; chunkStart < parentIds.size(); chunkStart += PARENT_ID_CHUNK_SIZE) {
            Integer chunkEnd = Math.min(chunkStart + PARENT_ID_CHUNK_SIZE, parentIds.size());

            List<Id> parentIdChunk = new List<Id>();
            for (Integer i = chunkStart; i < chunkEnd; i++) {
                parentIdChunk.add(parentIds[i]);
            }

            String childQuery = 'SELECT ' + fieldsStr
                             + ' FROM '   + child.objectName
                             + ' WHERE '  + child.relationshipField
                             + ' IN :parentIdChunk';

            List<SObject> records = Database.query(childQuery);
            if (records.isEmpty()) continue;

            totalRecords += records.size();

            // Collect IDs for next depth level
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
        }

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

    // ===================== FINISH ARCHIVE =====================
    // Called after all child objects are processed (or when list is empty).
    // Enqueues ArchivePostProcessQueueable for S3 upload + deletion + status update.
    private void finishArchive() {
        System.debug('========== All children processed ==========');
        System.debug('Total files: ' + contentDocumentIds.size());

        // Update status to Ready for Unarchive first
        update new Data_Archive__c(
            Id        = archiveRecordId,
            Status__c = 'Ready for Unarchive'
        );
        System.debug('Archive status: Ready for Unarchive');

        // Enqueue ArchivePostProcessQueueable for S3 upload + deletion
        // This will set status to 'Completed' after it finishes.
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new ArchivePostProcessQueueable(
                contentDocumentIds,
                archiveRecordId,
                rootObjectName,
                processedParentIds
            ));
            System.debug('ArchivePostProcessQueueable enqueued');
        } else {
            // Fallback: run deletion inline (skip S3 upload)
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

    // ===================== CSV HELPERS =====================

    private void saveCsvFile(String csvData, Integer partNum, String objectType) {
        String fileName = this.archiveRecordName + '-' + objectType
                        + (partNum > 1 ? '-Part' + partNum : '');
        String title    = objectType + (partNum > 1 ? ' Part ' + partNum : '');

        System.debug('Saving: ' + fileName + '.csv ('
                   + (csvData.length() / 1024) + ' KB)');

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

        System.debug('Saved: ' + fileName + '.csv');
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