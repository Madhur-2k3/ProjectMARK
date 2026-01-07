// public with sharing class DataArchiveController {

//     /* =====================================================
//      *   PUBLIC METHOD #1 — ARCHIVE SELECTED RECORDS
//      * ===================================================== */
//     @AuraEnabled
//     public static Id archiveSelectedRecords(
//         String objectName,
//         List<Id> recordIds,
//         String fieldsCsv
//     ) {
//         if (recordIds == null || recordIds.isEmpty()) {
//             throw new AuraHandledException('Select at least one record to archive.');
//         }

//         // Build SOQL
//         String soql = buildSoqlForSelected(objectName, recordIds, fieldsCsv);

//         // Delegate to reusable archive engine
//         return archiveEngine(objectName, fieldsCsv, soql);
//     }



//     /* =====================================================
//      *   PUBLIC METHOD #2 — ARCHIVE ALL RECORDS (FULL QUERY)
//      * ===================================================== */
//     @AuraEnabled
//     public static Id archiveAllRecords(
//         String objectName,
//         String fieldsCsv,
//         String fullQuery
//     ) {
//         if (String.isBlank(fullQuery)) {
//             throw new AuraHandledException('Full query is required.');
//         }

//         // Replace SELECT fields in fullQuery
        

//         return archiveEngine(objectName, fieldsCsv, fullQuery);
//     }



//     /* =====================================================
//      *   CORE ARCHIVE ENGINE (USED BY BOTH METHODS)
//      * ===================================================== */
//     private static Id archiveEngine(
//         String objectName,
//         String fieldsCsv,
//         String soql
//     ) {
//         validateInputs(objectName, fieldsCsv);

//         // Normalize Fields
//         List<String> fields = normalizeFields(fieldsCsv);

//         // Query records
//         List<SObject> rows = Database.query(soql);

//         if (rows.isEmpty()) {
//             throw new AuraHandledException('No records found to archive.');
//         }

//         // Create Archive Header
//         Data_Archive__c archiveRecord = new Data_Archive__c(
//             Parent_Object__c = objectName,
//             Fields__c = String.join(fields, ',')
//         );
//         insert archiveRecord;

//         archiveRecord = [
//             SELECT Id, Name
//             FROM Data_Archive__c
//             WHERE Id = :archiveRecord.Id
//             LIMIT 1
//         ];

//         // Build CSV
//         String csvData = buildCsv(rows, fields);

//         // Save CSV File
//         ContentVersion cv = new ContentVersion(
//             Title = archiveRecord.Name,
//             PathOnClient = archiveRecord.Name + '.csv',
//             VersionData = Blob.valueOf(csvData)
//         );

//         insert cv;

//         ContentVersion insertedCv = [
//             SELECT Id, ContentDocumentId
//             FROM ContentVersion
//             WHERE Id = :cv.Id LIMIT 1
//         ];

//         // Link to Archive record
//         insert new ContentDocumentLink(
//             ContentDocumentId = insertedCv.ContentDocumentId,
//             LinkedEntityId = archiveRecord.Id,
//             ShareType = 'V',
//             Visibility = 'AllUsers'
//         );

//         // Delete original records
//         delete rows;

//         return archiveRecord.Id;
//     }



//     /* =====================================================
//      *               SOQL BUILDERS
//      * ===================================================== */

//     private static String buildSoqlForSelected(
//     String objectName,
//     List<Id> recordIds,
//     String fieldsCsv
// ) {
//     List<String> fields = normalizeFields(fieldsCsv);

//     // Ensure Id is present
//     if (!fields.contains('Id')) fields.add('Id');

//     // Convert Ids into quoted string list
//     List<String> idStrings = new List<String>();
//     for (Id rId : recordIds) {
//         idStrings.add('\'' + String.escapeSingleQuotes(rId) + '\'');
//     }

//     String idList = String.join(idStrings, ',');

//     return 'SELECT ' + String.join(fields, ',') +
//            ' FROM ' + objectName +
//            ' WHERE Id IN (' + idList + ')';
// }



//     // Replace SELECT clause in fullQuery
//     private static String replaceSelect(String fullQuery, String fieldsCsv) {

//         List<String> fields = normalizeFields(fieldsCsv);

//         String selectClause = 'SELECT ' + String.join(fields, ',');

//         // Remove existing SELECT ... FROM
//         String afterSelect = fullQuery.substringAfter('from');

//         return selectClause + ' FROM ' + afterSelect;
//     }



//     /* =====================================================
//      *                  VALIDATION UTILS
//      * ===================================================== */

