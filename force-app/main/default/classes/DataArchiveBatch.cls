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
// public class DataArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {

//     // ===================== CONSTANTS =====================
//     private static final Integer MAX_CSV_SIZE_BYTES = 6 * 1024 * 1024; // 6 MB

//     // ===================== STATE VARIABLES =====================
//     private String objectName;
//     private List<String> fields;
//     private String soqlQuery;
//     private Id archiveRecordId;
//     private String archiveRecordName;
//     private Boolean includeChildObjects;

//     // Parent CSV accumulation
//     private String currentParentCsv;
//     private Integer parentPartNumber = 1;
//     private String parentHeader;
    
//     // IMPORTANT: Don't accumulate child data during execute - do it all in finish()
//     private Map<String, ChildMetadata> childMetadataMap = new Map<String, ChildMetadata>();
    
//     private Set<Id> generatedContentDocumentIds = new Set<Id>();
//     private List<Id> processedParentIds = new List<Id>();

//     // ===================== INNER CLASS =====================
//     private class ChildMetadata {
//         public String objectName;
//         public String relationshipField;
//         public List<String> fields;
        
//         public ChildMetadata(String objectName, String relationshipField, List<String> fields) {
//             this.objectName = objectName;
//             this.relationshipField = relationshipField;
//             this.fields = fields;
//         }
//     }

//     // ===================== CONSTRUCTORS =====================
//     public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery) {
//         this(objectName, fieldsCsv, soqlQuery, false);
//     }
    
//     public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery, Boolean includeChildObjects) {
//         this.objectName = objectName;
//         this.fields = normalizeFields(fieldsCsv);
//         this.soqlQuery = soqlQuery;
//         this.includeChildObjects = includeChildObjects;
        
//         // Initialize parent CSV
//         this.parentHeader = String.join(this.fields, ',') + '\n';
//         this.currentParentCsv = this.parentHeader;
        
//         // Discover child objects
//         if (this.includeChildObjects) {
//             initializeChildObjects();
//         }
//     }

//     // ===================== INITIALIZE CHILD OBJECTS =====================
//     private void initializeChildObjects() {
//         System.debug('╔══════════════════════════════════════════╗');
//         System.debug('║   DISCOVERING CHILD OBJECTS              ║');
//         System.debug('╚══════════════════════════════════════════╝');
        
//         Schema.SObjectType objType = Schema.getGlobalDescribe().get(this.objectName);
//         if (objType == null) {
//             System.debug(' Object not found: ' + this.objectName);
//             return;
//         }
        
//         Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
//         List<Schema.ChildRelationship> childRels = objDescribe.getChildRelationships();
        
//         System.debug('Found ' + childRels.size() + ' total relationships');
        
//         // WHITELIST: Only archive these common objects
//         // Customize this list based on your needs
//         Set<String> allowedObjects = new Set<String>{
//             'Contact',
//             'Opportunity',
//             'Case',
//             'Task',
//             'Event',
//             'Note',
//             'Attachment',
//             'OpportunityLineItem',
//             'CaseComment',
//             'AccountContactRole',
//             'OpportunityContactRole',
//             'Asset',
//             'Contract',
//             'Order',
//             'Quote',
//             'Booking_Order__c'
//         };
        
//         Integer validCount = 0;
//         Integer skippedCount = 0;
        
//         for (Schema.ChildRelationship childRel : childRels) {
//             String relationshipName = childRel.getRelationshipName();
            
//             // Skip if no relationship name
//             if (relationshipName == null) {
//                 skippedCount++;
//                 continue;
//             }
            
//             Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
//             String childObjectName = childDescribe.getName();
//             String relationshipField = childRel.getField().getDescribe().getName();
            
//             // ONLY PROCESS WHITELISTED OBJECTS
//             if (!allowedObjects.contains(childObjectName)) {
//                 skippedCount++;
//                 continue;
//             }
            
//             // Skip if not accessible or queryable
//             if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) {
//                 System.debug(' Skipping (not accessible): ' + childObjectName);
//                 skippedCount++;
//                 continue;
//             }
            
//             // Get fields for this child object
//             List<String> childFields = getChildObjectFields(childObjectName);
            
//             if (!childFields.isEmpty()) {
//                 ChildMetadata meta = new ChildMetadata(
//                     childObjectName,
//                     relationshipField,
//                     childFields
//                 );
                
//                 childMetadataMap.put(childObjectName, meta);
//                 validCount++;
//                 System.debug(' Will archive: ' + childObjectName + ' (via ' + relationshipField + ')');
//             } else {
//                 System.debug(' Skipping (no accessible fields): ' + childObjectName);
//                 skippedCount++;
//             }
//         }
        
//         System.debug('');
//         System.debug('Valid child objects: ' + validCount);
//         System.debug('Skipped objects: ' + skippedCount);
//     }

