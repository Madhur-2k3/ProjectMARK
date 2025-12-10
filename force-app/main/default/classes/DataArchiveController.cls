public with sharing class DataArchiveController {

    /* =====================================================
     *   PUBLIC METHOD #1 — ARCHIVE SELECTED RECORDS
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

        // Build SOQL
        String soql = buildSoqlForSelected(objectName, recordIds, fieldsCsv);

        // Delegate to reusable archive engine
        return archiveEngine(objectName, fieldsCsv, soql);
    }



    /* =====================================================
     *   PUBLIC METHOD #2 — ARCHIVE ALL RECORDS (FULL QUERY)
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

        // Replace SELECT fields in fullQuery
        

        return archiveEngine(objectName, fieldsCsv, fullQuery);
    }



    /* =====================================================
     *   CORE ARCHIVE ENGINE (USED BY BOTH METHODS)
     * ===================================================== */
    private static Id archiveEngine(
        String objectName,
        String fieldsCsv,
        String soql
    ) {
        validateInputs(objectName, fieldsCsv);

        // Normalize Fields
        List<String> fields = normalizeFields(fieldsCsv);

        // Query records
        List<SObject> rows = Database.query(soql);

        if (rows.isEmpty()) {
            throw new AuraHandledException('No records found to archive.');
        }

        // Create Archive Header
        Data_Archive__c archiveRecord = new Data_Archive__c(
            Parent_Object__c = objectName,
            Fields__c = String.join(fields, ',')
        );
        insert archiveRecord;

        archiveRecord = [
            SELECT Id, Name
            FROM Data_Archive__c
            WHERE Id = :archiveRecord.Id
            LIMIT 1
        ];

        // Build CSV
        String csvData = buildCsv(rows, fields);

        // Save CSV File
        ContentVersion cv = new ContentVersion(
            Title = archiveRecord.Name,
            PathOnClient = archiveRecord.Name + '.csv',
            VersionData = Blob.valueOf(csvData)
        );

        insert cv;

        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id LIMIT 1
        ];

        // Link to Archive record
        insert new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId = archiveRecord.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        // Delete original records
        delete rows;

        return archiveRecord.Id;
    }



    /* =====================================================
     *               SOQL BUILDERS
     * ===================================================== */

    private static String buildSoqlForSelected(
    String objectName,
    List<Id> recordIds,
    String fieldsCsv
) {
    List<String> fields = normalizeFields(fieldsCsv);

    // Ensure Id is present
    if (!fields.contains('Id')) fields.add('Id');

    // Convert Ids into quoted string list
    List<String> idStrings = new List<String>();
    for (Id rId : recordIds) {
        idStrings.add('\'' + String.escapeSingleQuotes(rId) + '\'');
    }

    String idList = String.join(idStrings, ',');

    return 'SELECT ' + String.join(fields, ',') +
           ' FROM ' + objectName +
           ' WHERE Id IN (' + idList + ')';
}



    // Replace SELECT clause in fullQuery
    private static String replaceSelect(String fullQuery, String fieldsCsv) {

        List<String> fields = normalizeFields(fieldsCsv);

        String selectClause = 'SELECT ' + String.join(fields, ',');

        // Remove existing SELECT ... FROM
        String afterSelect = fullQuery.substringAfter('from');

        return selectClause + ' FROM ' + afterSelect;
    }



    /* =====================================================
     *                  VALIDATION UTILS
     * ===================================================== */

    private static void validateInputs(String objectName, String fieldsCsv) {
        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required.');
        }
        if (!Schema.getGlobalDescribe().containsKey(objectName)) {
            throw new AuraHandledException('Invalid object: ' + objectName);
        }
        if (String.isBlank(fieldsCsv)) {
            throw new AuraHandledException('Select at least one field.');
        }
    }

    private static List<String> normalizeFields(String csv) {
        List<String> fields = new List<String>();
        for (String f : csv.split(',')) {
            if (!String.isBlank(f.trim()))
                fields.add(f.trim());
        }
        return fields;
    }



    /* =====================================================
     *                CSV BUILDER — NO ID
     * ===================================================== */

    private static String buildCsv(List<SObject> rows, List<String> fields) {
        List<String> lines = new List<String>();

        // Header
        lines.add(String.join(fields, ','));

        // Body
        for (SObject row : rows) {
            List<String> cols = new List<String>();
            for (String f : fields) {

                Object value;

                if (f.contains('.')) {
                    List<String> p = f.split('\\.');
                    SObject parent = row.getSObject(p[0]);
                    value = (parent != null ? parent.get(p[1]) : null);
                } else {
                    value = row.get(f);
                }

                cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
            }
            lines.add(String.join(cols, ','));
        }

        return String.join(lines, '\n');
    }


    private static String escapeCsv(String v) {
        if (v == null) return '';
        String s = v.replaceAll('"', '""');
        Boolean wrap = s.contains(',') || s.contains('\n') || s.contains('"');
        return wrap ? '"' + s + '"' : s;
    }
}