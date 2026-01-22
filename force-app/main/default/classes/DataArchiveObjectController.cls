// // // // public with sharing class DataArchiveObjectController {

// // // //     /* =========================================================
// // // //        WRAPPER
// // // //     ========================================================= */
// // // //     public class ArchiveWrapper {
// // // //         @AuraEnabled public List<Map<String, Object>> columns { get; set; }
// // // //         @AuraEnabled public List<Map<String, Object>> data { get; set; }
// // // //         @AuraEnabled public Integer totalRecords { get; set; }
// // // //     }

// // // //     /* =========================================================
// // // //        PAGINATED ARCHIVE DATA
// // // //     ========================================================= */
// // // //     @AuraEnabled(cacheable=true)
// // // //     public static ArchiveWrapper getArchivedObjectPaginated(
// // // //         Integer pageNumber,
// // // //         Integer pageSize
// // // //     ) {
// // // //         if (pageNumber == null) pageNumber = 1;
// // // //         if (pageSize == null) pageSize = 10;

// // // //         Integer offsetValue = (pageNumber - 1) * pageSize;
// // // //         Integer totalCount = [SELECT COUNT() FROM Data_Archive__c];

// // // //         List<Data_Archive__c> records = [
// // // //             SELECT Id, Name, Fields__c, Parent_Object__c, CreatedDate
// // // //             FROM Data_Archive__c
// // // //             ORDER BY CreatedDate DESC
// // // //             LIMIT :pageSize
// // // //             OFFSET :offsetValue
// // // //         ];

// // // //         List<Map<String, Object>> columns = new List<Map<String, Object>>{
// // // //             new Map<String, Object>{
// // // //                 'label' => 'Data Archive Name',
// // // //                 'fieldName' => 'nameUrl',
// // // //                 'type' => 'url',
// // // //                 'typeAttributes' => new Map<String, Object>{
// // // //                     'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
// // // //                     'target' => '_blank'
// // // //                 }
// // // //             },
// // // //             new Map<String, Object>{ 'label' => 'Fields', 'fieldName' => 'Fields__c', 'type' => 'text' },
// // // //             new Map<String, Object>{ 'label' => 'Parent Object', 'fieldName' => 'Parent_Object__c', 'type' => 'text' },
// // // //             new Map<String, Object>{ 'label' => 'Created Date', 'fieldName' => 'CreatedDate', 'type' => 'text' },
// // // //             new Map<String, Object>{
// // // //                 'type' => 'button-icon',
// // // //                 'typeAttributes' => new Map<String, Object>{
// // // //                     'iconName' => 'utility:download',
// // // //                     'name' => 'downloadCsv',
// // // //                     'title' => 'Download CSV',
// // // //                     'variant' => 'border-filled',
// // // //                     'alternativeText' => 'Download CSV'
// // // //                 },
// // // //                 'initialWidth' => 50
// // // //             }
// // // //         };

// // // //         List<Map<String, Object>> processed = new List<Map<String, Object>>();
// // // //         for (Data_Archive__c rec : records) {
// // // //             processed.add(new Map<String, Object>{
// // // //                 'Id' => rec.Id,
// // // //                 'Name' => rec.Name,
// // // //                 'Fields__c' => rec.Fields__c,
// // // //                 'Parent_Object__c' => rec.Parent_Object__c,
// // // //                 'CreatedDate' => rec.CreatedDate,
// // // //                 'nameUrl' => '/' + rec.Id
// // // //             });
// // // //         }

// // // //         ArchiveWrapper wrapper = new ArchiveWrapper();
// // // //         wrapper.columns = columns;
// // // //         wrapper.data = processed;
// // // //         wrapper.totalRecords = totalCount;
// // // //         return wrapper;
// // // //     }

// // // //     /* =========================================================
// // // //        CSV DOWNLOAD
// // // //     ========================================================= */
// // // //     @AuraEnabled
// // // //     public static String getArchiveCsvDownloadUrl(Id archiveId) {
// // // //         List<ContentDocumentLink> links = [
// // // //             SELECT ContentDocumentId
// // // //             FROM ContentDocumentLink
// // // //             WHERE LinkedEntityId = :archiveId
// // // //             LIMIT 1
// // // //         ];
// // // //         if (links.isEmpty()) return null;
// // // //         return '/sfc/servlet.shepherd/document/download/' +
// // // //                links[0].ContentDocumentId;
// // // //     }

// // // //     /* =========================================================
// // // //        UNARCHIVE - FULLY OPTIMIZED
// // // //     ========================================================= */
// // // //     @AuraEnabled
// // // //     public static String insertArchivedRecordsBulk(List<Id> archiveRecordIds) {

// // // //         /* ---------- FETCH ARCHIVES ---------- */
// // // //         List<Data_Archive__c> archives = [
// // // //             SELECT Id, Name, Fields__c, Parent_Object__c
// // // //             FROM Data_Archive__c
// // // //             WHERE Id IN :archiveRecordIds
// // // //         ];
// // // //         if (archives.isEmpty()) return 'No archive records found';

// // // //         /* ---------- BULK CONTENT VERSION FETCH ---------- */
// // // //         Set<String> titles = new Set<String>();
// // // //         for (Data_Archive__c a : archives) titles.add(a.Name);