//     // ===================== GET CHILD OBJECT FIELDS =====================
//     private List<String> getChildObjectFields(String childObjectName) {
//         List<String> fields = new List<String>();
        
//         try {
//             Schema.SObjectType childType = Schema.getGlobalDescribe().get(childObjectName);
//             if (childType == null) return fields;
            
//             Schema.DescribeSObjectResult childDescribe = childType.getDescribe();
//             if (!childDescribe.isAccessible()) return fields;
            
//             Map<String, Schema.SObjectField> fieldMap = childDescribe.fields.getMap();
            
//             for (String fieldName : fieldMap.keySet()) {
//                 Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
//                 // Skip inaccessible fields
//                 if (!fieldDescribe.isAccessible()) {
//                     continue;
//                 }
                
//                 // Skip person account fields and deleted flag
//                 if (fieldName.endsWith('__pc') || fieldName.equalsIgnoreCase('isdeleted')) {
//                     continue;
//                 }
                
//                 // Include createable fields or important system fields
//                 if (fieldDescribe.isCreateable() || 
//                     fieldName.equalsIgnoreCase('id') || 
//                     fieldName.equalsIgnoreCase('name') || 
//                     fieldName.equalsIgnoreCase('createddate') || 
//                     fieldName.equalsIgnoreCase('createdbyid') ||
//                     fieldName.equalsIgnoreCase('lastmodifieddate') ||
//                     fieldName.equalsIgnoreCase('lastmodifiedbyid')) {
//                     fields.add(fieldDescribe.getName());
//                 }
//             }
//         } catch (Exception e) {
//             System.debug(' Error getting fields for ' + childObjectName + ': ' + e.getMessage());
//         }
        
//         return fields;
//     }

//     // ===================== START METHOD =====================
//     public Database.QueryLocator start(Database.BatchableContext bc) {
//         System.debug('╔══════════════════════════════════════════╗');
//         System.debug('║   STARTING DATA ARCHIVE BATCH            ║');
//         System.debug('╚══════════════════════════════════════════╝');
        
//         Data_Archive__c archiveRecord = new Data_Archive__c(
//             Parent_Object__c = this.objectName,
//             Fields__c = String.join(this.fields, ','),
//             Status__c = 'Archive In Progress'
//         );
//         insert archiveRecord;

//         archiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archiveRecord.Id LIMIT 1];
//         this.archiveRecordId = archiveRecord.Id;
//         this.archiveRecordName = archiveRecord.Name;

//         System.debug('Archive: ' + this.archiveRecordName);
//         System.debug('Parent: ' + this.objectName);
//         System.debug('Children: ' + childMetadataMap.size());

//         return Database.getQueryLocator(this.soqlQuery);
//     }

//     // ===================== EXECUTE METHOD =====================
//     public void execute(Database.BatchableContext bc, List<SObject> scope) {
//         if (scope.isEmpty()) return;

//         System.debug('Processing ' + scope.size() + ' parent records');

//         // Just collect parent IDs and build parent CSV
//         for (SObject record : scope) {
//             processedParentIds.add(record.Id);
//         }

//         // Build parent CSV
//         List<String> parentCsvLines = buildCsvLines(scope, this.fields);
        
//         for (String line : parentCsvLines) {
//             if (Blob.valueOf(this.parentHeader + line).size() > MAX_CSV_SIZE_BYTES) {
//                 System.debug('⚠ Single parent record exceeds size limit');
//                 continue;
//             }

//             String tentativeCsv = this.currentParentCsv + line + '\n';

//             if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
//                 saveCsvFile(
//                     this.currentParentCsv, 
//                     this.parentPartNumber, 
//                     this.objectName,
//                     'Parent Object'
//                 );
//                 this.parentPartNumber++;
//                 this.currentParentCsv = this.parentHeader + line + '\n';
//             } else {
//                 this.currentParentCsv = tentativeCsv;
//             }
//         }
        
//         // DON'T process child objects here - do it in finish() before deletion!
//     }

//     // ===================== FINISH METHOD =====================
//     public void finish(Database.BatchableContext bc) {
//         System.debug('');
//         System.debug('╔══════════════════════════════════════════╗');
//         System.debug('║   FINISHING - CREATING ALL CSVs          ║');
//         System.debug('╚══════════════════════════════════════════╝');
        
//         try {
//             if (processedParentIds.isEmpty()) {
//                 System.debug('⚠ No parent records to archive');
//                 return;
//             }
            
//             System.debug('Total parent records: ' + processedParentIds.size());
            
//             // Save parent CSV
//             if (this.currentParentCsv != this.parentHeader) {
//                 System.debug('');
//                 System.debug('Saving parent CSV...');
//                 saveCsvFile(
//                     this.currentParentCsv,
//                     this.parentPartNumber,
//                     this.objectName,
//                     'Parent Object'
//                 );
//                 System.debug(' Parent CSV saved');
//             }

