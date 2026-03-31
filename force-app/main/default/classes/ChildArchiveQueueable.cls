/**
 * @description Queueable class that processes child objects for archival one at a time.
 *              Each execution processes ONE child object, then chains to the next.
 *              Gives each child object its own 50K SOQL-row budget.
 */
public class ChildArchiveQueueable implements Queueable {

    /**
     * @description Serializable child metadata — mirrors DataArchiveBatch.ChildMetadata.
     */
    public class ChildInfo {

        public String       objectName;
        public String       relationshipField;
        public List<String> fields;
        public Integer      depth;
        public String       parentObjectName;
    }

    // ===================== CONSTANTS =====================
    private static final Integer PARENT_ID_CHUNK_SIZE_INT = Integer.valueOf(Label.PARENT_ID_CHUNK_SIZE);
    private static final Integer MAX_CSV_LENGTH_INT = Integer.valueOf(Label.MAX_CSV_LENGTH);

    // ===================== STATE =====================
    private Id              archiveRecordId;
    private String          archiveRecordNameStr;
    private String          rootObjectNameStr;
    private List<ChildInfo> childrenToProcessList;
    private Map<String, List<Id>> collectedIdsMap;
    private List<Id>        contentDocumentIdsList;
    private List<Id>        processedParentIdsList;

    /**
     * @description Constructs a new ChildArchiveQueueable.
     * @param archiveRecordId The Data_Archive__c record ID.
     * @param archiveRecordNameStr The archive record's auto-number name.
     * @param rootObjectNameStr The root parent object API name.
     * @param childrenToProcessList Depth-sorted list of child metadata to process.
     * @param collectedIdsMap Map of object names to parent IDs for depth chaining.
     * @param contentDocumentIdsList Accumulated ContentDocument IDs.
     * @param processedParentIdsList Root parent record IDs for deletion.
     */
    public ChildArchiveQueueable(Id archiveRecordId, String archiveRecordNameStr,
                                  String rootObjectNameStr,
                                  List<ChildInfo> childrenToProcessList,
                                  Map<String, List<Id>> collectedIdsMap,
                                  List<Id> contentDocumentIdsList,
                                  List<Id> processedParentIdsList) {

        this.archiveRecordId       = archiveRecordId;
        this.archiveRecordNameStr  = archiveRecordNameStr;
        this.rootObjectNameStr     = rootObjectNameStr;
        this.childrenToProcessList = childrenToProcessList;
        this.collectedIdsMap       = collectedIdsMap;
        this.contentDocumentIdsList = contentDocumentIdsList;
        this.processedParentIdsList = processedParentIdsList;
    }