// // // //         Map<String, ContentVersion> contentByTitle = new Map<String, ContentVersion>();
// // // //         for (ContentVersion cv : [
// // // //             SELECT Title, VersionData, ContentDocumentId
// // // //             FROM ContentVersion
// // // //             WHERE Title IN :titles
// // // //             ORDER BY CreatedDate DESC
// // // //         ]) {
// // // //             if (!contentByTitle.containsKey(cv.Title)) {
// // // //                 contentByTitle.put(cv.Title, cv);
// // // //             }
// // // //         }

// // // //         /* ---------- DESCRIBE CACHE ---------- */
// // // //         Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
// // // //         Map<String, Map<String, Schema.SObjectField>> fieldCache =
// // // //             new Map<String, Map<String, Schema.SObjectField>>();

// // // //         List<SObject> recordsToInsert = new List<SObject>();
// // // //         Set<Id> contentDocIds = new Set<Id>();
// // // //         List<Id> archivesToDelete = new List<Id>();

// // // //         /* ---------- PROCESS EACH ARCHIVE ---------- */
// // // //         for (Data_Archive__c archive : archives) {

// // // //             if (!contentByTitle.containsKey(archive.Name)) continue;
// // // //             ContentVersion cv = contentByTitle.get(archive.Name);
// // // //             contentDocIds.add(cv.ContentDocumentId);

// // // //             if (!fieldCache.containsKey(archive.Parent_Object__c)) {
// // // //                 fieldCache.put(
// // // //                     archive.Parent_Object__c,
// // // //                     globalMap.get(archive.Parent_Object__c)
// // // //                              .getDescribe()
// // // //                              .fields.getMap()
// // // //                 );
// // // //             }

// // // //             Map<String, Schema.SObjectField> fieldMap =
// // // //                 fieldCache.get(archive.Parent_Object__c);

// // // //             /* ---------- HEADERS ---------- */
// // // //             List<String> headers = archive.Fields__c.split(',');

// // // //             Integer idIndex = -1;
// // // //             for (Integer h = 0; h < headers.size(); h++) {
// // // //                 if (headers[h].trim().equalsIgnoreCase('Id')) {
// // // //                     idIndex = h;
// // // //                     break;
// // // //                 }
// // // //             }
// // // //             if (idIndex >= 0) headers.remove(idIndex);

// // // //             /* ---------- CSV LINES ---------- */
// // // //             List<String> lines = cv.VersionData.toString().split('\n');

// // // //             for (Integer i = 1; i < lines.size(); i++) {
// // // //                 if (String.isBlank(lines[i])) continue;

// // // //                 List<String> values = lines[i].split(',');
// // // //                 if (idIndex >= 0 && idIndex < values.size()) values.remove(idIndex);

// // // //                 SObject sobj =
// // // //                     globalMap.get(archive.Parent_Object__c).newSObject();

// // // //                 for (Integer j = 0;
// // // //                      j < headers.size() && j < values.size();
// // // //                      j++) {

// // // //                     String fieldAPI = headers[j].trim();
// // // //                     String rawVal = values[j].replace('"', '').trim();

// // // //                     if (!fieldMap.containsKey(fieldAPI)) continue;

// // // //                     Schema.DescribeFieldResult d =
// // // //                         fieldMap.get(fieldAPI).getDescribe();

// // // //                     if (!d.isCreateable() || d.isCalculated()) continue;

// // // //                     try {
// // // //                         switch on d.getType() {
// // // //                             when Boolean {
// // // //                                 sobj.put(fieldAPI, rawVal == 'true');
// // // //                             }
// // // //                             when Integer {
// // // //                                 sobj.put(fieldAPI,
// // // //                                     rawVal == '' ? null : Integer.valueOf(rawVal));
// // // //                             }
// // // //                             when Double, Currency, Percent {
// // // //                                 sobj.put(fieldAPI,
// // // //                                     rawVal == '' ? null : Decimal.valueOf(rawVal));
// // // //                             }
// // // //                             when Date {
// // // //                                 sobj.put(fieldAPI,
// // // //                                     rawVal == '' ? null : Date.valueOf(rawVal));
// // // //                             }
// // // //                             when DateTime {
// // // //                                 sobj.put(fieldAPI,
// // // //                                     rawVal == '' ? null : Datetime.valueOf(rawVal));
// // // //                             }
// // // //                             when else {
// // // //                                 sobj.put(fieldAPI, rawVal);
// // // //                             }
// // // //                         }
// // // //                     } catch (Exception e) {
// // // //                         sobj.put(fieldAPI, null);
// // // //                     }
// // // //                 }

// // // //                 recordsToInsert.add(sobj);
// // // //             }

// // // //             archivesToDelete.add(archive.Id);
// // // //         }

// // // //         if (recordsToInsert.isEmpty())
// // // //             return 'No valid records found';

// // // //         /* ---------- DUPLICATE RULE OPTIONS ---------- */
// // // //         Database.DMLOptions opts = new Database.DMLOptions();
// // // //         opts.DuplicateRuleHeader.allowSave = true;
// // // //         opts.DuplicateRuleHeader.runAsCurrentUser = true;

// // // //         /* ---------- CHUNKED INSERT ---------- */
// // // //         Integer successCount = 0;
// // // //         List<SObject> chunk = new List<SObject>();

// // // //         for (SObject s : recordsToInsert) {
// // // //             s.setOptions(opts);
// // // //             chunk.add(s);