//             // ===== CRITICAL: Process ALL child objects HERE in finish() =====
//             // This ensures child records still exist before deletion
//             if (this.includeChildObjects && !childMetadataMap.isEmpty()) {
//                 System.debug('');
//                 System.debug('╔══════════════════════════════════════════╗');
//                 System.debug('║   PROCESSING CHILD OBJECTS               ║');
//                 System.debug('╚══════════════════════════════════════════╝');
                
//                 processAllChildObjects();
//             }

//             // Update archive status
//             System.debug('');
//             System.debug('Updating archive status...');
//             update new Data_Archive__c(
//                 Id = archiveRecordId,
//                 Status__c = 'Ready for Unarchive'
//             );
//             System.debug(' Archive status updated');

//             System.debug('');
//             System.debug('Archive complete! Total files: ' + generatedContentDocumentIds.size());

//             // NOW queue deletion (after CSVs are created)
//             if (!processedParentIds.isEmpty()) {
//                 Integer queueableUsed = Limits.getQueueableJobs();
//                 Integer queueableLimit = Limits.getLimitQueueableJobs();
                
//                 if (queueableUsed < queueableLimit) {
//                     System.debug('Queueing deletion of ' + processedParentIds.size() + ' records');
//                     System.enqueueJob(
//                         new ArchivePostProcessQueueable(
//                             new List<Id>(generatedContentDocumentIds),
//                             archiveRecordId,
//                             objectName,
//                             processedParentIds
//                         )
//                     );
//                     System.debug(' Post-process queued');
//                 } else {
//                     System.debug('Running deletion inline (no queueable slots)');
//                     CascadeDeleteHelper.deleteParentWithRelations(objectName, processedParentIds);
//                 }
//             }
            
//             System.debug('');
//             System.debug('╔══════════════════════════════════════════╗');
//             System.debug('║   FINISH METHOD COMPLETED                ║');
//             System.debug('╚══════════════════════════════════════════╝');
            
//         } catch (Exception e) {
//             System.debug('');
//             System.debug('❌❌❌ ERROR IN FINISH METHOD ❌❌❌');
//             System.debug('Error Type: ' + e.getTypeName());
//             System.debug('Error Message: ' + e.getMessage());
//             System.debug('Line Number: ' + e.getLineNumber());
//             System.debug('Stack Trace: ' + e.getStackTraceString());
//             System.debug('❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌');
            
//             // Try to update archive status to show error
//             try {
//                 update new Data_Archive__c(
//                     Id = archiveRecordId,
//                     Status__c = 'Error: ' + e.getMessage().abbreviate(255)
//                 );
//             } catch (Exception updateError) {
//                 System.debug('Could not update archive status: ' + updateError.getMessage());
//             }
//         }
//     }

//     // ===================== PROCESS ALL CHILD OBJECTS (IN FINISH) =====================
//     private void processAllChildObjects() {
//         System.debug('Processing children for ' + processedParentIds.size() + ' parent IDs');
        
//         Integer successCount = 0;
//         Integer errorCount = 0;
        
//         for (String childObjectName : childMetadataMap.keySet()) {
//             ChildMetadata meta = childMetadataMap.get(childObjectName);
            
//             System.debug('');
//             System.debug('--- ' + childObjectName + ' ---');
//             System.debug('Relationship field: ' + meta.relationshipField);
            
//             try {
//                 // Build and execute query
//                 List<Id> parentIdList = processedParentIds;
//                 String fieldsStr = String.join(meta.fields, ', ');
//                 String childQuery = 'SELECT ' + fieldsStr + 
//                                   ' FROM ' + childObjectName + 
//                                   ' WHERE ' + meta.relationshipField + ' IN :parentIdList';
                
//                 System.debug('Query: ' + childQuery);
                
//                 List<SObject> childRecords = Database.query(childQuery);
                
//                 System.debug('Found: ' + childRecords.size() + ' records');
                
//                 if (childRecords.isEmpty()) {
//                     System.debug(' No records - skipping CSV creation');
//                     continue;
//                 }
                
//                 // Build CSV
//                 String header = String.join(meta.fields, ',') + '\n';
//                 String csvData = header;
                
//                 List<String> csvLines = buildCsvLines(childRecords, meta.fields);
//                 System.debug('Generated: ' + csvLines.size() + ' CSV lines');
                
//                 for (String line : csvLines) {
//                     csvData += line + '\n';
//                 }
                
//                 System.debug('CSV size: ' + (csvData.length() / 1024) + ' KB');
                
//                 // Save CSV file
//                 saveCsvFile(csvData, 1, childObjectName, 'Child Object');
                
//                 System.debug(' CSV saved for ' + childObjectName);
//                 successCount++;
                
//             } catch (Exception e) {
//                 System.debug(' Error processing ' + childObjectName + ': ' + e.getMessage());
//                 System.debug('Stack: ' + e.getStackTraceString());
//                 errorCount++;
//             }
//         }
        
//         System.debug('');
//         System.debug('Child processing complete. Success: ' + successCount + ', Errors: ' + errorCount);
//     }

