// public class DataArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {

//     // ===================== CONSTANTS =====================
//     private static final Integer MAX_CSV_SIZE_BYTES = 6 * 1024 * 10; // 60 KB (6*1024*10)

//     // ===================== STATE VARIABLES =====================
//     private String objectName;
//     private List<String> fields;
//     private String soqlQuery;
//     private Id archiveRecordId;
//     private String archiveRecordName;

//     // CSV accumulation across batches
//     private String currentCsv;
//     private Integer partNumber = 1;
//     private String header;
//     private Set<Id> generatedContentDocumentIds = new Set<Id>();

//     // ===================== CONSTRUCTOR =====================
//     public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery) {
//         this.objectName = objectName;
//         this.fields = normalizeFields(fieldsCsv);
//         this.soqlQuery = soqlQuery;
        
//         // Create header
//         this.header = String.join(this.fields, ',') + '\n';
//         this.currentCsv = this.header;
//     }

//     // ===================== START METHOD =====================
//     public Database.QueryLocator start(Database.BatchableContext bc) {
//         // Create Data Archive record at start
//         Data_Archive__c archiveRecord = new Data_Archive__c(
//             Parent_Object__c = this.objectName,
//             Fields__c = String.join(this.fields, ','),
//             Status__c = 'Archive In Progress'
//         );
//         insert archiveRecord;

//         // Re-query to get auto-number Name
//         archiveRecord = [
//             SELECT Id, Name
//             FROM Data_Archive__c
//             WHERE Id = :archiveRecord.Id
//             LIMIT 1
//         ];

//         this.archiveRecordId = archiveRecord.Id;
//         this.archiveRecordName = archiveRecord.Name;

//         return Database.getQueryLocator(this.soqlQuery);
//     }

//     // ===================== EXECUTE METHOD =====================
//     public void execute(Database.BatchableContext bc, List<SObject> scope) {
//         if (scope.isEmpty()) return;

//         List<String> csvLines = buildCsvLines(scope, this.fields);
        
//         for (String line : csvLines) {
//             // Safety: one record cannot exceed max size
//             if (Blob.valueOf(this.header + line).size() > MAX_CSV_SIZE_BYTES) {
//                 System.debug('Warning: Single record exceeds CSV size limit, skipping.');
//                 continue;
//             }

//             String tentativeCsv = this.currentCsv + line + '\n';

//             // If limit exceeded → save previous CSV
//             if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
//                 saveCsvFile(this.currentCsv, this.partNumber);
//                 this.partNumber++;
//                 this.currentCsv = this.header + line + '\n';
//             } else {
//                 this.currentCsv = tentativeCsv;
//             }
//         }
//     }

//     // ===================== FINISH METHOD =====================
//     public void finish(Database.BatchableContext bc) {
//         // Save any remaining CSV data
//         if (this.currentCsv != this.header) {
//             saveCsvFile(this.currentCsv, this.partNumber);
//         }

//         update new Data_Archive__c(
//             Id = archiveRecordId,
//             Status__c = 'Ready for Unarchive'
//         );

//         List<Id> ids = new List<Id>();
//         for (SObject s : Database.query(this.soqlQuery)) {
//             ids.add(s.Id);
//         }

//         if (!ids.isEmpty()) {
//             Integer queueableUsed = Limits.getQueueableJobs();
//             Integer queueableLimit = Limits.getLimitQueueableJobs();
//             System.debug('DataArchiveBatch.finish queueable usage: ' + queueableUsed + '/' + queueableLimit);

//             if (queueableUsed < queueableLimit) {
//                 System.enqueueJob(
//                     new ArchivePostProcessQueueable(
//                         new List<Id>(generatedContentDocumentIds),
//                         archiveRecordId,
//                         objectName,
//                         ids
//                     )
//                 );
//             } else {
//                 System.debug('DataArchiveBatch.finish: queueable limit reached, running delete inline as fallback and skipping S3 upload.');
//                 CascadeDeleteHelper.deleteParentWithRelations(objectName, ids);
//             }
//         } else if (!generatedContentDocumentIds.isEmpty()) {
//             Integer queueableUsed = Limits.getQueueableJobs();
//             Integer queueableLimit = Limits.getLimitQueueableJobs();
//             System.debug('DataArchiveBatch.finish queueable usage for S3-only post-process: ' + queueableUsed + '/' + queueableLimit);
//             if (queueableUsed < queueableLimit) {
//                 System.enqueueJob(
//                     new ArchivePostProcessQueueable(
//                         new List<Id>(generatedContentDocumentIds),
//                         archiveRecordId,
//                         objectName,
//                         new List<Id>()
//                     )
//                 );
//             } else {
//                 System.debug('DataArchiveBatch.finish: queueable limit reached, skipping S3 upload post-process.');
//             }
//         }
//     }