// // // //             if (chunk.size() == 200) {
// // // //                 for (Database.SaveResult r :
// // // //                         Database.insert(chunk, false)) {
// // // //                     if (r.isSuccess()) successCount++;
// // // //                 }
// // // //                 chunk.clear();
// // // //             }
// // // //         }

// // // //         if (!chunk.isEmpty()) {
// // // //             for (Database.SaveResult r :
// // // //                     Database.insert(chunk, false)) {
// // // //                 if (r.isSuccess()) successCount++;
// // // //             }
// // // //         }

// // // //         /* ---------- CLEANUP ---------- */
// // // //         delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archivesToDelete];
// // // //         delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocIds];

// // // //         return 'Inserted ' + successCount + ' record(s) successfully.';
// // // //     }
// // // // }
// // // // public with sharing class DataArchiveObjectController {

// // // //     /* =========================================================
// // // //        WRAPPER
// // // //     ========================================================= */
// // // //     public class ArchiveWrapper {
// // // //         @AuraEnabled public List<Map<String, Object>> columns { get; set; }
// // // //         @AuraEnabled public List<Map<String, Object>> data { get; set; }
// // // //         @AuraEnabled public Integer totalRecords { get; set; }
// // // //     }

// // // //     /* =========================================================
// // // //        PAGINATION – USED BY DATA TABLE
// // // //     ========================================================= */
// // // //     @AuraEnabled(cacheable=true)
// // // //     public static ArchiveWrapper getArchivedObjectPaginated(
// // // //         Integer pageNumber,
// // // //         Integer pageSize
// // // //     ) {
// // // //         if (pageNumber == null) pageNumber = 1;
// // // //         if (pageSize == null) pageSize = 10;

// // // //         Integer offsetValue = (pageNumber - 1) * pageSize;
// // // //         Integer totalCount = [SELECT COUNT() FROM Data_Archive__c];

// // // //         List<Data_Archive__c> records = [
// // // //             SELECT Id, Name, Fields__c, Parent_Object__c, CreatedDate
// // // //             FROM Data_Archive__c
// // // //             ORDER BY CreatedDate DESC
// // // //             LIMIT :pageSize
// // // //             OFFSET :offsetValue
// // // //         ];

// // // //         List<Map<String, Object>> columns = new List<Map<String, Object>>{
// // // //             new Map<String, Object>{
// // // //                 'label' => 'Data Archive Name',
// // // //                 'fieldName' => 'nameUrl',
// // // //                 'type' => 'url',
// // // //                 'typeAttributes' => new Map<String, Object>{
// // // //                     'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
// // // //                     'target' => '_blank'
// // // //                 }
// // // //             },
// // // //             new Map<String, Object>{ 'label' => 'Fields', 'fieldName' => 'Fields__c', 'type' => 'text' },
// // // //             new Map<String, Object>{ 'label' => 'Parent Object', 'fieldName' => 'Parent_Object__c', 'type' => 'text' },
// // // //             new Map<String, Object>{ 'label' => 'Created Date', 'fieldName' => 'CreatedDate', 'type' => 'text' }
// // // //         };

// // // //         List<Map<String, Object>> rows = new List<Map<String, Object>>();
// // // //         for (Data_Archive__c r : records) {
// // // //             rows.add(new Map<String, Object>{
// // // //                 'Id' => r.Id,
// // // //                 'Name' => r.Name,
// // // //                 'Fields__c' => r.Fields__c,
// // // //                 'Parent_Object__c' => r.Parent_Object__c,
// // // //                 'CreatedDate' => r.CreatedDate,
// // // //                 'nameUrl' => '/' + r.Id
// // // //             });
// // // //         }

// // // //         ArchiveWrapper w = new ArchiveWrapper();
// // // //         w.columns = columns;
// // // //         w.data = rows;
// // // //         w.totalRecords = totalCount;
// // // //         return w;
// // // //     }

// // // //     /* =========================================================
// // // //        UNARCHIVE – FINAL FIXED VERSION
// // // //     ========================================================= */
// // // //     @AuraEnabled
// // // //     public static String insertArchivedRecordsBulk(List<Id> archiveRecordIds) {

// // // //         List<Data_Archive__c> archives = [
// // // //             SELECT Id, Name, Parent_Object__c
// // // //             FROM Data_Archive__c
// // // //             WHERE Id IN :archiveRecordIds
// // // //         ];
// // // //         if (archives.isEmpty()) return 'No archive records found';

// // // //         Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
// // // //         Integer inserted = 0;

// // // //         List<SObject> buffer = new List<SObject>();
// // // //         Set<Id> archiveIdsToDelete = new Set<Id>();
// // // //         Set<Id> contentDocIds = new Set<Id>();

// // // //         for (Data_Archive__c archive : archives) {

// // // //             Schema.SObjectType objType = globalMap.get(archive.Parent_Object__c);
// // // //             if (objType == null) continue;

// // // //             Map<String, Schema.SObjectField> fieldMap =
// // // //                 objType.getDescribe().fields.getMap();

// // // //             List<ContentVersion> files = [
// // // //                 SELECT VersionData, ContentDocumentId
// // // //                 FROM ContentVersion
// // // //                 WHERE Title = :archive.Name
// // // //                 AND FileType = 'CSV'
// // // //             ];

// // // //             for (ContentVersion cv : files) {

// // // //                 contentDocIds.add(cv.ContentDocumentId);
// // // //                 List<String> lines = splitLines(cv.VersionData.toString());
// // // //                 if (lines.size() < 2) continue;

