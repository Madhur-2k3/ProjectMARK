public class DataArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ===================== CONSTANTS =====================
    private static final Integer MAX_CSV_LENGTH = Integer.valueOf(Label.MAX_CSV_LENGTH);

    // ===================== STATE VARIABLES =====================
    private String objectName;
    private List<String> fields;
    private String soqlQuery;
    private Id archiveRecordId;
    private String archiveRecordName;

    // Parent CSV — flush during execute(), don't accumulate unbounded
    private String  currentParentCsv;
    private Integer parentPartNumber = 1;
    private String  parentHeader;

    // Stores full hierarchy with depth + parent tracking
    private Map<String, ChildMetadata> childMetadataMap = new Map<String, ChildMetadata>();

    private Set<Id>  generatedContentDocumentIds = new Set<Id>();
    private List<Id> processedParentIds          = new List<Id>();

    // ===================== INNER CLASS =====================
    private class ChildMetadata {
        public String       objectName;
        public String       relationshipField;
        public List<String> fields;
        public Integer      depth;
        public String       parentObjectName;

        public ChildMetadata(String objectName, String relationshipField,
                             List<String> fields, Integer depth, String parentObjectName) {
            this.objectName        = objectName;
            this.relationshipField = relationshipField;
            this.fields            = fields;
            this.depth             = depth;
            this.parentObjectName  = parentObjectName;
        }
    }
    // ===================== CONSTRUCTORS (backward-compatible overloads) =====================
    public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery) {
        this(objectName, fieldsCsv, soqlQuery, null, null);
    }

    public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery, String archiveName) {
        this(objectName, fieldsCsv, soqlQuery, archiveName, null);
    }

    public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery,
                            String archiveName, List<String> selectedChildObjects) {
        this.objectName   = objectName;
        this.fields       = filterAccessibleFields(objectName, normalizeFields(fieldsCsv));
        this.soqlQuery    = soqlQuery;
        this.archiveRecordName = archiveName;

        this.parentHeader     = String.join(this.fields, ',') + '\n';
        this.currentParentCsv = this.parentHeader;

        System.debug('========== DISCOVERING CHAIN ==========');
        discoverChain(this.objectName, 1);
        System.debug('Total objects discovered: ' + childMetadataMap.size());

        // Filter to only user-selected child objects
        if (selectedChildObjects != null && !selectedChildObjects.isEmpty()) {
            Set<String> allowed = new Set<String>(selectedChildObjects);
            List<String> toRemove = new List<String>();
            for (String objName : childMetadataMap.keySet()) {
                if (!allowed.contains(objName)) {
                    toRemove.add(objName);
                }
            }
            for (String objName : toRemove) {
                childMetadataMap.remove(objName);
            }
            System.debug('After filtering to user selection: ' + childMetadataMap.size() + ' objects');
        }
        System.debug('');
    }

    // ===================== RECURSIVE CHAIN DISCOVERY =====================
    private void discoverChain(String parentObjName, Integer depth) {
        if (depth > Integer.valueOf(Label.MAX_CHAIN_DEPTH)) return;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjName);
        if (objType == null) return;

        List<Schema.ChildRelationship> childRels = objType.getDescribe().getChildRelationships();

        for (Schema.ChildRelationship childRel : childRels) {

            // Include both master-detail and lookup relationships
            // Skip non-Reference field types (e.g., indirect lookups)
            Schema.DescribeFieldResult fieldDesc = childRel.getField().getDescribe();
            if (fieldDesc.getType() != Schema.DisplayType.REFERENCE) continue;

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            String childObjectName   = childDescribe.getName();
            String relationshipField = fieldDesc.getName();
            String relationshipName  = childRel.getRelationshipName();

            // Prevent infinite loops
            if (childMetadataMap.containsKey(childObjectName)) continue;

            // Skip system objects
            if (relationshipName == null                    ||
                childObjectName.endsWith('Share')           ||
                childObjectName.endsWith('History')         ||
                childObjectName.endsWith('Feed')            ||
                childObjectName.endsWith('ChangeEvent'))    continue;

            // Skip inaccessible
            if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) {
                System.debug('Skipping (not accessible): ' + childObjectName);
                continue;
            }

            List<String> childFields = getObjectFields(childObjectName);
            if (childFields.isEmpty()) continue;

            childMetadataMap.put(childObjectName, new ChildMetadata(
                childObjectName,
                relationshipField,
                childFields,
                depth,
                parentObjName
            ));

            String relType = childRel.isCascadeDelete() ? 'Master-Detail' : 'Lookup';
            System.debug('Found [depth-' + depth + '] [' + relType + ']: ' + childObjectName
                       + ' (parent: ' + parentObjName + ')');

            // RECURSE: find children of this child
            discoverChain(childObjectName, depth + 1);
        }
    }

    // ===================== GET OBJECT FIELDS =====================
    private List<String> getObjectFields(String objName) {
        List<String> fieldList = new List<String>();
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objName);
            if (objType == null) return fieldList;

            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            if (!objDescribe.isAccessible()) return fieldList;

            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();

                if (!fd.isAccessible())                        continue;
                if (fieldName.endsWith('__pc'))                continue;
                if (fieldName.equalsIgnoreCase('isdeleted'))   continue;

                if (fd.isCreateable()                              ||
                    fieldName.equalsIgnoreCase('id')               ||
                    fieldName.equalsIgnoreCase('name')             ||
                    fieldName.equalsIgnoreCase('createddate')      ||
                    fieldName.equalsIgnoreCase('createdbyid')      ||
                    fieldName.equalsIgnoreCase('lastmodifieddate') ||
                    fieldName.equalsIgnoreCase('lastmodifiedbyid')) {
                    fieldList.add(fd.getName());
                }
            }
        } catch (Exception e) {
            System.debug('Error getting fields for ' + objName + ': ' + e.getMessage());
        }
        return fieldList;
    }

    // ===================== START =====================
    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('========== STARTING DATA ARCHIVE BATCH ==========');

        Data_Archive__c archiveRecord = new Data_Archive__c(
            Parent_Object__c = this.objectName,
            Fields__c        = String.join(this.fields, ','),
            Status__c        = 'Archive In Progress',
            Name             = this.archiveRecordName
        );
        insert archiveRecord;

        archiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archiveRecord.Id LIMIT 1];
        this.archiveRecordId   = archiveRecord.Id;
        this.archiveRecordName = archiveRecord.Name;

        System.debug('Archive Record : ' + this.archiveRecordName);
        System.debug('Parent Object  : ' + this.objectName);
        System.debug('Chain Objects  : ' + childMetadataMap.size());

        return Database.getQueryLocator(this.soqlQuery);
    }

    // ===================== EXECUTE =====================
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope.isEmpty()) return;

        System.debug('Processing ' + scope.size() + ' parent records');

        // Collect parent IDs
        for (SObject record : scope) {
            processedParentIds.add(record.Id);
        }

        // Build parent CSV inline — no intermediate list
        for (SObject row : scope) {
            String line = buildSingleCsvRow(row, this.fields);

            // Skip absurdly large single records
            if (line.length() > MAX_CSV_LENGTH) {
                System.debug('Single record exceeds size limit - skipping');
                continue;
            }

            // Check if adding this line would exceed the limit
            if ((this.currentParentCsv.length() + line.length() + 1) > MAX_CSV_LENGTH) {
                // Flush current buffer to file
                saveCsvFile(this.currentParentCsv, this.parentPartNumber, this.objectName);
                this.parentPartNumber++;
                this.currentParentCsv = this.parentHeader;
            }

            this.currentParentCsv += line + '\n';
        }
    }

    // ===================== FINISH =====================
    // Parent CSV is saved here. Child objects are delegated to ChildArchiveQueueable
    // (one child per Queueable execution) to avoid the 50K SOQL row limit.
    public void finish(Database.BatchableContext bc) {
        System.debug('');
        System.debug('========== FINISHING - SAVING PARENT CSV ==========');

        try {
            if (processedParentIds.isEmpty()) {
                System.debug('No parent records processed');
                return;
            }

            System.debug('Total parent records : ' + processedParentIds.size());

            // 1. Save remaining parent CSV
            if (this.currentParentCsv != this.parentHeader) {
                saveCsvFile(this.currentParentCsv, this.parentPartNumber, this.objectName);
                System.debug('Parent CSV saved: ' + this.objectName);
            }

            // Free parent CSV memory
            this.currentParentCsv = null;

            // 2. Delegate child processing to a CHAINED BATCH
            //    Each child gets its own execute() with fresh 50K row limit.
            //    Batch finish() reliably enqueues ArchivePostProcessQueueable.
            if (!childMetadataMap.isEmpty()) {
                startChildBatch();
            } else {
                // No children — enqueue ArchivePostProcessQueueable directly
                update new Data_Archive__c(
                    Id        = archiveRecordId,
                    Status__c = 'Ready for Unarchive'
                );

                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                    System.enqueueJob(new ArchivePostProcessQueueable(
                        new List<Id>(generatedContentDocumentIds),
                        archiveRecordId,
                        objectName,
                        processedParentIds
                    ));
                    System.debug('ArchivePostProcessQueueable enqueued (no children)');
                } else {
                    CascadeDeleteHelper.deleteParentWithRelations(objectName, processedParentIds);
                    update new Data_Archive__c(Id = archiveRecordId, Status__c = 'Completed');
                }
            }

            System.debug('========== FINISH COMPLETED ==========');

        } catch (Exception e) {
            System.debug('ERROR IN FINISH: ' + e.getTypeName());
            System.debug('Message  : '       + e.getMessage());
            System.debug('Line     : '       + e.getLineNumber());
            System.debug('Stack    : '       + e.getStackTraceString());

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

    // ===================== START CHILD BATCH =====================
    // Builds a depth-sorted ChildInfo list and starts DataArchiveChildBatch.
    // Batch scope = 1: each execute() processes ONE child object.
    private void startChildBatch() {
        // Group by depth and sort
        Map<Integer, List<ChildMetadata>> byDepth = new Map<Integer, List<ChildMetadata>>();
        for (ChildMetadata meta : childMetadataMap.values()) {
            if (!byDepth.containsKey(meta.depth)) {
                byDepth.put(meta.depth, new List<ChildMetadata>());
            }
            byDepth.get(meta.depth).add(meta);
        }

        List<Integer> depths = new List<Integer>(byDepth.keySet());
        depths.sort();

        // Build sorted ChildInfo list
        List<DataArchiveChildBatch.ChildInfo> sortedChildren = new List<DataArchiveChildBatch.ChildInfo>();
        for (Integer depth : depths) {
            for (ChildMetadata meta : byDepth.get(depth)) {
                DataArchiveChildBatch.ChildInfo info = new DataArchiveChildBatch.ChildInfo();
                info.objectName        = meta.objectName;
                info.relationshipField = meta.relationshipField;
                info.fields            = meta.fields;
                info.depth             = meta.depth;
                info.parentObjectName  = meta.parentObjectName;
                sortedChildren.add(info);
            }
        }

        // Seed collectedIds with root parent IDs
        Map<String, List<Id>> collectedIds = new Map<String, List<Id>>();
        collectedIds.put(this.objectName, processedParentIds);

        // Start child batch — scope = 1 means one child object per execute()
        Database.executeBatch(new DataArchiveChildBatch(
            archiveRecordId,
            archiveRecordName,
            objectName,
            sortedChildren,
            collectedIds,
            new List<Id>(generatedContentDocumentIds),
            processedParentIds
        ), 2000);

        System.debug('DataArchiveChildBatch started (' + sortedChildren.size() + ' child objects)');
    }

    // ===================== SAVE CSV FILE =====================
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
        generatedContentDocumentIds.add(inserted.ContentDocumentId);

        insert new ContentDocumentLink(
            ContentDocumentId = inserted.ContentDocumentId,
            LinkedEntityId    = this.archiveRecordId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        System.debug('Saved: ' + fileName + '.csv');
    }

    // ===================== HELPERS =====================

    // Build a single CSV row directly from an SObject — no intermediate List needed
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

    private static List<String> normalizeFields(String csv) {
        List<String> fields = new List<String>();
        for (String f : csv.split(',')) {
            if (!String.isBlank(f)) fields.add(f.trim());
        }
        return fields;
    }

    // Filter parent fields to only those the running user can actually read
    private List<String> filterAccessibleFields(String objName, List<String> fields) {
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objName);
        if (objType == null) return fields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        List<String> accessible = new List<String>();

        for (String f : fields) {
            String key = f.toLowerCase();
            if (fieldMap.containsKey(key) && fieldMap.get(key).getDescribe().isAccessible()) {
                accessible.add(f);
            } else if (f.contains('.')) {
                // Relationship fields (e.g. Owner.Name) — keep them; they'll fail
                // gracefully in buildSingleCsvRow if parent is null
                accessible.add(f);
            } else {
                System.debug('Dropping inaccessible field: ' + f);
            }
        }
        return accessible;
    }

    private static String escapeCsv(String v) {
        String s = v.replace('"', '""');
        return (s.contains(',') || s.contains('\n') || s.contains('"'))
            ? '"' + s + '"' : s;
    }
}