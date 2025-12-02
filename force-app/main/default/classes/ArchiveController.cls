public with sharing class ArchiveController {

    @AuraEnabled
    public static String archiveRecords(String objectName, List<Id> recordIds, String fieldsCsv) {

        // ------------------ VALIDATIONS ------------------
        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required.');
        }
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('No record IDs provided.');
        }
        if (String.isBlank(fieldsCsv)) {
            throw new AuraHandledException('Select at least one field to archive.');
        }

        if (!Schema.getGlobalDescribe().containsKey(objectName)) {
            throw new AuraHandledException('Invalid object: ' + objectName);
        }

        // ------------------ NORMALIZE FIELDS ------------------
        List<String> fields = new List<String>();
        for (String f : fieldsCsv.split(',')) {
            if (!String.isBlank(f.trim())) fields.add(f.trim());
        }

        // Add Id ONLY for query, but NOT for CSV
        List<String> queryFields = new List<String>(fields);
        if (!queryFields.contains('Id')) {
            queryFields.add('Id');
        }

        // ------------------ BUILD SOQL ------------------
        String soql =
            'SELECT ' + String.join(queryFields, ',') +
            ' FROM ' + objectName +
            ' WHERE Id IN :recordIds';

        List<SObject> rows;
        try {
            rows = Database.query(soql);
        } catch (Exception e) {
            throw new AuraHandledException('SOQL FAILED: ' + e.getMessage());
        }

        // ------------------ CREATE ARCHIVE RECORD ------------------
        Data_Archive__c archiveRecord = new Data_Archive__c(
            Parent_Object__c = objectName,
            Fields__c = String.join(fields, ',')    // store ONLY selected fields
        );
        insert archiveRecord;
        

// Fetch auto-generated Name value
archiveRecord = [
    SELECT Id,Name
    FROM Data_Archive__c
    WHERE Id = :archiveRecord.Id
    LIMIT 1
];


        // ------------------ CSV FILE CREATION ------------------
        String csvData = buildCsv(rows, fields); // <-- PASS FIELDS WITHOUT ID

        ContentVersion cv = new ContentVersion(
            Title = archiveRecord.Name,
            PathOnClient = archiveRecord.Name + '.csv',
            VersionData = Blob.valueOf(csvData)
        );

        try {
            insert cv;
        } catch (Exception e) {
            deleteSafely(archiveRecord);
            throw new AuraHandledException('File creation failed: ' + e.getMessage());
        }

        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id LIMIT 1
        ];

        if (String.isBlank(insertedCv.ContentDocumentId)) {
            deleteSafely(archiveRecord);
            throw new AuraHandledException('ContentDocumentId missing after file insert.');
        }

        // ------------------ LINK FILE ------------------
        try {
            insert new ContentDocumentLink(
                ContentDocumentId = insertedCv.ContentDocumentId,
                LinkedEntityId = archiveRecord.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        } catch (Exception e) {
            deleteContentDocument(insertedCv.ContentDocumentId);
            deleteSafely(archiveRecord);
            throw new AuraHandledException('Linking archive file failed: ' + e.getMessage());
        }

        // ------------------ DELETE ORIGINAL RECORDS ------------------
        try {
            delete rows;
        } catch (DmlException e) {
            throw new AuraHandledException('Delete failed: ' + e.getMessage());
        }

        return 'OK';
    }

    // =======================================================
    //  CSV BUILDER — WITHOUT ID FIELD
    // =======================================================
    private static String buildCsv(List<SObject> rows, List<String> fields) {
        List<String> lines = new List<String>();

        // Header
        lines.add(String.join(fields, ','));

        // Rows
        for (SObject record : rows) {
            List<String> cols = new List<String>();

            for (String field : fields) {
                Object value;

                if (field.contains('.')) {
                    List<String> path = field.split('\\.');
                    SObject parent = record.getSObject(path[0]);
                    value = (parent != null) ? parent.get(path[1]) : null;
                } else {
                    value = record.get(field);
                }

                cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
            }
            lines.add(String.join(cols, ','));
        }
        return String.join(lines, '\n');
    }

    private static String escapeCsv(String value) {
        if (value == null) return '';
        String sanitized = value.replaceAll('"', '""');
        Boolean wrap = sanitized.contains(',') || sanitized.contains('\n') || sanitized.contains('"');
        return wrap ? '"' + sanitized + '"' : sanitized;
    }

    // -------------------------------------------------------
    // SAFE CLEANUP
    // -------------------------------------------------------
    private static void deleteSafely(SObject record) {
        try { delete record; } catch (Exception ex) {}
    }

    private static void deleteContentDocument(Id contentDocumentId) {
        try {
            delete [SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId];
        } catch (Exception ex) {}
    }
}