// // // //                 List<String> headers = parseCsvLine(lines[0]);

// // // //                 Map<Integer, Schema.DescribeFieldResult> indexMap =
// // // //                     new Map<Integer, Schema.DescribeFieldResult>();

// // // //                 for (Integer i = 0; i < headers.size(); i++) {
// // // //                     String f = headers[i].trim();
// // // //                     if (f.equalsIgnoreCase('Id')) continue;
// // // //                     if (!fieldMap.containsKey(f)) continue;

// // // //                     Schema.DescribeFieldResult d =
// // // //                         fieldMap.get(f).getDescribe();

// // // //                     if (!d.isCreateable() || d.isCalculated()) continue;
// // // //                     indexMap.put(i, d);
// // // //                 }

// // // //                 if (indexMap.isEmpty()) continue;

// // // //                 for (Integer r = 1; r < lines.size(); r++) {
// // // //                     if (String.isBlank(lines[r])) continue;

// // // //                     List<String> values = parseCsvLine(lines[r]);
// // // //                     SObject sobj = objType.newSObject();
// // // //                     Boolean hasData = false;

// // // //                     for (Integer i : indexMap.keySet()) {
// // // //                         if (i >= values.size()) continue;

// // // //                         String raw = values[i].trim();
// // // //                         if (raw == '') continue;

// // // //                         Schema.DescribeFieldResult d = indexMap.get(i);
// // // //                         try {
// // // //                             sobj.put(
// // // //                                 d.getName(),
// // // //                                 convertValue(raw, d.getType())
// // // //                             );
// // // //                             hasData = true;
// // // //                         } catch (Exception ignore) {}
// // // //                     }

// // // //                     if (hasData) buffer.add(sobj);

// // // //                     if (buffer.size() == 200) {
// // // //                         inserted += Database.insert(buffer, false).size();
// // // //                         buffer.clear();
// // // //                     }
// // // //                 }
// // // //             }

// // // //             archiveIdsToDelete.add(archive.Id);
// // // //         }

// // // //         if (!buffer.isEmpty()) {
// // // //             inserted += Database.insert(buffer, false).size();
// // // //         }

// // // //         if (inserted == 0) return 'No valid records found to insert';

// // // //         delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archiveIdsToDelete];
// // // //         delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocIds];

// // // //         return 'Inserted ' + inserted + ' record(s) successfully.';
// // // //     }

// // // //     /* =========================================================
// // // //        HELPERS
// // // //     ========================================================= */
// // // //     private static Object convertValue(String v, Schema.DisplayType t) {
// // // //         switch on t {
// // // //             when Boolean   { return v.toLowerCase() == 'true'; }
// // // //             when Integer   { return Integer.valueOf(v); }
// // // //             when Double, Currency, Percent { return Decimal.valueOf(v); }
// // // //             when Date      { return Date.valueOf(v); }
// // // //             when DateTime  { return Datetime.valueOf(v); }
// // // //             when else      { return v; }
// // // //         }
// // // //     }

// // // //     private static List<String> parseCsvLine(String line) {
// // // //         List<String> out = new List<String>();
// // // //         Boolean inQuotes = false;
// // // //         String cur = '';

// // // //         for (Integer i = 0; i < line.length(); i++) {
// // // //             String c = line.substring(i, i + 1);
// // // //             if (c == '"') inQuotes = !inQuotes;
// // // //             else if (c == ',' && !inQuotes) {
// // // //                 out.add(cur);
// // // //                 cur = '';
// // // //             } else cur += c;
// // // //         }
// // // //         out.add(cur);
// // // //         return out;
// // // //     }

// // // //     private static List<String> splitLines(String text) {
// // // //         List<String> lines = new List<String>();
// // // //         String cur = '';
// // // //         for (Integer i = 0; i < text.length(); i++) {
// // // //             String c = text.substring(i, i + 1);
// // // //             if (c == '\n') {
// // // //                 lines.add(cur);
// // // //                 cur = '';
// // // //             } else if (c != '\r') {
// // // //                 cur += c;
// // // //             }
// // // //         }
// // // //         if (cur != '') lines.add(cur);
// // // //         return lines;
// // // //     }
// // // // }
// // // public with sharing class DataArchiveObjectController {

// // //     /* =========================================================
// // //        WRAPPER FOR DATA TABLE
// // //     ========================================================= */
// // //     public class ArchiveWrapper {
// // //         @AuraEnabled public List<Map<String, Object>> columns;
// // //         @AuraEnabled public List<Map<String, Object>> data;
// // //         @AuraEnabled public Integer totalRecords;
// // //     }

// // //     /* =========================================================
// // //        PAGINATION – DATA TABLE
// // //     ========================================================= */
// // //     @AuraEnabled(cacheable=true)
// // //     public static ArchiveWrapper getArchivedObjectPaginated(
// // //         Integer pageNumber,
// // //         Integer pageSize
// // //     ) {
// // //         if (pageNumber == null) pageNumber = 1;
// // //         if (pageSize == null) pageSize = 10;

// // //         Integer offsetVal = (pageNumber - 1) * pageSize;

// // //         Integer totalCount = [SELECT COUNT() FROM Data_Archive__c];

