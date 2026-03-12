public with sharing class DataArchiveController {

    /* =====================================================
     *   ARCHIVE SELECTED RECORDS (ASYNC)
     * ===================================================== */
    @AuraEnabled
    public static Id archiveSelectedRecords(
        String objectName,
        List<Id> recordIds,
        String fieldsCsv,
        String archiveName,
        List<String> selectedChildObjects
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('Select at least one record to archive.');
        }

        String soql = buildSoqlForSelected(objectName, recordIds, fieldsCsv);
        return executeBatchArchive(objectName, fieldsCsv, soql, archiveName, selectedChildObjects);
    }

    /* =====================================================
     *   ARCHIVE ALL RECORDS (ASYNC)
     * ===================================================== */
    @AuraEnabled
    public static Id archiveAllRecords(
        String objectName,
        String fieldsCsv,
        String fullQuery,
        String archiveName,
        List<String> selectedChildObjects
    ) {
        if (String.isBlank(fullQuery)) {
            throw new AuraHandledException('Full query is required.');
        }

        String finalQuery = replaceSelect(fullQuery, fieldsCsv);
        return executeBatchArchive(objectName, fieldsCsv, finalQuery, archiveName, selectedChildObjects);
    }

    /* =====================================================
     *   EXECUTE BATCH JOB
     * ===================================================== */
    private static Id executeBatchArchive(
        String objectName,
        String fieldsCsv,
        String soql,
        String archiveName,
        List<String> selectedChildObjects
    ) {
        validateInputs(objectName, fieldsCsv);

        DataArchiveBatch batch = new DataArchiveBatch(objectName, fieldsCsv, soql, archiveName, selectedChildObjects);
        Id batchJobId = Database.executeBatch(batch, 2000);

        return batchJobId;
    }

    /* =====================================================
     *   CHECK BATCH STATUS
     * ===================================================== */
    @AuraEnabled
    public static Map<String, Object> getBatchStatus(Id batchJobId) {
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors,
                   JobItemsProcessed, TotalJobItems,
                   CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE Id = :batchJobId
            LIMIT 1
        ];

        return new Map<String, Object>{
            'status' => job.Status,
            'processed' => job.JobItemsProcessed,
            'total' => job.TotalJobItems,
            'errors' => job.NumberOfErrors,
            'createdDate' => job.CreatedDate,
            'completedDate' => job.CompletedDate
        };
    }

    /* =====================================================
     *   GET ARCHIVE RECORD ID FROM BATCH JOB
     * ===================================================== */
    @AuraEnabled
    public static Id getArchiveRecordId(Id batchJobId) {
        List<Data_Archive__c> archives = [
            SELECT Id, Status__c
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return archives.isEmpty() ? null : archives[0].Id;
    }

    /* =====================================================
     *   CHECK ARCHIVE RECORD STATUS
     * ===================================================== */
    @AuraEnabled
    public static String getArchiveStatus(Id archiveRecordId) {
        List<Data_Archive__c> archives = [
            SELECT Status__c
            FROM Data_Archive__c
            WHERE Id = :archiveRecordId
            LIMIT 1
        ];
        return archives.isEmpty() ? null : archives[0].Status__c;
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

        Integer fromIndex = fullQuery.toLowerCase().indexOf(' from ');
        if (fromIndex == -1) {
            throw new AuraHandledException('Invalid SOQL query.');
        }

        return 'SELECT ' + String.join(fields, ',') +
               fullQuery.substring(fromIndex);
    }

    /* =====================================================
     *   VALIDATION & UTILITIES
     * ===================================================== */
    private static void validateInputs(String objectName, String fieldsCsv) {
        if (String.isBlank(objectName))
            throw new AuraHandledException('Object name is required.');
        if (!Schema.getGlobalDescribe().containsKey(objectName))
            throw new AuraHandledException('Invalid object name.');
        if (String.isBlank(fieldsCsv))
            throw new AuraHandledException('At least one field is required.');
    }

    private static List<String> normalizeFields(String csv) {
        List<String> fields = new List<String>();
        for (String f : csv.split(',')) {
            if (!String.isBlank(f)) fields.add(f.trim());
        }
        return fields;
    }
}