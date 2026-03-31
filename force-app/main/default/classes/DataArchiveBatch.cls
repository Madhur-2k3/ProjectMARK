/**
 * @description Main batch class for archiving SObject records into CSV files.
 *              Discovers child relationships recursively, builds CSV files for
 *              parent records, and delegates child archival to DataArchiveChildBatch.
 *              Implements Database.Stateful to maintain state across batch chunks.
 */
public class DataArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ===================== CONSTANTS =====================
    private static final Integer MAX_CSV_LENGTH_INT = Integer.valueOf(Label.MAX_CSV_LENGTH);

    // ===================== STATE VARIABLES =====================
    private String objectNameStr;
    private List<String> fieldsList;
    private String soqlQueryStr;
    private Id archiveRecordId;
    private String archiveRecordNameStr;

    // Parent CSV — flush during execute(), don't accumulate unbounded
    private String  currentParentCsvStr;
    private Integer parentPartNumberInt = 1;
    private String  parentHeaderStr;

    // Stores full hierarchy with depth + parent tracking
    private Map<String, ChildMetadata> childMetadataMap = new Map<String, ChildMetadata>();

    private Set<Id>  generatedContentDocIdSet = new Set<Id>();
    private List<Id> processedParentIdsList   = new List<Id>();

    /**
     * @description Inner class that holds metadata for a discovered child object.
     */
    private class ChildMetadata {

        public String       objectName;
        public String       relationshipField;
        public List<String> fields;
        public Integer      depth;
        public String       parentObjectName;

        /**
         * @description Constructs a new ChildMetadata instance.
         * @param objNameStr The child object API name.
         * @param relFieldStr The relationship field API name.
         * @param fieldsList List of accessible field API names.
         * @param depthInt The depth level in the hierarchy.
         * @param parentObjNameStr The parent object API name.
         */
        public ChildMetadata(String objNameStr, String relFieldStr,
                             List<String> fieldsList, Integer depthInt, String parentObjNameStr) {

            this.objectName        = objNameStr;
            this.relationshipField = relFieldStr;
            this.fields            = fieldsList;
            this.depth             = depthInt;
            this.parentObjectName  = parentObjNameStr;
        }
    }

    /**
     * @description Backward-compatible constructor (3 params).
     * @param objectNameStr The API name of the SObject to archive.
     * @param fieldsCsvStr Comma-separated field API names.
     * @param soqlQueryStr The SOQL query to select records.
     */
    public DataArchiveBatch(String objectNameStr, String fieldsCsvStr, String soqlQueryStr) {

        this(objectNameStr, fieldsCsvStr, soqlQueryStr, null, null);
    }

    /**
     * @description Backward-compatible constructor (4 params).
     * @param objectNameStr The API name of the SObject to archive.
     * @param fieldsCsvStr Comma-separated field API names.
     * @param soqlQueryStr The SOQL query to select records.
     * @param archiveNameStr Optional archive record name.
     */
    public DataArchiveBatch(String objectNameStr, String fieldsCsvStr, String soqlQueryStr, String archiveNameStr) {

        this(objectNameStr, fieldsCsvStr, soqlQueryStr, archiveNameStr, null);
    }

    /**
     * @description Full constructor with child object selection.
     * @param objectNameStr The API name of the SObject to archive.
     * @param fieldsCsvStr Comma-separated field API names.
     * @param soqlQueryStr The SOQL query to select records.
     * @param archiveNameStr Optional archive record name.
     * @param selectedChildObjectsList Optional list of child object API names to include.
     */
    public DataArchiveBatch(String objectNameStr, String fieldsCsvStr, String soqlQueryStr,
                            String archiveNameStr, List<String> selectedChildObjectsList) {

        this.objectNameStr       = objectNameStr;
        this.fieldsList          = filterAccessibleFields(objectNameStr, normalizeFields(fieldsCsvStr));
        this.soqlQueryStr        = soqlQueryStr;
        this.archiveRecordNameStr = archiveNameStr;

        this.parentHeaderStr     = String.join(this.fieldsList, ',') + '\n';
        this.currentParentCsvStr = this.parentHeaderStr;

        System.debug('========== DISCOVERING CHAIN ==========');
        discoverChain(this.objectNameStr, 1);
        System.debug('Total objects discovered: ' + childMetadataMap.size());

        if (selectedChildObjectsList != null && !selectedChildObjectsList.isEmpty()) {

            Set<String> allowedSet = new Set<String>(selectedChildObjectsList);
            List<String> toRemoveList = new List<String>();

            for (String objNameStr : childMetadataMap.keySet()) {
                if (!allowedSet.contains(objNameStr)) {
                    toRemoveList.add(objNameStr);
                }
            }

            for (String objNameStr : toRemoveList) {
                childMetadataMap.remove(objNameStr);
            }

            System.debug('After filtering to user selection: ' + childMetadataMap.size() + ' objects');
        }

        System.debug('');
    }

    /**
     * @description Recursively discovers child relationships for a given parent object.
     * @param parentObjNameStr The API name of the parent object.
     * @param depthInt The current depth in the hierarchy.
     */
    private void discoverChain(String parentObjNameStr, Integer depthInt) {

        if (depthInt > Integer.valueOf(Label.MAX_CHAIN_DEPTH)) return;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjNameStr);
        if (objType == null) return;

        List<Schema.ChildRelationship> childRelsList = objType.getDescribe().getChildRelationships();

        for (Schema.ChildRelationship childRel : childRelsList) {

            Schema.DescribeFieldResult fieldDesc = childRel.getField().getDescribe();
            if (fieldDesc.getType() != Schema.DisplayType.REFERENCE) continue;

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            String childObjectNameStr   = childDescribe.getName();
            String relationshipFieldStr = fieldDesc.getName();
            String relationshipNameStr  = childRel.getRelationshipName();

            if (childMetadataMap.containsKey(childObjectNameStr)) continue;

            if (relationshipNameStr == null                   ||
                childObjectNameStr.endsWith('Share')          ||
                childObjectNameStr.endsWith('History')        ||
                childObjectNameStr.endsWith('Feed')           ||
                childObjectNameStr.endsWith('ChangeEvent'))   continue;

            if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) {
                System.debug('Skipping (not accessible): ' + childObjectNameStr);
                continue;
            }

            List<String> childFieldsList = getObjectFields(childObjectNameStr);
            if (childFieldsList.isEmpty()) continue;

            childMetadataMap.put(childObjectNameStr, new ChildMetadata(
                childObjectNameStr,
                relationshipFieldStr,
                childFieldsList,
                depthInt,
                parentObjNameStr
            ));

            String relTypeStr = childRel.isCascadeDelete() ? 'Master-Detail' : 'Lookup';
            System.debug('Found [depth-' + depthInt + '] [' + relTypeStr + ']: ' + childObjectNameStr
                       + ' (parent: ' + parentObjNameStr + ')');

            discoverChain(childObjectNameStr, depthInt + 1);
        }
    }

    /**
     * @description Gets all accessible, createable fields for the given SObject.
     * @param objNameStr The API name of the SObject.
     * @return A list of accessible field API names.
     */
    private List<String> getObjectFields(String objNameStr) {

        List<String> fieldResultList = new List<String>();

        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objNameStr);
            if (objType == null) return fieldResultList;

            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            if (!objDescribe.isAccessible()) return fieldResultList;

            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

            for (String fieldNameStr : fieldMap.keySet()) {

                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldNameStr).getDescribe();

                if (!fieldDescribe.isAccessible())                         continue;
                if (fieldNameStr.endsWith('__pc'))                         continue;
                if (fieldNameStr.equalsIgnoreCase('isdeleted'))            continue;

                if (fieldDescribe.isCreateable()                              ||
                    fieldNameStr.equalsIgnoreCase('id')                        ||
                    fieldNameStr.equalsIgnoreCase('name')                      ||
                    fieldNameStr.equalsIgnoreCase('createddate')               ||
                    fieldNameStr.equalsIgnoreCase('createdbyid')               ||
                    fieldNameStr.equalsIgnoreCase('lastmodifieddate')          ||
                    fieldNameStr.equalsIgnoreCase('lastmodifiedbyid')) {
                    fieldResultList.add(fieldDescribe.getName());
                }
            }
        } catch (Exception ex) {
            System.debug('Error getting fields for ' + objNameStr + ': ' + ex.getMessage());
        }

        return fieldResultList;
    }

    /**
     * @description Starts the batch by creating a Data_Archive__c record and
     *              returning a QueryLocator for the SOQL query.
     * @param batchContext The BatchableContext provided by the platform.
     * @return A Database.QueryLocator for the parent records.
     */
    public Database.QueryLocator start(Database.BatchableContext batchContext) {

        System.debug('========== STARTING DATA ARCHIVE BATCH ==========');

        Data_Archive__c archiveRecord = new Data_Archive__c(
            Parent_Object__c = this.objectNameStr,
            Fields__c        = String.join(this.fieldsList, ','),
            Status__c        = 'Archive In Progress',
            Name             = this.archiveRecordNameStr
        );
        insert archiveRecord;

        archiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archiveRecord.Id LIMIT 1];
        this.archiveRecordId       = archiveRecord.Id;
        this.archiveRecordNameStr  = archiveRecord.Name;

        System.debug('Archive Record : ' + this.archiveRecordNameStr);
        System.debug('Parent Object  : ' + this.objectNameStr);
        System.debug('Chain Objects  : ' + childMetadataMap.size());

        return Database.getQueryLocator(this.soqlQueryStr);
    }

    /**
     * @description Processes each batch chunk of parent records, building CSV content
     *              and flushing to files when the size limit is reached.
     * @param batchContext The BatchableContext provided by the platform.
     * @param scopeList The list of SObject records in this batch chunk.
     */
    public void execute(Database.BatchableContext batchContext, List<SObject> scopeList) {

        if (scopeList.isEmpty()) return;

        System.debug('Processing ' + scopeList.size() + ' parent records');

        for (SObject currentRecord : scopeList) {
            processedParentIdsList.add(currentRecord.Id);
        }

        for (SObject currentRow : scopeList) {

            String lineStr = buildSingleCsvRow(currentRow, this.fieldsList);

            if (lineStr.length() > MAX_CSV_LENGTH_INT) {
                System.debug('Single record exceeds size limit - skipping');
                continue;
            }

            if ((this.currentParentCsvStr.length() + lineStr.length() + 1) > MAX_CSV_LENGTH_INT) {
                saveCsvFile(this.currentParentCsvStr, this.parentPartNumberInt, this.objectNameStr);
                this.parentPartNumberInt++;
                this.currentParentCsvStr = this.parentHeaderStr;
            }

            this.currentParentCsvStr += lineStr + '\n';
        }
    }

    /**
     * @description Finishes the batch by saving remaining parent CSV, then either
     *              starting child batch processing or enqueuing post-processing.
     * @param batchContext The BatchableContext provided by the platform.
     */
    public void finish(Database.BatchableContext batchContext) {

        System.debug('');
        System.debug('========== FINISHING - SAVING PARENT CSV ==========');

        try {
            if (processedParentIdsList.isEmpty()) {
                System.debug('No parent records processed');
                return;
            }

            System.debug('Total parent records : ' + processedParentIdsList.size());

            if (this.currentParentCsvStr != this.parentHeaderStr) {
                saveCsvFile(this.currentParentCsvStr, this.parentPartNumberInt, this.objectNameStr);
                System.debug('Parent CSV saved: ' + this.objectNameStr);
            }

            this.currentParentCsvStr = null;

            if (!childMetadataMap.isEmpty()) {
                startChildBatch();
            } else {
                update new Data_Archive__c(
                    Id        = archiveRecordId,
                    Status__c = 'Ready for Unarchive'
                );

                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                    System.enqueueJob(new ArchivePostProcessQueueable(
                        new List<Id>(generatedContentDocIdSet),
                        archiveRecordId,
                        objectNameStr,
                        processedParentIdsList
                    ));
                    System.debug('ArchivePostProcessQueueable enqueued (no children)');
                } else {
                    CascadeDeleteHelper.deleteParentWithRelations(objectNameStr, processedParentIdsList);
                    update new Data_Archive__c(Id = archiveRecordId, Status__c = 'Completed');
                }
            }

            System.debug('========== FINISH COMPLETED ==========');

        } catch (Exception ex) {
            System.debug('ERROR IN FINISH: ' + ex.getTypeName());
            System.debug('Message  : '       + ex.getMessage());
            System.debug('Line     : '       + ex.getLineNumber());
            System.debug('Stack    : '       + ex.getStackTraceString());

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
     * @description Builds a depth-sorted ChildInfo list and starts DataArchiveChildBatch.
     */
    private void startChildBatch() {

        Map<Integer, List<ChildMetadata>> byDepthMap = new Map<Integer, List<ChildMetadata>>();

        for (ChildMetadata meta : childMetadataMap.values()) {
            if (!byDepthMap.containsKey(meta.depth)) {
                byDepthMap.put(meta.depth, new List<ChildMetadata>());
            }
            byDepthMap.get(meta.depth).add(meta);
        }

        List<Integer> depthsList = new List<Integer>(byDepthMap.keySet());
        depthsList.sort();

        List<DataArchiveChildBatch.ChildInfo> sortedChildInfoList = new List<DataArchiveChildBatch.ChildInfo>();

        for (Integer depthInt : depthsList) {
            for (ChildMetadata meta : byDepthMap.get(depthInt)) {

                DataArchiveChildBatch.ChildInfo info = new DataArchiveChildBatch.ChildInfo();
                info.objectName        = meta.objectName;
                info.relationshipField = meta.relationshipField;
                info.fields            = meta.fields;
                info.depth             = meta.depth;
                info.parentObjectName  = meta.parentObjectName;
                sortedChildInfoList.add(info);
            }
        }

        Map<String, List<Id>> collectedIdsMap = new Map<String, List<Id>>();
        collectedIdsMap.put(this.objectNameStr, processedParentIdsList);

        Database.executeBatch(new DataArchiveChildBatch(
            archiveRecordId,
            archiveRecordNameStr,
            objectNameStr,
            sortedChildInfoList,
            collectedIdsMap,
            new List<Id>(generatedContentDocIdSet),
            processedParentIdsList
        ), 1);

        System.debug('DataArchiveChildBatch started (' + sortedChildInfoList.size() + ' child objects)');
    }

    /**
     * @description Saves CSV data as a ContentVersion file and links it to the archive record.
     * @param csvDataStr The CSV content to save.
     * @param partNumInt The part number for multi-part files.
     * @param objectTypeStr The object API name for file naming.
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
        generatedContentDocIdSet.add(insertedVersion.ContentDocumentId);

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
     * @description Normalizes a comma-separated field string into a list of trimmed field names.
     * @param csvStr The comma-separated field string.
     * @return A list of trimmed, non-blank field names.
     */
    private static List<String> normalizeFields(String csvStr) {

        List<String> normalizedFieldsList = new List<String>();

        for (String fieldStr : csvStr.split(',')) {
            if (!String.isBlank(fieldStr)) normalizedFieldsList.add(fieldStr.trim());
        }

        return normalizedFieldsList;
    }

    /**
     * @description Filters fields to only those accessible by the running user.
     * @param objNameStr The API name of the SObject.
     * @param fieldsList List of field API names to filter.
     * @return A filtered list containing only accessible fields.
     */
    private List<String> filterAccessibleFields(String objNameStr, List<String> fieldsList) {

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objNameStr);
        if (objType == null) return fieldsList;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        List<String> accessibleFieldsList = new List<String>();

        for (String fieldStr : fieldsList) {

            String keyStr = fieldStr.toLowerCase();

            if (fieldMap.containsKey(keyStr) && fieldMap.get(keyStr).getDescribe().isAccessible()) {
                accessibleFieldsList.add(fieldStr);
            } else if (fieldStr.contains('.')) {
                accessibleFieldsList.add(fieldStr);
            } else {
                System.debug('Dropping inaccessible field: ' + fieldStr);
            }
        }

        return accessibleFieldsList;
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