//     // ===================== HELPER METHODS =====================

//     private void saveCsvFile(String csvData, Integer partNum) {

//         ContentVersion cv = new ContentVersion(
//             Title = this.archiveRecordName,
//             PathOnClient = this.archiveRecordName + '.csv',
//             Description = 'Part ' + partNum,
//             VersionData = Blob.valueOf(csvData)
//         );
//         insert cv;

//         ContentVersion insertedCv = [
//             SELECT ContentDocumentId
//             FROM ContentVersion
//             WHERE Id = :cv.Id
//             LIMIT 1
//         ];

//         generatedContentDocumentIds.add(insertedCv.ContentDocumentId);

//         insert new ContentDocumentLink(
//             ContentDocumentId = insertedCv.ContentDocumentId,
//             LinkedEntityId = this.archiveRecordId,
//             ShareType = 'V',
//             Visibility = 'AllUsers'
//         );
//     }

//     private static List<String> buildCsvLines(List<SObject> rows, List<String> fields) {
//         List<String> lines = new List<String>();

//         for (SObject row : rows) {
//             List<String> cols = new List<String>();
            
//             for (String f : fields) {
//                 Object value;
                
//                 if (f.contains('.')) {
//                     List<String> parts = f.split('\\.');
//                     SObject parent = row.getSObject(parts[0]);
//                     value = parent != null ? parent.get(parts[1]) : null;
//                 } else {
//                     value = row.get(f);
//                 }

//                 cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
//             }
            
//             lines.add(String.join(cols, ','));
//         }
//         return lines;
//     }

//     private static List<String> normalizeFields(String csv) {
//         List<String> fields = new List<String>();
//         for (String f : csv.split(',')) {
//             if (!String.isBlank(f)) {
//                 fields.add(f.trim());
//             }
//         }
//         return fields;
//     }