// // //         List<Data_Archive__c> records = [
// // //             SELECT Id, Name, Fields__c, Parent_Object__c, CreatedDate
// // //             FROM Data_Archive__c
// // //             ORDER BY CreatedDate DESC
// // //             LIMIT :pageSize OFFSET :offsetVal
// // //         ];

// // //         List<Map<String, Object>> columns = new List<Map<String, Object>>{
// // //             new Map<String, Object>{
// // //                 'label' => 'Archive Name',
// // //                 'fieldName' => 'nameUrl',
// // //                 'type' => 'url',
// // //                 'typeAttributes' => new Map<String, Object>{
// // //                     'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
// // //                     'target' => '_blank'
// // //                 }
// // //             },
// // //             new Map<String, Object>{ 'label' => 'Fields', 'fieldName' => 'Fields__c', 'type' => 'text' },
// // //             new Map<String, Object>{ 'label' => 'Parent Object', 'fieldName' => 'Parent_Object__c', 'type' => 'text' },
// // //             new Map<String, Object>{ 'label' => 'Created Date', 'fieldName' => 'CreatedDate', 'type' => 'text' },
// // //             new Map<String, Object>{
// // //                 'type' => 'button-icon',
// // //                 'typeAttributes' => new Map<String, Object>{
// // //                     'iconName' => 'utility:download',
// // //                     'name' => 'downloadCsv',
// // //                     'title' => 'Download CSV'
// // //                 },
// // //                 'initialWidth' => 60
// // //             }
// // //         };

// // //         List<Map<String, Object>> rows = new List<Map<String, Object>>();
// // //         for (Data_Archive__c r : records) {
// // //             rows.add(new Map<String, Object>{
// // //                 'Id' => r.Id,
// // //                 'Name' => r.Name,
// // //                 'Fields__c' => r.Fields__c,
// // //                 'Parent_Object__c' => r.Parent_Object__c,
// // //                 'CreatedDate' => r.CreatedDate,
// // //                 'nameUrl' => '/' + r.Id
// // //             });
// // //         }

// // //         ArchiveWrapper w = new ArchiveWrapper();
// // //         w.columns = columns;
// // //         w.data = rows;
// // //         w.totalRecords = totalCount;
// // //         return w;
// // //     }

// // //     /* =========================================================
// // //        CSV DOWNLOAD
// // //     ========================================================= */
// // //     @AuraEnabled
// // //     public static String getArchiveCsvDownloadUrl(Id archiveId) {

// // //         List<ContentDocumentLink> links = [
// // //             SELECT ContentDocumentId
// // //             FROM ContentDocumentLink
// // //             WHERE LinkedEntityId = :archiveId
// // //             ORDER BY SystemModstamp DESC
// // //             LIMIT 1
// // //         ];

// // //         if (links.isEmpty()) return null;

// // //         return '/sfc/servlet.shepherd/document/download/' +
// // //                links[0].ContentDocumentId;
// // //     }

// // //     /* =========================================================
// // //        ASYNC UNARCHIVE (QUEUEABLE)
// // //     ========================================================= */
// // //     @AuraEnabled
// // //     public static String unarchiveAsync(List<Id> archiveRecordIds) {

// // //         if (archiveRecordIds == null || archiveRecordIds.isEmpty()) {
// // //             return 'No records selected';
// // //         }

// // //         System.enqueueJob(
// // //             new DataArchiveUnarchiveQueueable(archiveRecordIds)
// // //         );

// // //         return 'Un-archive started in background';
// // //     }
// // // }


// // public with sharing class DataArchiveObjectController {

// //     /* ================= WRAPPER ================= */
// //     public class ArchiveWrapper {
// //         @AuraEnabled public List<Map<String, Object>> columns;
// //         @AuraEnabled public List<Map<String, Object>> data;
// //         @AuraEnabled public Integer totalRecords;
// //     }

// //     /* ================= PAGINATION ================= */
// //     @AuraEnabled(cacheable=true)
// //     public static ArchiveWrapper getArchivedObjectPaginated(
// //         Integer pageNumber,
// //         Integer pageSize
// //     ) {
// //         if (pageNumber == null) pageNumber = 1;
// //         if (pageSize == null) pageSize = 5;

// //         Integer offsetVal = (pageNumber - 1) * pageSize;

// //         Integer totalCount = [
// //             SELECT COUNT() FROM Data_Archive__c
// //         ];

// //         List<Data_Archive__c> records = [
// //             SELECT Id, Name, Fields__c, Parent_Object__c, Status__c
// //             FROM Data_Archive__c
// //             ORDER BY CreatedDate DESC
// //             LIMIT :pageSize OFFSET :offsetVal
// //         ];

// //         /* ===== COLUMNS (EXACTLY WHAT YOU ASKED) ===== */
// //         List<Map<String, Object>> columns = new List<Map<String, Object>>{
// //             new Map<String, Object>{ 'label'=>'Data Archive Name', 'fieldName'=>'Name', 'type'=>'text' },
// //             new Map<String, Object>{ 'label'=>'Fields', 'fieldName'=>'Fields__c', 'type'=>'text' },
// //             new Map<String, Object>{ 'label'=>'Parent Object', 'fieldName'=>'Parent_Object__c', 'type'=>'text' },
// //             new Map<String, Object>{ 'label'=>'Status', 'fieldName'=>'Status__c', 'type'=>'text' }
// //         };