//     private static void validateInputs(String objectName, String fieldsCsv) {
//         if (String.isBlank(objectName)) {
//             throw new AuraHandledException('Object name is required.');
//         }
//         if (!Schema.getGlobalDescribe().containsKey(objectName)) {
//             throw new AuraHandledException('Invalid object: ' + objectName);
//         }
//         if (String.isBlank(fieldsCsv)) {
//             throw new AuraHandledException('Select at least one field.');
//         }
//     }

//     private static List<String> normalizeFields(String csv) {
//         List<String> fields = new List<String>();
//         for (String f : csv.split(',')) {
//             if (!String.isBlank(f.trim()))
//                 fields.add(f.trim());
//         }
//         return fields;
//     }



//     /* =====================================================
//      *                CSV BUILDER — NO ID
//      * ===================================================== */

//     private static String buildCsv(List<SObject> rows, List<String> fields) {
//         List<String> lines = new List<String>();

//         // Header
//         lines.add(String.join(fields, ','));

//         // Body
//         for (SObject row : rows) {
//             List<String> cols = new List<String>();
//             for (String f : fields) {

//                 Object value;

//                 if (f.contains('.')) {
//                     List<String> p = f.split('\\.');
//                     SObject parent = row.getSObject(p[0]);
//                     value = (parent != null ? parent.get(p[1]) : null);
//                 } else {
//                     value = row.get(f);
//                 }

//                 cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
//             }
//             lines.add(String.join(cols, ','));
//         }

//         return String.join(lines, '\n');
//     }


//     private static String escapeCsv(String v) {
//         if (v == null) return '';
//         String s = v.replaceAll('"', '""');
//         Boolean wrap = s.contains(',') || s.contains('\n') || s.contains('"');
//         return wrap ? '"' + s + '"' : s;
//     }
// }
// public with sharing class DataArchiveController {

//     // ===================== CONSTANT =====================
//     private static final Integer MAX_CSV_SIZE_BYTES = 6 * 1024 * 1024; // 6 MB = 6,291,456 bytes
 

//     /* =====================================================
//      *   ARCHIVE SELECTED RECORDS
//      * ===================================================== */
//     @AuraEnabled
//     public static Id archiveSelectedRecords(
//         String objectName,
//         List<Id> recordIds,
//         String fieldsCsv
//     ) {
//         if (recordIds == null || recordIds.isEmpty()) {
//             throw new AuraHandledException('Select at least one record to archive.');
//         }

//         String soql = buildSoqlForSelected(objectName, recordIds, fieldsCsv);
//         return archiveEngine(objectName, fieldsCsv, soql);
//     }

//     /* =====================================================
//      *   ARCHIVE ALL RECORDS
//      * ===================================================== */
//     @AuraEnabled
//     public static Id archiveAllRecords(
//         String objectName,
//         String fieldsCsv,
//         String fullQuery
//     ) {
//         if (String.isBlank(fullQuery)) {
//             throw new AuraHandledException('Full query is required.');
//         }

//         String finalQuery = replaceSelect(fullQuery, fieldsCsv);
//         return archiveEngine(objectName, fieldsCsv, finalQuery);
//     }

//     /* =====================================================
//      *   CORE ENGINE
//      * ===================================================== */
//     private static Id archiveEngine(
//         String objectName,
//         String fieldsCsv,
//         String soql
//     ) {
//         validateInputs(objectName, fieldsCsv);

//         List<String> fields = normalizeFields(fieldsCsv);
//         List<SObject> rows = Database.query(soql);

//         if (rows.isEmpty()) {
//             throw new AuraHandledException('No records found to archive.');
//         }

//         createArchiveFiles(objectName, rows, fields);
//         delete rows;

//         return null;
//     }

//     /* =====================================================
//      *   CSV SPLITTER (1 MB, NO RECORD SPLIT)
//      * ===================================================== */
//     private static void createArchiveFiles(
//         String objectName,
//         List<SObject> rows,
//         List<String> fields
//     ) {
//         String header = String.join(fields, ',') + '\n';
//         String currentCsv = header;
//         Integer partNumber = 1;

//         List<String> csvLines = buildCsvLines(rows, fields);

//         for (String line : csvLines) {

//             if (Blob.valueOf(header + line).size() > MAX_CSV_SIZE_BYTES) {
//                 throw new AuraHandledException(
//                     'A single record exceeds the 1 MB archive limit.'
//                 );
//             }

//             String tentativeCsv = currentCsv + line + '\n';

//             if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
//                 saveArchive(objectName, fields, currentCsv);
//                 partNumber++;
//                 currentCsv = header + line + '\n';
//             } else {
//                 currentCsv = tentativeCsv;
//             }
//         }

//         if (currentCsv != header) {
//             saveArchive(objectName, fields, currentCsv);
//         }
//     }