//     // ===================== SAVE CSV FILE =====================
//     private void saveCsvFile(String csvData, Integer partNum, String objectType, String description) {
//         String fileName = this.archiveRecordName + '-' + objectType;
//         String title = objectType;
        
//         if (partNum > 1) {
//             fileName += '-Part' + partNum;
//             title += ' Part ' + partNum;
//         }

//         System.debug('Creating file: ' + fileName + '.csv (' + (csvData.length() / 1024) + ' KB)');

//         ContentVersion cv = new ContentVersion(
//             Title = title,
//             PathOnClient = fileName + '.csv',
//             Description = description + ' - Part ' + partNum,
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
        
//         System.debug(' Saved: ' + fileName + '.csv (ID: ' + insertedCv.ContentDocumentId + ')');
//     }

//     // ===================== HELPER METHODS =====================
    
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
//single level
// public class DataArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {

//     // ===================== CONSTANTS =====================
//     private static final Integer MAX_CSV_SIZE_BYTES = 6 * 1024 * 1024; // 6 MB

//     // ===================== STATE VARIABLES =====================
//     private String objectName;
//     private List<String> fields;
//     private String soqlQuery;
//     private Id archiveRecordId;
//     private String archiveRecordName;
//     private Boolean includeChildObjects;

//     // Parent CSV accumulation
//     private String currentParentCsv;
//     private Integer parentPartNumber = 1;
//     private String parentHeader;
    
//     // IMPORTANT: Don't accumulate child data during execute - do it all in finish()
//     private Map<String, ChildMetadata> childMetadataMap = new Map<String, ChildMetadata>();
    
//     private Set<Id> generatedContentDocumentIds = new Set<Id>();
//     private List<Id> processedParentIds = new List<Id>();

//     // ===================== INNER CLASS =====================
//     private class ChildMetadata {
//         public String objectName;
//         public String relationshipField;
//         public List<String> fields;
        
//         public ChildMetadata(String objectName, String relationshipField, List<String> fields) {
//             this.objectName = objectName;
//             this.relationshipField = relationshipField;
//             this.fields = fields;
//         }
//     }

//     // ===================== CONSTRUCTORS =====================
//     // Constructor that ALWAYS includes child objects
//     public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery) {
//         this.objectName = objectName;
//         this.fields = normalizeFields(fieldsCsv);
//         this.soqlQuery = soqlQuery;
//         this.includeChildObjects = true; // ALWAYS TRUE
        
//         // Initialize parent CSV
//         this.parentHeader = String.join(this.fields, ',') + '\n';
//         this.currentParentCsv = this.parentHeader;
        
//         // Discover child objects
//         initializeChildObjects();
//     }

//     // ===================== INITIALIZE CHILD OBJECTS =====================
//     private void initializeChildObjects() {
//         System.debug('DISCOVERING CHILD OBJECTS              ');
        
//         Schema.SObjectType objType = Schema.getGlobalDescribe().get(this.objectName);
//         if (objType == null) {
//             System.debug(' Object not found: ' + this.objectName);
//             return;
//         }
        
//         Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
//         List<Schema.ChildRelationship> childRels = objDescribe.getChildRelationships();
        
//         System.debug('Found ' + childRels.size() + ' total relationships');
        
//         // WHITELIST: Only archive these objects
//         Set<String> allowedObjects = new Set<String>{
//             'Contact',
//             'Opportunity',
//             'Case',
//             'Task',
//             'Event',
//             'Note',
//             'Attachment',
//             'OpportunityLineItem',
//             'CaseComment',
//             'AccountContactRole',
//             'OpportunityContactRole',
//             'Asset',
//             'Contract',
//             'Order',
//             'Quote',
//             'Booking_Order__c'  // YOUR CUSTOM OBJECT
//         };
        
//         Integer validCount = 0;
//         Integer skippedCount = 0;
        
//         for (Schema.ChildRelationship childRel : childRels) {
//             String relationshipName = childRel.getRelationshipName();
            
//             if (relationshipName == null) {
//                 skippedCount++;
//                 continue;
//             }
            
//             Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
//             String childObjectName = childDescribe.getName();
//             String relationshipField = childRel.getField().getDescribe().getName();
            
//             // Skip system objects
//             if (childObjectName.endsWith('Share') || 
//                 childObjectName.endsWith('History') || 
//                 childObjectName.endsWith('Feed') ||
//                 childObjectName.endsWith('ChangeEvent')) {
//                 skippedCount++;
//                 continue;
//             }
            
//             // // ONLY PROCESS WHITELISTED OBJECTS
//             // if (!allowedObjects.contains(childObjectName)) {
//             //     skippedCount++;
//             //     continue;
//             // }
            
//             if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) {
//                 System.debug(' Skipping (not accessible): ' + childObjectName);
//                 skippedCount++;
//                 continue;
//             }
            