// //         List<Map<String, Object>> rows = new List<Map<String, Object>>();
// //         for (Data_Archive__c r : records) {
// //             rows.add(new Map<String, Object>{
// //                 'Id' => r.Id,
// //                 'Name' => r.Name,
// //                 'Fields__c' => r.Fields__c,
// //                 'Parent_Object__c' => r.Parent_Object__c,
// //                 'Status__c' => r.Status__c,

// //                 // 🔒 Used by datatable to disable selection
// //                 'isSelectable' => r.Status__c == 'Ready for Unarchive'
// //             });
// //         }

// //         ArchiveWrapper w = new ArchiveWrapper();
// //         w.columns = columns;
// //         w.data = rows;
// //         w.totalRecords = totalCount;
// //         return w;
// //     }

// //     /* ================= START ASYNC ================= */
// //     @AuraEnabled
// //     public static String unarchiveAsync(List<Id> archiveRecordIds) {

// //         if (archiveRecordIds == null || archiveRecordIds.isEmpty()) {
// //             return 'No records selected';
// //         }

// //         /* 🔥 IMMEDIATE STATUS UPDATE */
// //         List<Data_Archive__c> updates = new List<Data_Archive__c>();
// //         for (Id i : archiveRecordIds) {
// //             updates.add(new Data_Archive__c(
// //                 Id = i,
// //                 Status__c = 'In Progress'
// //             ));
// //         }
// //         update updates;

// //         System.enqueueJob(
// //             new DataArchiveUnarchiveQueueable(archiveRecordIds)
// //         );

// //         return 'Un-archive started in background. This may take a few minutes.';
// //     }
// // }
// public with sharing class DataArchiveObjectController {

//     /* ================= WRAPPER ================= */
//     public class ArchiveWrapper {
//         @AuraEnabled public List<Map<String, Object>> columns;
//         @AuraEnabled public List<Map<String, Object>> data;
//         @AuraEnabled public Integer totalRecords;
//     }

//     /* ================= PAGINATION ================= */
//     @AuraEnabled(cacheable=true)
//     public static ArchiveWrapper getArchivedObjectPaginated(
//         Integer pageNumber,
//         Integer pageSize
//     ) {
//         if (pageNumber == null) pageNumber = 1;
//         if (pageSize == null) pageSize = 5;

//         Integer offsetVal = (pageNumber - 1) * pageSize;

//         Integer totalCount = [
//             SELECT COUNT() FROM Data_Archive__c
//         ];

//         List<Data_Archive__c> records = [
//             SELECT Id, Name, Fields__c, Parent_Object__c, Status__c
//             FROM Data_Archive__c
//             ORDER BY CreatedDate DESC
//             LIMIT :pageSize OFFSET :offsetVal
//         ];

//         /* ===== COLUMNS (WITH CLICKABLE ARCHIVE NAME) ===== */
//         List<Map<String, Object>> columns = new List<Map<String, Object>>{
//             new Map<String, Object>{
//                 'label' => 'Data Archive Name',
//                 'fieldName' => 'recordUrl',
//                 'type' => 'url',
//                 'typeAttributes' => new Map<String, Object>{
//                     'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
//                     'target' => '_blank'
//                 }
//             },
//             new Map<String, Object>{
//                 'label' => 'Fields',
//                 'fieldName' => 'Fields__c',
//                 'type' => 'text'
//             },
//             new Map<String, Object>{
//                 'label' => 'Parent Object',
//                 'fieldName' => 'Parent_Object__c',
//                 'type' => 'text'
//             },
//             new Map<String, Object>{
//                 'label' => 'Status',
//                 'fieldName' => 'Status__c',
//                 'type' => 'text'
//             },
//             new Map<String, Object>{
//     'type' => 'button-icon',
//     'initialWidth' => 60,
//     'typeAttributes' => new Map<String, Object>{
//         'iconName' => 'utility:download',
//         'name' => 'downloadCsv',
//         'title' => 'Download All CSV'
//     }
// }
//         };

//         /* ===== ROW DATA ===== */
//         List<Map<String, Object>> rows = new List<Map<String, Object>>();
//         for (Data_Archive__c r : records) {
//             rows.add(new Map<String, Object>{
//                 'Id' => r.Id,
//                 'Name' => r.Name,
//                 'Fields__c' => r.Fields__c,
//                 'Parent_Object__c' => r.Parent_Object__c,
//                 'Status__c' => r.Status__c,

//                 //  Redirect to Data_Archive__c record page
//                 'recordUrl' => '/' + r.Id,

//                 //  Disable row selection if not ready
//                 'isSelectable' => r.Status__c == 'Ready for Unarchive'
//             });
//         }

//         ArchiveWrapper w = new ArchiveWrapper();
//         w.columns = columns;
//         w.data = rows;
//         w.totalRecords = totalCount;
//         return w;
//     }
//     /* ================= DOWNLOAD ALL CSV FILES ================= */
// @AuraEnabled
// public static List<String> getAllArchiveCsvDownloadUrls(Id archiveId) {

//     List<String> urls = new List<String>();

//     for (ContentDocumentLink cdl : [
//         SELECT ContentDocumentId
//         FROM ContentDocumentLink
//         WHERE LinkedEntityId = :archiveId
//         ORDER BY SystemModstamp DESC
//     ]) {
//         urls.add(
//             '/sfc/servlet.shepherd/document/download/' +
//             cdl.ContentDocumentId
//         );
//     }

//     return urls;
// }