//     /* =====================================================
//      *   SAVE ARCHIVE + FILE
//      * ===================================================== */
//     private static void saveArchive(
//         String objectName,
//         List<String> fields,
//         String csvData
//     ) {
//         // DO NOT set Name (Auto Number)
//         Data_Archive__c archiveRecord = new Data_Archive__c(
//             Parent_Object__c = objectName,
//             Fields__c = String.join(fields, ',')
//         );
//         insert archiveRecord;

//         // Re-query to get auto-generated Name
//         archiveRecord = [
//             SELECT Id, Name
//             FROM Data_Archive__c
//             WHERE Id = :archiveRecord.Id
//             LIMIT 1
//         ];

//         ContentVersion cv = new ContentVersion(
//             Title = archiveRecord.Name,
//             PathOnClient = archiveRecord.Name + '.csv',
//             VersionData = Blob.valueOf(csvData)
//         );
//         insert cv;

//         ContentVersion insertedCv = [
//             SELECT ContentDocumentId
//             FROM ContentVersion
//             WHERE Id = :cv.Id
//             LIMIT 1
//         ];

//         insert new ContentDocumentLink(
//             ContentDocumentId = insertedCv.ContentDocumentId,
//             LinkedEntityId = archiveRecord.Id,
//             ShareType = 'V',
//             Visibility = 'AllUsers'
//         );
//     }

//     /* =====================================================
//      *   CSV LINE BUILDER
//      * ===================================================== */
//     private static List<String> buildCsvLines(
//         List<SObject> rows,
//         List<String> fields
//     ) {
//         List<String> lines = new List<String>();

//         for (SObject row : rows) {
//             List<String> cols = new List<String>();

//             for (String f : fields) {
//                 Object value;

//                 if (f.contains('.')) {
//                     List<String> p = f.split('\\.');
//                     SObject parent = row.getSObject(p[0]);
//                     value = (parent != null ? parent.get(p[1]) : null);
//                 } else {
//                     value = row.get(f);
//                 }

//                 cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
//             }

//             lines.add(String.join(cols, ','));
//         }
//         return lines;
//     }

//     /* =====================================================
//      *   SOQL HELPERS
//      * ===================================================== */
//     private static String buildSoqlForSelected(
//         String objectName,
//         List<Id> recordIds,
//         String fieldsCsv
//     ) {
//         List<String> fields = normalizeFields(fieldsCsv);
//         if (!fields.contains('Id')) fields.add('Id');

//         List<String> ids = new List<String>();
//         for (Id i : recordIds) {
//             ids.add('\'' + String.escapeSingleQuotes(i) + '\'');
//         }

//         return 'SELECT ' + String.join(fields, ',') +
//                ' FROM ' + objectName +
//                ' WHERE Id IN (' + String.join(ids, ',') + ')';
//     }

//     // FIXED: Apex-safe replace SELECT
//     private static String replaceSelect(String fullQuery, String fieldsCsv) {
//         List<String> fields = normalizeFields(fieldsCsv);

//         String lowerQuery = fullQuery.toLowerCase();
//         Integer fromIndex = lowerQuery.indexOf(' from ');

//         if (fromIndex == -1) {
//             throw new AuraHandledException('Invalid SOQL query.');
//         }

//         String fromClause = fullQuery.substring(fromIndex);
//         return 'SELECT ' + String.join(fields, ',') + fromClause;
//     }