//             List<String> childFields = getChildObjectFields(childObjectName);
            
//             if (!childFields.isEmpty()) {
//                 ChildMetadata meta = new ChildMetadata(
//                     childObjectName,
//                     relationshipField,
//                     childFields
//                 );
                
//                 childMetadataMap.put(childObjectName, meta);
//                 validCount++;
//                 System.debug(' Will archive: ' + childObjectName + ' (via ' + relationshipField + ')');
//             } else {
//                 System.debug(' Skipping (no fields): ' + childObjectName);
//                 skippedCount++;
//             }
//         }
        
//         System.debug('');
//         System.debug('Valid child objects: ' + validCount);
//         System.debug('Skipped objects: ' + skippedCount);
//     }

//     // ===================== GET CHILD OBJECT FIELDS =====================
//     private List<String> getChildObjectFields(String childObjectName) {
//         List<String> fields = new List<String>();
        
//         try {
//             Schema.SObjectType childType = Schema.getGlobalDescribe().get(childObjectName);
//             if (childType == null) return fields;
            
//             Schema.DescribeSObjectResult childDescribe = childType.getDescribe();
//             if (!childDescribe.isAccessible()) return fields;
            
//             Map<String, Schema.SObjectField> fieldMap = childDescribe.fields.getMap();
            
//             for (String fieldName : fieldMap.keySet()) {
//                 Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
//                 if (!fieldDescribe.isAccessible() || 
//                     fieldName.endsWith('__pc') || 
//                     fieldName.equalsIgnoreCase('isdeleted')) {
//                     continue;
//                 }
                
//                 if (fieldDescribe.isCreateable() || 
//                     fieldName.equalsIgnoreCase('id') || 
//                     fieldName.equalsIgnoreCase('name') || 
//                     fieldName.equalsIgnoreCase('createddate') || 
//                     fieldName.equalsIgnoreCase('createdbyid') ||
//                     fieldName.equalsIgnoreCase('lastmodifieddate') ||
//                     fieldName.equalsIgnoreCase('lastmodifiedbyid')) {
//                     fields.add(fieldDescribe.getName());
//                 }
//             }
//         } catch (Exception e) {
//             System.debug(' Error getting fields for ' + childObjectName + ': ' + e.getMessage());
//         }
        
//         return fields;
//     }

//     // ===================== START METHOD =====================
//     public Database.QueryLocator start(Database.BatchableContext bc) {
//         System.debug('STARTING DATA ARCHIVE BATCH');
        
//         Data_Archive__c archiveRecord = new Data_Archive__c(
//             Parent_Object__c = this.objectName,
//             Fields__c = String.join(this.fields, ','),
//             Status__c = 'Archive In Progress'
//         );
//         insert archiveRecord;

//         archiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archiveRecord.Id LIMIT 1];
//         this.archiveRecordId = archiveRecord.Id;
//         this.archiveRecordName = archiveRecord.Name;

//         System.debug('Archive: ' + this.archiveRecordName);
//         System.debug('Parent: ' + this.objectName);
//         System.debug('Children: ' + childMetadataMap.size());

//         return Database.getQueryLocator(this.soqlQuery);
//     }

//     // ===================== EXECUTE METHOD =====================
//     public void execute(Database.BatchableContext bc, List<SObject> scope) {
//         if (scope.isEmpty()) return;

//         System.debug('Processing ' + scope.size() + ' parent records');

//         // Just collect parent IDs and build parent CSV
//         for (SObject record : scope) {
//             processedParentIds.add(record.Id);
//         }

//         // Build parent CSV
//         List<String> parentCsvLines = buildCsvLines(scope, this.fields);
        
//         for (String line : parentCsvLines) {
//             if (Blob.valueOf(this.parentHeader + line).size() > MAX_CSV_SIZE_BYTES) {
//                 System.debug(' Single parent record exceeds size limit');
//                 continue;
//             }

//             String tentativeCsv = this.currentParentCsv + line + '\n';

//             if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
//                 saveCsvFile(
//                     this.currentParentCsv, 
//                     this.parentPartNumber, 
//                     this.objectName,
//                     'Parent Object'
//                 );
//                 this.parentPartNumber++;
//                 this.currentParentCsv = this.parentHeader + line + '\n';
//             } else {
//                 this.currentParentCsv = tentativeCsv;
//             }
//         }
        
//         // DON'T process child objects here - do it in finish() before deletion!
//     }

//     // ===================== FINISH METHOD =====================
//     public void finish(Database.BatchableContext bc) {
//         System.debug('');
//         System.debug('FINISHING - CREATING ALL CSVs');
        
//         try {
//             if (processedParentIds.isEmpty()) {
//                 System.debug(' No parent records to archive');
//                 return;
//             }
            
//             System.debug('Total parent records: ' + processedParentIds.size());
//             System.debug('Parent IDs: ' + processedParentIds);
            