//     /* ================= START ASYNC ================= */
//     @AuraEnabled
//     public static String unarchiveAsync(List<Id> archiveRecordIds) {

//         if (archiveRecordIds == null || archiveRecordIds.isEmpty()) {
//             return 'No records selected';
//         }

//         /*  IMMEDIATE STATUS UPDATE */
//         List<Data_Archive__c> updates = new List<Data_Archive__c>();
//         for (Id i : archiveRecordIds) {
//             updates.add(new Data_Archive__c(
//                 Id = i,
//                 Status__c = 'In Progress'
//             ));
//         }
//         update updates;

//         System.enqueueJob(
//             new DataArchiveUnarchiveQueueable(archiveRecordIds)
//         );

//         return 'Un-archive started in background. This may take a few minutes.';
//     }
// }
public with sharing class DataArchiveObjectController {

    /* ================= WRAPPER ================= */
    public class ArchiveWrapper {
        @AuraEnabled public List<Map<String, Object>> columns;
        @AuraEnabled public List<Map<String, Object>> data;
        @AuraEnabled public Integer totalRecords;
    }

    /* ================= PAGINATION ================= */
    @AuraEnabled(cacheable=true)
    public static ArchiveWrapper getArchivedObjectPaginated(
        Integer pageNumber,
        Integer pageSize
    ) {
        if (pageNumber == null) pageNumber = 1;
        if (pageSize == null) pageSize = 5;

        Integer offsetVal = (pageNumber - 1) * pageSize;

        Integer totalCount = [
            SELECT COUNT() FROM Data_Archive__c
        ];

        List<Data_Archive__c> records = [
            SELECT Id, Name, Fields__c, Parent_Object__c, Status__c
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
            LIMIT :pageSize OFFSET :offsetVal
        ];

        List<Map<String, Object>> columns = new List<Map<String, Object>>{
            new Map<String, Object>{
                'label' => 'Data Archive Name',
                'fieldName' => 'recordUrl',
                'type' => 'url',
                'typeAttributes' => new Map<String, Object>{
                    'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
                    'target' => '_blank'
                }
            },
            new Map<String, Object>{
                'label' => 'Fields',
                'fieldName' => 'Fields__c',
                'type' => 'text'
            },
            new Map<String, Object>{
                'label' => 'Parent Object',
                'fieldName' => 'Parent_Object__c',
                'type' => 'text'
            },
            new Map<String, Object>{
    'label' => 'Status',
    'fieldName' => 'Status__c',
    'type' => 'text',
    'cellAttributes' => new Map<String, Object>{
        'class' => new Map<String, Object>{
            'fieldName' => 'statusClass'
        }
    }
}

            // new Map<String, Object>{
            //     'type' => 'button-icon',
            //     'initialWidth' => 60,
            //     'typeAttributes' => new Map<String, Object>{
            //         'iconName' => 'utility:download',
            //         'name' => 'downloadCsv',
            //         'title' => 'Download All CSV'
            //     }
            // }
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Data_Archive__c r : records) {

          

            rows.add(new Map<String, Object>{
    'Id' => r.Id,
    'Name' => r.Name,
    'Fields__c' => r.Fields__c,
    'Parent_Object__c' => r.Parent_Object__c,
    'Status__c' => r.Status__c,
    'recordUrl' => '/' + r.Id,
    'isSelectable' => r.Status__c == 'Ready for Unarchive',
    'statusClass' =>
        r.Status__c == 'In Progress'
        ? 'slds-text-color_success slds-text-title_bold'
        : ''
});
        }

        ArchiveWrapper w = new ArchiveWrapper();
        w.columns = columns;
        w.data = rows;
        w.totalRecords = totalCount;
        return w;
    }

    /* ================= DOWNLOAD ALL CSV FILES ================= */
    // @AuraEnabled
    // public static List<String> getAllArchiveCsvDownloadUrls(Id archiveId) {

    //     List<String> urls = new List<String>();

    //     for (ContentDocumentLink cdl : [
    //         SELECT ContentDocumentId
    //         FROM ContentDocumentLink
    //         WHERE LinkedEntityId = :archiveId
    //         
    //     ]) {
    //         urls.add(
    //             '/sfc/servlet.shepherd/document/download/' +
    //             cdl.ContentDocumentId
    //         );
    //     }
    //     return urls;
    // }

    /* ================= START ASYNC ================= */
    @AuraEnabled
    public static String unarchiveAsync(List<Id> archiveRecordIds) {

        if (archiveRecordIds == null || archiveRecordIds.isEmpty()) {
            return 'No records selected';
        }

        List<Data_Archive__c> updates = new List<Data_Archive__c>();
        for (Id i : archiveRecordIds) {
            updates.add(
                new Data_Archive__c(
                    Id = i,
                    Status__c = 'In Progress'
                )
            );
        }
        update updates;

        System.enqueueJob(
            new DataArchiveUnarchiveQueueable(archiveRecordIds)
        );

        return 'Un-archive started in background. This may take a few minutes.';
    }
}

// public with sharing class DataArchiveObjectController {

//     /* ================= WRAPPER ================= */
//     public class ArchiveWrapper {
//         @AuraEnabled public List<Map<String, Object>> columns;
//         @AuraEnabled public List<Map<String, Object>> data;
//         @AuraEnabled public Integer totalRecords;
//     }