    /**
     * @description Processes ONE child object, then chains to the next.
     * @param queueableContext The QueueableContext provided by the platform.
     */
    public void execute(QueueableContext queueableContext) {

        try {
            if (childrenToProcessList.isEmpty()) {
                finishArchive();
                return;
            }

            ChildInfo currentChild = childrenToProcessList.remove(0);
            System.debug('========== ChildArchiveQueueable ==========');
            System.debug('Processing: ' + currentChild.objectName + ' (depth ' + currentChild.depth + ')');

            processOneChild(currentChild);

            if (!childrenToProcessList.isEmpty()) {
                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                    System.enqueueJob(new ChildArchiveQueueable(
                        archiveRecordId, archiveRecordNameStr, rootObjectNameStr,
                        childrenToProcessList, collectedIdsMap,
                        contentDocumentIdsList, processedParentIdsList
                    ));
                    System.debug('Chained to next child object');
                } else {
                    System.debug('Queueable limit reached — finishing early');
                    finishArchive();
                }
            } else {
                finishArchive();
            }

        } catch (Exception ex) {
            System.debug('ERROR in ChildArchiveQueueable: ' + ex.getTypeName());
            System.debug('Message: ' + ex.getMessage());
            System.debug('Line   : ' + ex.getLineNumber());
            System.debug('Stack  : ' + ex.getStackTraceString());

            try {
                update new Data_Archive__c(
                    Id        = archiveRecordId,
                    Status__c = 'Error: ' + ex.getMessage().abbreviate(255)
                );
            } catch (Exception innerException) {
                System.debug('Could not update status: ' + innerException.getMessage());
            }
        }
    }

    /**
     * @description Processes a single child object: queries records in chunks,
     *              builds CSV inline, and saves files.
     * @param child The ChildInfo metadata for the child object to process.
     */
    private void processOneChild(ChildInfo child) {

        List<Id> parentIdsList = collectedIdsMap.get(child.parentObjectName);

        if (parentIdsList == null || parentIdsList.isEmpty()) {
            System.debug('No parent IDs for ' + child.parentObjectName
                       + ' — skipping ' + child.objectName);
            return;
        }

        String fieldsStr = String.join(child.fields, ', ');
        String headerStr = String.join(child.fields, ',') + '\n';
        String csvBufferStr = headerStr;
        Integer partNumInt  = 1;
        Integer totalRecordsInt = 0;
        List<Id> childIdsList = new List<Id>();

        for (Integer chunkStartInt = 0; chunkStartInt < parentIdsList.size(); chunkStartInt += PARENT_ID_CHUNK_SIZE_INT) {

            Integer chunkEndInt = Math.min(chunkStartInt + PARENT_ID_CHUNK_SIZE_INT, parentIdsList.size());

            List<Id> parentIdChunkList = new List<Id>();

            for (Integer idIndex = chunkStartInt; idIndex < chunkEndInt; idIndex++) {
                parentIdChunkList.add(parentIdsList[idIndex]);
            }

            String childQueryStr = 'SELECT ' + fieldsStr
                             + ' FROM '   + child.objectName
                             + ' WHERE '  + child.relationshipField
                             + ' IN :parentIdChunkList';

            List<SObject> recordsList = Database.query(childQueryStr);
            if (recordsList.isEmpty()) continue;

            totalRecordsInt += recordsList.size();

            for (SObject currentRecord : recordsList) {
                childIdsList.add(currentRecord.Id);
            }

            for (SObject currentRow : recordsList) {

                String lineStr = buildSingleCsvRow(currentRow, child.fields);

                if ((csvBufferStr.length() + lineStr.length() + 1) > MAX_CSV_LENGTH_INT) {
                    saveCsvFile(csvBufferStr, partNumInt, child.objectName);
                    partNumInt++;
                    csvBufferStr = headerStr;
                }

                csvBufferStr += lineStr + '\n';
            }

            recordsList = null; // help GC
        }

        if (csvBufferStr.length() > headerStr.length()) {
            saveCsvFile(csvBufferStr, partNumInt, child.objectName);
        }

        if (!childIdsList.isEmpty()) {
            collectedIdsMap.put(child.objectName, childIdsList);
            System.debug('Stored ' + childIdsList.size() + ' IDs for ' + child.objectName);
        }

        System.debug('Done: ' + child.objectName + ' (' + totalRecordsInt
                   + ' records, ' + partNumInt + ' part(s))');
    }

    /**
     * @description Called after all child objects are processed.
     *              Updates archive status and enqueues ArchivePostProcessQueueable.
     */
    private void finishArchive() {

        System.debug('========== All children processed ==========');
        System.debug('Total files: ' + contentDocumentIdsList.size());

        update new Data_Archive__c(
            Id        = archiveRecordId,
            Status__c = 'Ready for Unarchive'
        );
        System.debug('Archive status: Ready for Unarchive');

        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new ArchivePostProcessQueueable(
                contentDocumentIdsList,
                archiveRecordId,
                rootObjectNameStr,
                processedParentIdsList
            ));
            System.debug('ArchivePostProcessQueueable enqueued');
        } else {
            System.debug('Queueable limit reached — running deletion inline');
            if (!processedParentIdsList.isEmpty()) {
                CascadeDeleteHelper.deleteParentWithRelations(rootObjectNameStr, processedParentIdsList);
            }
            update new Data_Archive__c(
                Id        = archiveRecordId,
                Status__c = 'Completed'
            );
        }
    }

    /**
     * @description Saves CSV data as a ContentVersion and links it to the archive record.
     * @param csvDataStr The CSV string content.
     * @param partNumInt The part number for multi-part files.
     * @param objectTypeStr The child object API name for file naming.
     */
    private void saveCsvFile(String csvDataStr, Integer partNumInt, String objectTypeStr) {

        String fileNameStr = this.archiveRecordNameStr + '-' + objectTypeStr
                        + (partNumInt > 1 ? '-Part' + partNumInt : '');
        String titleStr    = objectTypeStr + (partNumInt > 1 ? ' Part ' + partNumInt : '');

        System.debug('Saving: ' + fileNameStr + '.csv ('
                   + (csvDataStr.length() / 1024) + ' KB)');

        ContentVersion contentVersion = new ContentVersion(
            Title        = titleStr,
            PathOnClient = fileNameStr + '.csv',
            Description  = objectTypeStr + ' - ' + this.archiveRecordNameStr,
            VersionData  = Blob.valueOf(csvDataStr)
        );
        insert contentVersion;

        ContentVersion insertedVersion = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1
        ];
        contentDocumentIdsList.add(insertedVersion.ContentDocumentId);

        insert new ContentDocumentLink(
            ContentDocumentId = insertedVersion.ContentDocumentId,
            LinkedEntityId    = this.archiveRecordId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        System.debug('Saved: ' + fileNameStr + '.csv');
    }

    /**
     * @description Builds a single CSV row from an SObject record.
     * @param row The SObject record to convert.
     * @param fieldsList List of field API names for column order.
     * @return A comma-separated string representing the CSV row.
     */
    private static String buildSingleCsvRow(SObject row, List<String> fieldsList) {

        List<String> colsList = new List<String>();

        for (String fieldStr : fieldsList) {

            Object value;

            if (fieldStr.contains('.')) {
                List<String> partsList = fieldStr.split('\\\\\\.');
                SObject parentRecord = row.getSObject(partsList[0]);
                value = parentRecord != null ? parentRecord.get(partsList[1]) : null;
            } else {
                value = row.get(fieldStr);
            }

            colsList.add(escapeCsv(value == null ? '' : String.valueOf(value)));
        }

        return String.join(colsList, ',');
    }

    /**
     * @description Escapes a string value for CSV formatting.
     * @param valueStr The string value to escape.
     * @return The CSV-escaped string.
     */
    private static String escapeCsv(String valueStr) {

        String escapedStr = valueStr.replace('"', '""');

        return (escapedStr.contains(',') || escapedStr.contains('\n') || escapedStr.contains('"'))
            ? '"' + escapedStr + '"' : escapedStr;
    }
}