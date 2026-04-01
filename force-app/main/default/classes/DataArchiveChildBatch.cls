/**
 * @description Batch class that processes child objects for archival.
 *              Each execute() call handles ONE child object with its own governor limits.
 *              After all children are processed, enqueues ArchivePostProcessQueueable.
 */
public class DataArchiveChildBatch implements Database.Batchable<String>, Database.Stateful {

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

    private static final Integer MAX_CSV_LENGTH_INT = Integer.valueOf(Label.MAX_CSV_LENGTH);

    private Id              archiveRecordId;
    private String          archiveRecordNameStr;
    private String          rootObjectNameStr;
    private List<ChildInfo> sortedChildrenList;
    private Map<String, List<Id>> collectedIdsMap;
    private List<Id>        contentDocumentIdsList;
    private List<Id>        processedParentIdsList;

    /**
     * @description Constructs a new DataArchiveChildBatch.
     * @param archiveRecordId The Data_Archive__c record ID.
     * @param archiveRecordNameStr The archive record's auto-number name.
     * @param rootObjectNameStr The root parent object API name.
     * @param sortedChildrenList Depth-sorted list of child object metadata.
     * @param collectedIdsMap Map of object names to their parent record IDs.
     * @param contentDocumentIdsList Accumulated ContentDocument IDs from parent CSV.
     * @param processedParentIdsList Root parent record IDs for eventual deletion.
     */
    public DataArchiveChildBatch(Id archiveRecordId, String archiveRecordNameStr,
                                  String rootObjectNameStr,
                                  List<ChildInfo> sortedChildrenList,
                                  Map<String, List<Id>> collectedIdsMap,
                                  List<Id> contentDocumentIdsList,
                                  List<Id> processedParentIdsList) {

        this.archiveRecordId       = archiveRecordId;
        this.archiveRecordNameStr  = archiveRecordNameStr;
        this.rootObjectNameStr     = rootObjectNameStr;
        this.sortedChildrenList    = sortedChildrenList;
        this.collectedIdsMap       = collectedIdsMap;
        this.contentDocumentIdsList = contentDocumentIdsList;
        this.processedParentIdsList = processedParentIdsList;
    }

    /**
     * @description Returns child object names as an iterable. Batch scope = 1
     *              means each execute() handles ONE child object.
     * @param batchContext The BatchableContext provided by the platform.
     * @return An iterable of child object API names.
     */
    public Iterable<String> start(Database.BatchableContext batchContext) {

        List<String> namesList = new List<String>();

        for (ChildInfo childInfo : sortedChildrenList) {
            namesList.add(childInfo.objectName);
        }

        System.debug('DataArchiveChildBatch: starting with ' + namesList.size() + ' child objects');
        return namesList;
    }

    /**
     * @description Processes ONE child object per execute call.
     * @param batchContext The BatchableContext provided by the platform.
     * @param objectNamesList List of object names to process (typically size 1).
     */
    public void execute(Database.BatchableContext batchContext, List<String> objectNamesList) {

        for (String objNameStr : objectNamesList) {

            ChildInfo child = findChild(objNameStr);
            if (child == null) continue;

            System.debug('Processing child: ' + child.objectName + ' (depth ' + child.depth + ')');
            processOneChild(child);
        }
    }

    /**
     * @description After ALL children are processed, updates status and enqueues deletion.
     * @param batchContext The BatchableContext provided by the platform.
     */
    public void finish(Database.BatchableContext batchContext) {

        System.debug('DataArchiveChildBatch: all children processed');
        System.debug('Total files: ' + contentDocumentIdsList.size());

        update new Data_Archive__c(
            Id        = archiveRecordId,
            Status__c = 'Ready for Unarchive'
        );

        Database.executeBatch(
            new ArchivePostProcessQueueable(
                contentDocumentIdsList,
                archiveRecordId,
                rootObjectNameStr,
                processedParentIdsList
            ),
            1
        );
        System.debug('ArchivePostProcessQueueable batch started');
    }

    /**
     * @description Finds a ChildInfo by object name from the sorted list.
     * @param objNameStr The object API name to find.
     * @return The matching ChildInfo, or null if not found.
     */
    private ChildInfo findChild(String objNameStr) {

        for (ChildInfo childInfo : sortedChildrenList) {
            if (childInfo.objectName == objNameStr) return childInfo;
        }

        return null;
    }

    /**
     * @description Processes a single child object: queries records, builds CSV, saves files.
     * @param child The ChildInfo metadata for the child object to process.
     */
    private void processOneChild(ChildInfo child) {

        List<Id> parentIdsList = collectedIdsMap.get(child.parentObjectName);

        if (parentIdsList == null || parentIdsList.isEmpty()) {
            System.debug('No parent IDs for ' + child.parentObjectName + ' — skipping');
            return;
        }

        String fieldsStr = String.join(child.fields, ', ');
        String headerStr = String.join(child.fields, ',') + '\n';
        String csvBufferStr = headerStr;
        Integer partNumInt  = 1;
        Integer totalRecordsInt = 0;
        List<Id> childIdsList = new List<Id>();

        String childQueryStr = 'SELECT ' + fieldsStr
                         + ' FROM '   + child.objectName
                         + ' WHERE '  + child.relationshipField
                         + ' IN :parentIdsList';

        List<SObject> recordsList = Database.query(childQueryStr);

        if (recordsList.isEmpty()) {
            System.debug('No records found — skipping CSV');
            return;
        }

        totalRecordsInt = recordsList.size();

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
     * @description Saves CSV data as a ContentVersion and links it to the archive record.
     * @param csvDataStr The CSV content to save.
     * @param partNumInt The part number for multi-part files.
     * @param objectTypeStr The child object API name for file naming.
     */
    private void saveCsvFile(String csvDataStr, Integer partNumInt, String objectTypeStr) {

        String fileNameStr = this.archiveRecordNameStr + '-' + objectTypeStr
                        + (partNumInt > 1 ? '-Part' + partNumInt : '');
        String titleStr    = objectTypeStr + (partNumInt > 1 ? ' Part ' + partNumInt : '');

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

        System.debug('Saved: ' + fileNameStr + '.csv (' + (csvDataStr.length() / 1024) + ' KB)');
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