//     /* =====================================================
//      *   VALIDATION & UTILITIES
//      * ===================================================== */
//     private static void validateInputs(String objectName, String fieldsCsv) {
//         if (String.isBlank(objectName)) {
//             throw new AuraHandledException('Object name is required.');
//         }
//         if (!Schema.getGlobalDescribe().containsKey(objectName)) {
//             throw new AuraHandledException('Invalid object name.');
//         }
//         if (String.isBlank(fieldsCsv)) {
//             throw new AuraHandledException('At least one field is required.');
//         }
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
public with sharing class DataArchiveController {

    // ===================== CONSTANT =====================
    private static final Integer MAX_CSV_SIZE_BYTES = 6 * 1024*10; // 6 MB

    /* =====================================================
     *   ARCHIVE SELECTED RECORDS
     * ===================================================== */
    @AuraEnabled
    public static Id archiveSelectedRecords(
        String objectName,
        List<Id> recordIds,
        String fieldsCsv
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('Select at least one record to archive.');
        }

        String soql = buildSoqlForSelected(objectName, recordIds, fieldsCsv);
        return archiveEngine(objectName, fieldsCsv, soql);
    }

    /* =====================================================
     *   ARCHIVE ALL RECORDS
     * ===================================================== */
    @AuraEnabled
    public static Id archiveAllRecords(
        String objectName,
        String fieldsCsv,
        String fullQuery
    ) {
        if (String.isBlank(fullQuery)) {
            throw new AuraHandledException('Full query is required.');
        }

        String finalQuery = replaceSelect(fullQuery, fieldsCsv);
        return archiveEngine(objectName, fieldsCsv, finalQuery);
    }

    /* =====================================================
     *   CORE ENGINE
     * ===================================================== */
    private static Id archiveEngine(
        String objectName,
        String fieldsCsv,
        String soql
    ) {
        validateInputs(objectName, fieldsCsv);

        List<String> fields = normalizeFields(fieldsCsv);
        List<SObject> rows = Database.query(soql);

        if (rows.isEmpty()) {
            throw new AuraHandledException('No records found to archive.');
        }

        // 🔹 Create ONE Data Archive record
        Data_Archive__c archiveRecord = new Data_Archive__c(
            Parent_Object__c = objectName,
            Fields__c = String.join(fields, ',')
        );
        insert archiveRecord;

        // Re-query to get auto-number Name
        archiveRecord = [
            SELECT Id, Name
            FROM Data_Archive__c
            WHERE Id = :archiveRecord.Id
            LIMIT 1
        ];

        createArchiveFiles(archiveRecord, rows, fields);

        delete rows;
        return archiveRecord.Id;
    }

    /* =====================================================
     *   CSV SPLITTER (6 MB, SAME ARCHIVE RECORD)
     * ===================================================== */
    private static void createArchiveFiles(
        Data_Archive__c archiveRecord,
        List<SObject> rows,
        List<String> fields
    ) {
        String header = String.join(fields, ',') + '\n';
        String currentCsv = header;

        Integer partNumber = 1;
        List<String> csvLines = buildCsvLines(rows, fields);

        for (String line : csvLines) {

            // Safety: one record cannot exceed max size
            if (Blob.valueOf(header + line).size() > MAX_CSV_SIZE_BYTES) {
                throw new AuraHandledException(
                    'A single record exceeds the 6 MB CSV size limit.'
                );
            }

            String tentativeCsv = currentCsv + line + '\n';

            // If limit exceeded → save previous CSV (without this record)
            if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
                saveCsvFile(archiveRecord, currentCsv, partNumber);
                partNumber++;
                currentCsv = header + line + '\n';
            } else {
                currentCsv = tentativeCsv;
            }
        }

        // Save last file
        if (currentCsv != header) {
            saveCsvFile(archiveRecord, currentCsv, partNumber);
        }
    }

    /* =====================================================
     *   SAVE CSV FILE (SAME NAME AS ARCHIVE RECORD)
     * ===================================================== */
    private static void saveCsvFile(
        Data_Archive__c archiveRecord,
        String csvData,
        Integer partNumber
    ) {
        ContentVersion cv = new ContentVersion(
            Title = archiveRecord.Name,                 // SAME NAME
            PathOnClient = archiveRecord.Name + '.csv', // SAME FILE NAME
            Description = 'Part ' + partNumber,         // Differentiator
            VersionData = Blob.valueOf(csvData)
        );
        insert cv;

        ContentVersion insertedCv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId = archiveRecord.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    /* =====================================================
     *   CSV LINE BUILDER
     * ===================================================== */
    private static List<String> buildCsvLines(
        List<SObject> rows,
        List<String> fields
    ) {
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

    /* =====================================================
     *   SOQL HELPERS
     * ===================================================== */
    private static String buildSoqlForSelected(
        String objectName,
        List<Id> recordIds,
        String fieldsCsv
    ) {
        List<String> fields = normalizeFields(fieldsCsv);
        if (!fields.contains('Id')) fields.add('Id');

        List<String> ids = new List<String>();
        for (Id i : recordIds) {
            ids.add('\'' + String.escapeSingleQuotes(i) + '\'');
        }

        return 'SELECT ' + String.join(fields, ',') +
               ' FROM ' + objectName +
               ' WHERE Id IN (' + String.join(ids, ',') + ')';
    }

    private static String replaceSelect(String fullQuery, String fieldsCsv) {
        List<String> fields = normalizeFields(fieldsCsv);

        String lowerQuery = fullQuery.toLowerCase();
        Integer fromIndex = lowerQuery.indexOf(' from ');

        if (fromIndex == -1) {
            throw new AuraHandledException('Invalid SOQL query.');
        }

        String fromClause = fullQuery.substring(fromIndex);
        return 'SELECT ' + String.join(fields, ',') + fromClause;
    }

    /* =====================================================
     *   VALIDATION & UTILITIES
     * ===================================================== */
    private static void validateInputs(String objectName, String fieldsCsv) {
        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required.');
        }
        if (!Schema.getGlobalDescribe().containsKey(objectName)) {
            throw new AuraHandledException('Invalid object name.');
        }
        if (String.isBlank(fieldsCsv)) {
            throw new AuraHandledException('At least one field is required.');
        }
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