//             // Save parent CSV
//             if (this.currentParentCsv != this.parentHeader) {
//                 System.debug('');
//                 System.debug('Saving parent CSV...');
//                 saveCsvFile(
//                     this.currentParentCsv,
//                     this.parentPartNumber,
//                     this.objectName,
//                     'Parent Object'
//                 );
//                 System.debug(' Parent CSV saved');
//             }

//             // ===== CRITICAL: Process ALL child objects HERE in finish() =====
//             // This ensures child records still exist before deletion
//             if (this.includeChildObjects && !childMetadataMap.isEmpty()) {
//                 System.debug('');
//                 System.debug('PROCESSING CHILD OBJECTS');
                
//                 processAllChildObjects();
//             }

//             // Update archive status
//             System.debug('');
//             System.debug('Updating archive status...');
//             update new Data_Archive__c(
//                 Id = archiveRecordId,
//                 Status__c = 'Ready for Unarchive'
//             );
//             System.debug(' Archive status updated');

//             System.debug('');
//             System.debug('Archive complete! Total files: ' + generatedContentDocumentIds.size());

//             // NOW queue deletion (after CSVs are created)
//             if (!processedParentIds.isEmpty()) {
//                 Integer queueableUsed = Limits.getQueueableJobs();
//                 Integer queueableLimit = Limits.getLimitQueueableJobs();
                
//                 if (queueableUsed < queueableLimit) {
//                     System.debug('Queueing deletion of ' + processedParentIds.size() + ' records');
//                     System.enqueueJob(
//                         new ArchivePostProcessQueueable(
//                             new List<Id>(generatedContentDocumentIds),
//                             archiveRecordId,
//                             objectName,
//                             processedParentIds
//                         )
//                     );
//                     System.debug(' Post-process queued');
//                 } else {
//                     System.debug('Running deletion inline (no queueable slots)');
//                     CascadeDeleteHelper.deleteParentWithRelations(objectName, processedParentIds);
//                 }
//             }
            
//             System.debug('FINISH METHOD COMPLETED');
            
            
//         } catch (Exception e) {
//             System.debug('');
//             System.debug('ERROR IN FINISH METHOD');
//             System.debug('Error Type: ' + e.getTypeName());
//             System.debug('Error Message: ' + e.getMessage());
//             System.debug('Line Number: ' + e.getLineNumber());
//             System.debug('Stack Trace: ' + e.getStackTraceString());
            
            
//             try {
//                 update new Data_Archive__c(
//                     Id = archiveRecordId,
//                     Status__c = 'Error: ' + e.getMessage().abbreviate(255)
//                 );
//             } catch (Exception updateError) {
//                 System.debug('Could not update archive status: ' + updateError.getMessage());
//             }
//         }
//     }

//     // ===================== PROCESS ALL CHILD OBJECTS (IN FINISH) =====================
//     private void processAllChildObjects() {
//         System.debug('Processing children for ' + processedParentIds.size() + ' parent IDs');
        
//         Integer successCount = 0;
//         Integer errorCount = 0;
        
//         for (String childObjectName : childMetadataMap.keySet()) {
//             ChildMetadata meta = childMetadataMap.get(childObjectName);
            
//             System.debug('');
//             System.debug('--- ' + childObjectName + ' ---');
//             System.debug('Relationship field: ' + meta.relationshipField);
            
//             try {
//                 // Build and execute query
//                 List<Id> parentIdList = processedParentIds;
//                 String fieldsStr = String.join(meta.fields, ', ');
//                 String childQuery = 'SELECT ' + fieldsStr + 
//                                   ' FROM ' + childObjectName + 
//                                   ' WHERE ' + meta.relationshipField + ' IN :parentIdList';
                
//                 System.debug('Query: ' + childQuery);
                
//                 List<SObject> childRecords = Database.query(childQuery);
                
//                 System.debug('Found: ' + childRecords.size() + ' records');
                
//                 if (childRecords.isEmpty()) {
//                     System.debug(' No records - skipping CSV creation');
//                     continue;
//                 }
                
//                 // Build CSV
//                 String header = String.join(meta.fields, ',') + '\n';
//                 String csvData = header;
                
//                 List<String> csvLines = buildCsvLines(childRecords, meta.fields);
//                 System.debug('Generated: ' + csvLines.size() + ' CSV lines');
                
//                 for (String line : csvLines) {
//                     csvData += line + '\n';
//                 }
                
//                 System.debug('CSV size: ' + (csvData.length() / 1024) + ' KB');
                
//                 // Save CSV file
//                 saveCsvFile(csvData, 1, childObjectName, 'Child Object');
                
//                 System.debug(' CSV saved for ' + childObjectName);
//                 successCount++;
                
//             } catch (Exception e) {
//                 System.debug(' Error processing ' + childObjectName + ': ' + e.getMessage());
//                 System.debug('Stack: ' + e.getStackTraceString());
//                 errorCount++;
//             }
//         }
        