//     /* ================= PAGINATION ================= */
//     @AuraEnabled(cacheable=true)
//     public static ArchiveWrapper getArchivedObjectPaginated(
//         Integer pageNumber,
//         Integer pageSize
//     ) {
//         if (pageNumber == null) pageNumber = 1;
//         if (pageSize == null) pageSize = 5;

//         Integer offsetVal = (pageNumber - 1) * pageSize;

//         Integer totalCount = [
//             SELECT COUNT() FROM Data_Archive__c
//         ];

//         List<Data_Archive__c> records = [
//             SELECT Id, Name, Fields__c, Parent_Object__c, Status__c
//             FROM Data_Archive__c
//             ORDER BY CreatedDate DESC
//             LIMIT :pageSize OFFSET :offsetVal
//         ];

//         /* ================= COLUMNS ================= */
//         List<Map<String, Object>> columns = new List<Map<String, Object>>{
//             new Map<String, Object>{
//                 'label' => 'Data Archive Name',
//                 'fieldName' => 'recordUrl',
//                 'type' => 'url',
//                 'typeAttributes' => new Map<String, Object>{
//                     'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
//                     'target' => '_blank'
//                 }
//             },
//             new Map<String, Object>{
//                 'label' => 'Fields',
//                 'fieldName' => 'Fields__c',
//                 'type' => 'text'
//             },
//             new Map<String, Object>{
//                 'label' => 'Parent Object',
//                 'fieldName' => 'Parent_Object__c',
//                 'type' => 'text'
//             },
//             new Map<String, Object>{
//                 'label' => 'Status',
//                 'fieldName' => 'Status__c',
//                 'type' => 'text',
//                 'cellAttributes' => new Map<String, Object>{
//                     'class' => new Map<String, Object>{
//                         'fieldName' => 'statusClass'
//                     }
//                 }
//             },

//             // ✅ Download button column
//             new Map<String, Object>{
//                 'type' => 'button-icon',
//                 'initialWidth' => 60,
//                 'typeAttributes' => new Map<String, Object>{
//                     'iconName' => 'utility:download',
//                     'name' => 'downloadCsv',
//                     'title' => 'Download All CSV',
//                     'variant' => 'border-filled',
//                     'alternativeText' => 'Download CSV'
//                 }
//             }
//         };

//         /* ================= ROWS ================= */
//         List<Map<String, Object>> rows = new List<Map<String, Object>>();

//         for (Data_Archive__c r : records) {

//             String statusClass = '';
//             if (r.Status__c == 'In Progress') {
//                 statusClass = 'slds-text-color_success slds-text-title_bold';
//             }

//             rows.add(new Map<String, Object>{
//                 'Id' => r.Id,
//                 'Name' => r.Name,
//                 'Fields__c' => r.Fields__c,
//                 'Parent_Object__c' => r.Parent_Object__c,
//                 'Status__c' => r.Status__c,
//                 'recordUrl' => '/' + r.Id,

//                 // disable selection if not ready
//                 'isSelectable' => r.Status__c == 'Ready for Unarchive',

//                 // for status color
//                 'statusClass' => statusClass
//             });
//         }

//         ArchiveWrapper w = new ArchiveWrapper();
//         w.columns = columns;
//         w.data = rows;
//         w.totalRecords = totalCount;
//         return w;
//     }

//     /* ================= DOWNLOAD ALL CSV FILES ================= */
//     @AuraEnabled
//     public static List<String> getAllArchiveCsvDownloadUrls(Id archiveId) {

//         List<String> urls = new List<String>();

//         // 1) Get all linked documents
//         List<ContentDocumentLink> links = [
//             SELECT ContentDocumentId
//             FROM ContentDocumentLink
//             WHERE LinkedEntityId = :archiveId
//             ORDER BY SystemModstamp DESC
//         ];

//         if (links.isEmpty()) return urls;

//         Set<Id> docIds = new Set<Id>();
//         for (ContentDocumentLink cdl : links) {
//             docIds.add(cdl.ContentDocumentId);
//         }

//         // 2) Filter only CSV latest versions
//         List<ContentVersion> csvFiles = [
//             SELECT ContentDocumentId, FileExtension
//             FROM ContentVersion
//             WHERE ContentDocumentId IN :docIds
//             AND IsLatest = true
//             AND FileExtension = 'csv'
//         ];

//         Set<Id> csvDocIds = new Set<Id>();
//         for (ContentVersion cv : csvFiles) {
//             csvDocIds.add(cv.ContentDocumentId);
//         }

//         // 3) Create download URLs
//         for (Id docId : csvDocIds) {
//             urls.add('/sfc/servlet.shepherd/document/download/' + docId);
//         }

//         return urls;
//     }

//     /* ================= START ASYNC ================= */
//     @AuraEnabled
//     public static String unarchiveAsync(List<Id> archiveRecordIds) {

//         if (archiveRecordIds == null || archiveRecordIds.isEmpty()) {
//             return 'No records selected';
//         }

//         // update status immediately
//         List<Data_Archive__c> updates = new List<Data_Archive__c>();
//         for (Id i : archiveRecordIds) {
//             updates.add(new Data_Archive__c(
//                 Id = i,
//                 Status__c = 'In Progress'
//             ));
//         }
//         update updates;

//         // run queueable
//         System.enqueueJob(new DataArchiveUnarchiveQueueable(archiveRecordIds));

//         return 'Un-archive started in background. This may take a few minutes.';
//     }
// }