//     private static String escapeCsv(String v) {
//         String s = v.replace('"', '""');
//         return (s.contains(',') || s.contains('\n') || s.contains('"'))
//             ? '"' + s + '"'
//             : s;
//     }
// }
public class DataArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ===================== CONSTANTS =====================
    private static final Integer MAX_CSV_SIZE_BYTES = 6 * 1024 * 1024; // 6 MB

    // ===================== STATE VARIABLES =====================
    private String objectName;
    private List<String> fields;
    private String soqlQuery;
    private Id archiveRecordId;
    private String archiveRecordName;
    private Boolean includeChildObjects;

    // Parent CSV accumulation
    private String currentParentCsv;
    private Integer parentPartNumber = 1;
    private String parentHeader;
    
    // Child CSV accumulation - one per child object
    private Map<String, ChildCsvData> childCsvMap = new Map<String, ChildCsvData>();
    
    private Set<Id> generatedContentDocumentIds = new Set<Id>();
    private List<Id> processedParentIds = new List<Id>();

    // ===================== INNER CLASS FOR CHILD CSV DATA =====================
    private class ChildCsvData {
        public String objectName;
        public String relationshipField;
        public List<String> fields;
        public String header;
        public String currentCsv;
        public Integer partNumber;
        
        public ChildCsvData(String objectName, String relationshipField, List<String> fields) {
            this.objectName = objectName;
            this.relationshipField = relationshipField;
            this.fields = fields;
            this.header = String.join(fields, ',') + '\n';
            this.currentCsv = this.header;
            this.partNumber = 1;
        }
    }

    // ===================== CONSTRUCTORS =====================
    public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery) {
        this(objectName, fieldsCsv, soqlQuery, false);
    }
    
    public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery, Boolean includeChildObjects) {
        this.objectName = objectName;
        this.fields = normalizeFields(fieldsCsv);
        this.soqlQuery = soqlQuery;
        this.includeChildObjects = includeChildObjects;
        
        // Initialize parent CSV
        this.parentHeader = String.join(this.fields, ',') + '\n';
        this.currentParentCsv = this.parentHeader;
        
        // Discover and initialize child objects
        if (this.includeChildObjects) {
            initializeChildObjects();
        }
    }

    // ===================== INITIALIZE CHILD OBJECTS =====================
    private void initializeChildObjects() {
        System.debug('╔══════════════════════════════════════════╗');
        System.debug('║   DISCOVERING CHILD OBJECTS              ║');
        System.debug('╚══════════════════════════════════════════╝');
        
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(this.objectName);
        if (objType == null) {
            System.debug('Object not found: ' + this.objectName);
            return;
        }
        
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        List<Schema.ChildRelationship> childRels = objDescribe.getChildRelationships();
        
        System.debug('Found ' + childRels.size() + ' total relationships');
        
        for (Schema.ChildRelationship childRel : childRels) {
            String childObjectName = childRel.getChildSObject().getDescribe().getName();
            String relationshipField = childRel.getField().getDescribe().getName();
            String relationshipName = childRel.getRelationshipName();
            Boolean isCascadeDelete = childRel.isCascadeDelete();
            
            // Skip system and share objects
            if (relationshipName == null || 
                childObjectName.endsWith('Share') || 
                childObjectName.endsWith('History') || 
                childObjectName.endsWith('Feed') ||
                childObjectName.endsWith('ChangeEvent')) {
                continue;
            }
            
            System.debug('Analyzing: ' + childObjectName + ' (Field: ' + relationshipField + ', Cascade: ' + isCascadeDelete + ')');
            
            // Get fields for this child object
            List<String> childFields = getChildObjectFields(childObjectName);
            
            if (!childFields.isEmpty()) {
                ChildCsvData childData = new ChildCsvData(
                    childObjectName,
                    relationshipField,
                    childFields
                );
                
                childCsvMap.put(childObjectName, childData);
                
                System.debug('✅ Initialized CSV for: ' + childObjectName + 
                           ' (' + childFields.size() + ' fields)');
            } else {
                System.debug('⚠️ No accessible fields found for: ' + childObjectName);
            }
        }
        
        System.debug('═══════════════════════════════════════');
        System.debug('TOTAL CHILD OBJECTS TO ARCHIVE: ' + childCsvMap.size());
        System.debug('═══════════════════════════════════════');
        
        for (String childName : childCsvMap.keySet()) {
            System.debug('  • ' + childName);
        }
    }

    // ===================== GET CHILD OBJECT FIELDS =====================
    private List<String> getChildObjectFields(String childObjectName) {
        List<String> fields = new List<String>();
        
        try {
            Schema.SObjectType childType = Schema.getGlobalDescribe().get(childObjectName);
            if (childType == null) return fields;
            
            Schema.DescribeSObjectResult childDescribe = childType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = childDescribe.fields.getMap();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                // Skip inaccessible or system fields
                if (!fieldDescribe.isAccessible() || 
                    fieldName.endsWith('__pc') || 
                    fieldName == 'isdeleted') {
                    continue;
                }
                
                // Include standard and custom fields
                if (fieldDescribe.isCreateable() || 
                    fieldName == 'id' || 
                    fieldName == 'name' || 
                    fieldName == 'createddate' || 
                    fieldName == 'createdbyid' ||
                    fieldName == 'lastmodifieddate' ||
                    fieldName == 'lastmodifiedbyid') {
                    fields.add(fieldDescribe.getName());
                }
            }
        } catch (Exception e) {
            System.debug('❌ Error getting fields for ' + childObjectName + ': ' + e.getMessage());
        }
        
        return fields;
    }

    // ===================== START METHOD =====================
    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('╔══════════════════════════════════════════╗');
        System.debug('║   STARTING DATA ARCHIVE BATCH            ║');
        System.debug('╚══════════════════════════════════════════╝');
        
        // Create Data Archive record
        Data_Archive__c archiveRecord = new Data_Archive__c(
            Parent_Object__c = this.objectName,
            Fields__c = String.join(this.fields, ','),
            Status__c = 'Archive In Progress'
            
        );
        insert archiveRecord;

        // Re-query to get auto-number Name
        archiveRecord = [
            SELECT Id, Name
            FROM Data_Archive__c
            WHERE Id = :archiveRecord.Id
            LIMIT 1
        ];

        this.archiveRecordId = archiveRecord.Id;
        this.archiveRecordName = archiveRecord.Name;

        System.debug('Archive Record: ' + this.archiveRecordName);
        System.debug('Parent Object: ' + this.objectName);
        System.debug('Include Children: ' + this.includeChildObjects);
        if (this.includeChildObjects) {
            System.debug('Child Objects Count: ' + childCsvMap.size());
        }

        return Database.getQueryLocator(this.soqlQuery);
    }

    // ===================== EXECUTE METHOD =====================
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope.isEmpty()) return;

        System.debug('Processing batch of ' + scope.size() + ' parent records');

        // Collect parent IDs
        Set<Id> parentIdsInScope = new Set<Id>();
        for (SObject record : scope) {
            parentIdsInScope.add(record.Id);
            processedParentIds.add(record.Id);
        }

        // ===== PROCESS PARENT RECORDS =====
        List<String> parentCsvLines = buildCsvLines(scope, this.fields);
        
        for (String line : parentCsvLines) {
            // Safety check: single record shouldn't exceed limit
            if (Blob.valueOf(this.parentHeader + line).size() > MAX_CSV_SIZE_BYTES) {
                System.debug('⚠️ Single parent record exceeds CSV size limit, skipping');
                continue;
            }

            String tentativeCsv = this.currentParentCsv + line + '\n';

            // Check if we need to split into a new file
            if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
                saveCsvFile(
                    this.currentParentCsv, 
                    this.parentPartNumber, 
                    this.objectName,
                    'Parent Object'
                );
                this.parentPartNumber++;
                this.currentParentCsv = this.parentHeader + line + '\n';
            } else {
                this.currentParentCsv = tentativeCsv;
            }
        }

        // ===== PROCESS CHILD OBJECTS =====
        if (this.includeChildObjects && !childCsvMap.isEmpty()) {
            processChildObjects(parentIdsInScope);
        }
    }

    // ===================== PROCESS CHILD OBJECTS =====================
    private void processChildObjects(Set<Id> parentIds) {
        System.debug('Processing child objects for ' + parentIds.size() + ' parent records');
        
        for (String childObjectName : childCsvMap.keySet()) {
            ChildCsvData childData = childCsvMap.get(childObjectName);
            
            try {
                // Build query for child records
                String childQuery = buildChildQuery(
                    childObjectName,
                    childData.fields,
                    childData.relationshipField,
                    parentIds
                );
                
                List<SObject> childRecords = Database.query(childQuery);
                
                if (childRecords.isEmpty()) {
                    System.debug('  ' + childObjectName + ': 0 records');
                    continue;
                }
                
                System.debug('  ' + childObjectName + ': ' + childRecords.size() + ' records');
                
                // Build CSV lines for child records
                List<String> childCsvLines = buildCsvLines(childRecords, childData.fields);
                
                // Add lines to child CSV
                for (String line : childCsvLines) {
                    String tentativeCsv = childData.currentCsv + line + '\n';
                    
                    // Check if we need to split into a new part
                    if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
                        saveCsvFile(
                            childData.currentCsv,
                            childData.partNumber,
                            childObjectName,
                            'Child Object'
                        );
                        childData.partNumber++;
                        childData.currentCsv = childData.header + line + '\n';
                    } else {
                        childData.currentCsv = tentativeCsv;
                    }
                }
                
                // Update the map with new data
                childCsvMap.put(childObjectName, childData);
                
            } catch (Exception e) {
                System.debug('❌ Error processing ' + childObjectName + ': ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
            }
        }
    }

    // ===================== BUILD CHILD QUERY =====================
    private String buildChildQuery(
        String childObjectName,
        List<String> fields,
        String relationshipField,
        Set<Id> parentIds
    ) {
        List<Id> parentIdList = new List<Id>(parentIds);
        String fieldsStr = String.join(fields, ', ');
        
        return 'SELECT ' + fieldsStr + 
               ' FROM ' + childObjectName + 
               ' WHERE ' + relationshipField + ' IN :parentIdList';
    }

    // ===================== FINISH METHOD =====================
    public void finish(Database.BatchableContext bc) {
        System.debug('╔══════════════════════════════════════════╗');
        System.debug('║   FINISHING DATA ARCHIVE BATCH           ║');
        System.debug('╚══════════════════════════════════════════╝');
        
        Integer totalFiles = 0;
        
        // Save remaining parent CSV
        if (this.currentParentCsv != this.parentHeader) {
            saveCsvFile(
                this.currentParentCsv,
                this.parentPartNumber,
                this.objectName,
                'Parent Object'
            );
            totalFiles++;
        }

        // Save remaining child CSVs
        if (this.includeChildObjects) {
            for (String childObjectName : childCsvMap.keySet()) {
                ChildCsvData childData = childCsvMap.get(childObjectName);
                
                // Only save if there's actual data (more than just header)
                if (childData.currentCsv != childData.header) {
                    saveCsvFile(
                        childData.currentCsv,
                        childData.partNumber,
                        childObjectName,
                        'Child Object'
                    );
                    totalFiles++;
                    System.debug('✅ Saved CSV for: ' + childObjectName);
                } else {
                    System.debug('⚠️ No data for: ' + childObjectName);
                }
            }
        }

        // Update archive record
        update new Data_Archive__c(
            Id = archiveRecordId,
            Status__c = 'Ready for Unarchive'
            
        );

        // Print summary
        printArchiveSummary(totalFiles);

        // Queue post-processing
        List<Id> ids = processedParentIds;

        if (!ids.isEmpty()) {
            Integer queueableUsed = Limits.getQueueableJobs();
            Integer queueableLimit = Limits.getLimitQueueableJobs();
            
            if (queueableUsed < queueableLimit) {
                System.enqueueJob(
                    new ArchivePostProcessQueueable(
                        new List<Id>(generatedContentDocumentIds),
                        archiveRecordId,
                        objectName,
                        ids
                    )
                );
            } else {
                System.debug('⚠️ Queueable limit reached, running delete inline');
                CascadeDeleteHelper.deleteParentWithRelations(objectName, ids);
            }
        } else if (!generatedContentDocumentIds.isEmpty()) {
            Integer queueableUsed = Limits.getQueueableJobs();
            Integer queueableLimit = Limits.getLimitQueueableJobs();
            
            if (queueableUsed < queueableLimit) {
                System.enqueueJob(
                    new ArchivePostProcessQueueable(
                        new List<Id>(generatedContentDocumentIds),
                        archiveRecordId,
                        objectName,
                        new List<Id>()
                    )
                );
            }
        }
    }

    // ===================== PRINT ARCHIVE SUMMARY =====================
    private void printArchiveSummary(Integer totalFiles) {
        System.debug('═══════════════════════════════════════');
        System.debug('ARCHIVE COMPLETE - SUMMARY');
        System.debug('═══════════════════════════════════════');
        System.debug('Archive Record: ' + this.archiveRecordName);
        System.debug('Parent Object: ' + this.objectName);
        System.debug('Parent Records Archived: ' + processedParentIds.size());
        System.debug('Total CSV Files Created: ' + totalFiles);
        System.debug('');
        System.debug('Files Created:');
        System.debug('  📄 ' + this.objectName + '.csv (Parent)');
        
        if (this.includeChildObjects) {
            for (String childObjectName : childCsvMap.keySet()) {
                ChildCsvData childData = childCsvMap.get(childObjectName);
                if (childData.currentCsv != childData.header || childData.partNumber > 1) {
                    System.debug('  📄 ' + childObjectName + '.csv (Child)');
                }
            }
        }
        System.debug('═══════════════════════════════════════');
    }

    // ===================== SAVE CSV FILE =====================
    private void saveCsvFile(String csvData, Integer partNum, String objectType, String description) {
        String fileName = this.archiveRecordName + '-' + objectType;
        String title = objectType;
        
        if (partNum > 1) {
            fileName += '-Part' + partNum;
            title += ' Part ' + partNum;
        }

        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = fileName + '.csv',
            Description = description + ' - Part ' + partNum,
            VersionData = Blob.valueOf(csvData)
        );
        insert cv;

        ContentVersion insertedCv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        generatedContentDocumentIds.add(insertedCv.ContentDocumentId);

        insert new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId = this.archiveRecordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        
        System.debug('💾 Saved: ' + fileName + '.csv (' + (csvData.length() / 1024) + ' KB)');
    }

    // ===================== HELPER METHODS =====================
    
    private static List<String> buildCsvLines(List<SObject> rows, List<String> fields) {
        List<String> lines = new List<String>();

        for (SObject row : rows) {
            List<String> cols = new List<String>();
            
            for (String f : fields) {
                Object value;
                
                if (f.contains('.')) {
                    // Handle relationship fields (e.g., Account.Name)
                    List<String> parts = f.split('\\.');
                    SObject parent = row.getSObject(parts[0]);
                    value = parent != null ? parent.get(parts[1]) : null;
                } else {
                    value = row.get(f);
                }

                cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
            }
            
            lines.add(String.join(cols, ','));
        }
        return lines;
    }

    private static List<String> normalizeFields(String csv) {
        List<String> fields = new List<String>();
        for (String f : csv.split(',')) {
            if (!String.isBlank(f)) {
                fields.add(f.trim());
            }
        }
        return fields;
    }

    private static String escapeCsv(String v) {
        String s = v.replace('"', '""');
        return (s.contains(',') || s.contains('\n') || s.contains('"'))
            ? '"' + s + '"'
            : s;
    }
}