//         System.debug('');
//         System.debug('Child processing complete. Success: ' + successCount + ', Errors: ' + errorCount);
//     }

//     // ===================== SAVE CSV FILE =====================
//     private void saveCsvFile(String csvData, Integer partNum, String objectType, String description) {
//         String fileName = this.archiveRecordName + '-' + objectType;
//         String title = objectType;
        
//         if (partNum > 1) {
//             fileName += '-Part' + partNum;
//             title += ' Part ' + partNum;
//         }

//         System.debug('Creating file: ' + fileName + '.csv (' + (csvData.length() / 1024) + ' KB)');

//         ContentVersion cv = new ContentVersion(
//             Title = title,
//             PathOnClient = fileName + '.csv',
//             Description = description + ' - Part ' + partNum,
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
        
//         System.debug(' Saved: ' + fileName + '.csv (ID: ' + insertedCv.ContentDocumentId + ')');
//     }

//     // ===================== HELPER METHODS =====================
    
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
    private static final Integer MAX_CSV_SIZE_BYTES = 60 * 1024 ; // 60KB

    // ===================== STATE VARIABLES =====================
    private String objectName;
    private List<String> fields;
    private String soqlQuery;
    private Id archiveRecordId;
    private String archiveRecordName;

    // Parent CSV accumulation
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
        this.fields       = normalizeFields(fieldsCsv);
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

        // Print full tree
        for (Integer d = 1; d <= 10; d++) {
            for (ChildMetadata m : childMetadataMap.values()) {
                if (m.depth == d) {
                    String indent = '';
                    for (Integer i = 0; i < d; i++) indent += '  ';
                    System.debug(indent + '[Depth ' + d + '] '
                               + m.objectName
                               + ' → parent: ' + m.parentObjectName
                               + ' via: '      + m.relationshipField);
                }
            }
        }
    }

    // ===================== RECURSIVE CHAIN DISCOVERY =====================
    private void discoverChain(String parentObjName, Integer depth) {
        if (depth > 10) return;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjName);
        if (objType == null) return;

        List<Schema.ChildRelationship> childRels = objType.getDescribe().getChildRelationships();

        for (Schema.ChildRelationship childRel : childRels) {

            // ONLY master-detail (cascade delete = true)
            if (!childRel.isCascadeDelete()) continue;

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            String childObjectName   = childDescribe.getName();
            String relationshipField = childRel.getField().getDescribe().getName();
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

            System.debug('Found [depth-' + depth + ']: ' + childObjectName
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

        return Database.getQueryLocator(this.soqlQuery + ' WITH SECURITY_ENFORCED');
    }

    // ===================== EXECUTE =====================
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope.isEmpty()) return;

        System.debug('Processing ' + scope.size() + ' parent records');

        // Collect parent IDs
        for (SObject record : scope) {
            processedParentIds.add(record.Id);
        }

        // Build parent CSV
        for (String line : buildCsvLines(scope, this.fields)) {
            if (Blob.valueOf(this.parentHeader + line).size() > MAX_CSV_SIZE_BYTES) {
                System.debug('Single record exceeds size limit - skipping');
                continue;
            }

            String tentativeCsv = this.currentParentCsv + line + '\n';

            if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
                saveCsvFile(this.currentParentCsv, this.parentPartNumber, this.objectName);
                this.parentPartNumber++;
                this.currentParentCsv = this.parentHeader + line + '\n';
            } else {
                this.currentParentCsv = tentativeCsv;
            }
        }
    }

    // ===================== FINISH =====================
    public void finish(Database.BatchableContext bc) {
        System.debug('');
        System.debug('========== FINISHING - CREATING ALL CSVs ==========');

        try {
            if (processedParentIds.isEmpty()) {
                System.debug('No parent records processed');
                return;
            }

            System.debug('Total parent records : ' + processedParentIds.size());

            // 1. Save parent CSV
            if (this.currentParentCsv != this.parentHeader) {
                saveCsvFile(this.currentParentCsv, this.parentPartNumber, this.objectName);
                System.debug('Parent CSV saved: ' + this.objectName);
            }

            // 2. Process full chain level by level
            if (!childMetadataMap.isEmpty()) {
                processChain();
            }

            // 3. Update archive status
            update new Data_Archive__c(
                Id        = archiveRecordId,
                Status__c = 'Ready for Unarchive'
            );
            System.debug('Archive status updated');
            System.debug('Total files created: ' + generatedContentDocumentIds.size());

            // 4. Queue deletion
            if (!processedParentIds.isEmpty()) {
                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                    System.enqueueJob(new ArchivePostProcessQueueable(
                        new List<Id>(generatedContentDocumentIds),
                        archiveRecordId,
                        objectName,
                        processedParentIds
                    ));
                    System.debug('Deletion queued');
                } else {
                    System.debug('Running deletion inline');
                    CascadeDeleteHelper.deleteParentWithRelations(objectName, processedParentIds);
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

    // ===================== PROCESS FULL CHAIN =====================
    private void processChain() {
        System.debug('');
        System.debug('========== PROCESSING CHAIN ==========');
        System.debug('Root IDs: ' + processedParentIds.size());

        // Group metadata by depth level
        Map<Integer, List<ChildMetadata>> byDepth = new Map<Integer, List<ChildMetadata>>();
        for (ChildMetadata meta : childMetadataMap.values()) {
            if (!byDepth.containsKey(meta.depth)) {
                byDepth.put(meta.depth, new List<ChildMetadata>());
            }
            byDepth.get(meta.depth).add(meta);
        }

        // =====================================================================
        // KEY: collectedIds tracks IDs found at EACH object level
        //
        // Example chain:
        //   Booking__c              [B1, B2]
        //   └── Booking_Order__c    [O1, O2, O3]      ← parent = Booking__c
        //   │     └── Order_Item__c [I1, I2, I3]       ← parent = Booking_Order__c
        //   │           └── Item_Tax__c [T1, T2]        ← parent = Order_Item__c
        //   └── Booking_Payment__c  [P1, P2]            ← parent = Booking__c
        //         └── Payment_Line__c [L1, L2]          ← parent = Booking_Payment__c
        //
        // Without this: Item_Tax__c queries WHERE Order_Item__c IN [B1,B2] ← WRONG
        // With this:    Item_Tax__c queries WHERE Order_Item__c IN [I1,I2,I3] ← CORRECT
        // =====================================================================
        Map<String, List<Id>> collectedIds = new Map<String, List<Id>>();
        collectedIds.put(this.objectName, processedParentIds); // seed with root

        // Sort depths: 1, 2, 3, 4... N
        List<Integer> depths = new List<Integer>(byDepth.keySet());
        depths.sort();

        Integer successCount = 0;
        Integer errorCount   = 0;

        for (Integer depth : depths) {
            System.debug('');
            System.debug('----- Depth ' + depth + ' -----');

            for (ChildMetadata meta : byDepth.get(depth)) {
                System.debug('Object       : ' + meta.objectName);
                System.debug('Parent Object: ' + meta.parentObjectName);
                System.debug('Via Field    : ' + meta.relationshipField);

                // Get IDs of the DIRECT parent (not necessarily root!)
                List<Id> parentIds = collectedIds.get(meta.parentObjectName);

                if (parentIds == null || parentIds.isEmpty()) {
                    System.debug('No parent IDs found for '
                               + meta.parentObjectName + ' - skipping '
                               + meta.objectName);
                    continue;
                }

                try {
                    // Query child records using DIRECT parent IDs
                    String fieldsStr  = String.join(meta.fields, ', ');
                    String childQuery = 'SELECT ' + fieldsStr
                                     + ' FROM '   + meta.objectName
                                     + ' WHERE '  + meta.relationshipField
                                     + ' IN :parentIds';

                    System.debug('Query: ' + childQuery);

                    List<SObject> childRecords = Database.query(childQuery);
                    System.debug('Found: ' + childRecords.size() + ' records');

                    if (childRecords.isEmpty()) {
                        System.debug('No records - skipping CSV');
                        continue;
                    }

                    // Store IDs so next depth level can use them
                    List<Id> theseIds = new List<Id>();
                    for (SObject rec : childRecords) theseIds.add(rec.Id);
                    collectedIds.put(meta.objectName, theseIds);
                    System.debug('Stored ' + theseIds.size()
                               + ' IDs for ' + meta.objectName);

                    // Build CSV
                    String csvData = String.join(meta.fields, ',') + '\n';
                    for (String line : buildCsvLines(childRecords, meta.fields)) {
                        csvData += line + '\n';
                    }

                    System.debug('CSV size: ' + (csvData.length() / 1024) + ' KB');

                    // Save CSV file
                    saveCsvFile(csvData, 1, meta.objectName);
                    System.debug('CSV saved: ' + meta.objectName
                               + ' (' + childRecords.size() + ' records)');
                    successCount++;

                } catch (Exception e) {
                    System.debug('Error processing ' + meta.objectName
                               + ': ' + e.getMessage());
                    System.debug('Stack: ' + e.getStackTraceString());
                    errorCount++;
                }
            }
        }

        System.debug('');
        System.debug('Chain complete. Success: ' + successCount
                   + ' | Errors: ' + errorCount);
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
    private static List<String> buildCsvLines(List<SObject> rows, List<String> fields) {
        List<String> lines = new List<String>();
        for (SObject row : rows) {
            List<String> cols = new List<String>();
            for (String f : fields) {
                Object value;
                if (f.contains('.')) {
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
            if (!String.isBlank(f)) fields.add(f.trim());
        }
        return fields;
    }

    private static String escapeCsv(String v) {
        String s = v.replace('"', '""');
        return (s.contains(',') || s.contains('\n') || s.contains('"'))
            ? '"' + s + '"' : s;
    }
}