/**
 * @description Controller that provides CRUD and utility operations for Data_Archive__c records.
 *              Supports retrieval, status updates, unarchiving, archiving, and deletion of archives.
 */
public with sharing class DataArchiveController {

    /**
     * @description Retrieves all Data_Archive__c records ordered by creation date descending.
     * @return A list of Data_Archive__c records with key fields.
     */
    @AuraEnabled(cacheable=true)
    public static List<Data_Archive__c> getArchives() {

        return [
            SELECT Id, Name, Parent_Object__c, Fields__c, Status__c, CreatedDate
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * @description Retrieves a single Data_Archive__c record by its ID.
     * @param archiveIdStr The ID of the archive record to retrieve.
     * @return The Data_Archive__c record, or null if not found.
     */
    @AuraEnabled
    public static Data_Archive__c getArchiveById(String archiveIdStr) {

        List<Data_Archive__c> archivesList = [
            SELECT Id, Name, Parent_Object__c, Fields__c, Status__c, CreatedDate
            FROM Data_Archive__c
            WHERE Id = :archiveIdStr
            LIMIT 1
        ];

        return archivesList.isEmpty() ? null : archivesList[0];
    }

    /**
     * @description Archives selected records by ID. Creates a Data_Archive__c record
     *              and starts a DataArchiveBatch job.
     * @param objectName The API name of the SObject to archive.
     * @param recordIds List of record IDs to archive.
     * @param fieldsCsv Comma-separated field API names.
     * @param archiveName Optional name for the archive record.
     * @param selectedChildObjects Optional list of child object API names to include.
     * @return The ID of the batch job.
     */
    @AuraEnabled
    public static Id archiveSelectedRecords(String objectName, List<Id> recordIds, String fieldsCsv,
                                             String archiveName, List<String> selectedChildObjects) {

        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required.');
        }
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('Record IDs are required.');
        }
        if (String.isBlank(fieldsCsv)) {
            throw new AuraHandledException('Fields are required.');
        }

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) {
            throw new AuraHandledException('Invalid object: ' + objectName);
        }

        // Ensure Id field is included
        List<String> fieldsList = new List<String>();
        Boolean hasIdFlag = false;

        for (String fieldStr : fieldsCsv.split(',')) {
            String trimmedStr = fieldStr.trim();
            fieldsList.add(trimmedStr);
            if (trimmedStr.equalsIgnoreCase('Id')) hasIdFlag = true;
        }

        if (!hasIdFlag) {
            fieldsList.add(0, 'Id');
        }

        String fieldsJoinedStr = String.join(fieldsList, ',');

        String soqlStr = 'SELECT ' + fieldsJoinedStr +
            ' FROM ' + objectName +
            ' WHERE Id IN (\'' + String.join(recordIds, '\',\'') + '\')';

        // Start batch
        Id batchJobId = Database.executeBatch(
            new DataArchiveBatch(objectName, fieldsJoinedStr, soqlStr, archiveName, selectedChildObjects),
            200
        );

        return batchJobId;
    }

    /**
     * @description Archives all records matching a SOQL query. Creates a Data_Archive__c
     *              record and starts a DataArchiveBatch job.
     * @param objectName The API name of the SObject to archive.
     * @param fieldsCsv Comma-separated field API names.
     * @param fullQuery The full SOQL query to select records.
     * @param archiveName Optional name for the archive record.
     * @param selectedChildObjects Optional list of child object API names to include.
     * @return The ID of the batch job.
     */
    @AuraEnabled
    public static Id archiveAllRecords(String objectName, String fieldsCsv, String fullQuery,
                                        String archiveName, List<String> selectedChildObjects) {

        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required.');
        }
        if (String.isBlank(fieldsCsv)) {
            throw new AuraHandledException('Fields are required.');
        }
        if (String.isBlank(fullQuery)) {
            throw new AuraHandledException('SOQL query is required.');
        }

        // Replace SELECT clause with full field list
        String adjustedQueryStr = replaceSelect(fullQuery, fieldsCsv);

        // Start batch
        Id batchJobId = Database.executeBatch(
            new DataArchiveBatch(objectName, fieldsCsv, adjustedQueryStr, archiveName, selectedChildObjects),
            200
        );

        return batchJobId;
    }

    /**
     * @description Replaces the SELECT clause in a SOQL query with specified fields.
     * @param originalQueryStr The original SOQL query.
     * @param fieldsCsvStr Comma-separated field API names.
     * @return The modified SOQL query with the new SELECT clause.
     */
    private static String replaceSelect(String originalQueryStr, String fieldsCsvStr) {

        List<String> fieldsList = new List<String>();
        Boolean hasIdFlag = false;

        for (String fieldStr : fieldsCsvStr.split(',')) {
            String trimmedStr = fieldStr.trim();
            fieldsList.add(trimmedStr);
            if (trimmedStr.equalsIgnoreCase('Id')) hasIdFlag = true;
        }

        if (!hasIdFlag) {
            fieldsList.add(0, 'Id');
        }

        String fieldsJoinedStr = String.join(fieldsList, ', ');

        Integer fromIndexInt = originalQueryStr.toLowerCase().indexOf(' from ');

        if (fromIndexInt < 0) {
            throw new AuraHandledException('Invalid SOQL query - missing FROM clause.');
        }

        return 'SELECT ' + fieldsJoinedStr + originalQueryStr.substring(fromIndexInt);
    }

    /**
     * @description Gets the status of an async batch job.
     * @param batchJobId The ID of the batch job to check.
     * @return A map with status, processed, total, and errors keys.
     */
    @AuraEnabled
    public static Map<String, Object> getBatchStatus(Id batchJobId) {

        Map<String, Object> resultMap = new Map<String, Object>();

        List<AsyncApexJob> jobsList = [
            SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchJobId
            LIMIT 1
        ];

        if (!jobsList.isEmpty()) {
            AsyncApexJob jobRecord = jobsList[0];
            resultMap.put('status', jobRecord.Status);
            resultMap.put('processed', jobRecord.JobItemsProcessed);
            resultMap.put('total', jobRecord.TotalJobItems);
            resultMap.put('errors', jobRecord.NumberOfErrors);
        } else {
            resultMap.put('status', 'Not Found');
            resultMap.put('processed', 0);
            resultMap.put('total', 0);
            resultMap.put('errors', 0);
        }

        return resultMap;
    }

    /**
     * @description Gets the archive record ID associated with a batch job.
     * @param batchJobId The batch job ID to look up the archive for.
     * @return The archive record ID, or null if not found.
     */
    @AuraEnabled
    public static Id getArchiveRecordId(Id batchJobId) {

        if (batchJobId == null) return null;

        // Get the most recently created archive record
        List<Data_Archive__c> archivesList = [
            SELECT Id
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return archivesList.isEmpty() ? null : archivesList[0].Id;
    }

    /**
     * @description Gets the current status of a Data_Archive__c record.
     * @param archiveRecordId The ID of the archive record.
     * @return The status string of the archive record.
     */
    @AuraEnabled
    public static String getArchiveStatus(Id archiveRecordId) {

        if (archiveRecordId == null) return null;

        List<Data_Archive__c> archivesList = [
            SELECT Status__c
            FROM Data_Archive__c
            WHERE Id = :archiveRecordId
            LIMIT 1
        ];

        return archivesList.isEmpty() ? null : archivesList[0].Status__c;
    }

    /**
     * @description Updates the status of a Data_Archive__c record.
     * @param archiveIdStr The ID of the archive record.
     * @param statusStr The new status value to set.
     */
    @AuraEnabled
    public static void updateArchiveStatus(String archiveIdStr, String statusStr) {

        Data_Archive__c archiveRecord = new Data_Archive__c(
            Id = archiveIdStr,
            Status__c = statusStr
        );
        update archiveRecord;
    }

    /**
     * @description Initiates the unarchive process for the given archive IDs by
     *              enqueuing a DataArchiveUnarchiveQueueable job.
     * @param archiveIdsList List of Data_Archive__c record IDs to unarchive.
     */
    @AuraEnabled
    public static void unarchiveRecords(List<Id> archiveIdsList) {

        if (archiveIdsList == null || archiveIdsList.isEmpty()) return;

        System.enqueueJob(new DataArchiveUnarchiveQueueable(archiveIdsList));
    }

    /**
     * @description Deletes the specified Data_Archive__c records and their linked
     *              ContentDocuments (CSV files).
     * @param archiveIdsList List of Data_Archive__c record IDs to delete.
     */
    @AuraEnabled
    public static void deleteArchives(List<Id> archiveIdsList) {

        if (archiveIdsList == null || archiveIdsList.isEmpty()) return;

        List<ContentDocumentLink> linksList = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :archiveIdsList
        ];

        Set<Id> docIdSet = new Set<Id>();

        for (ContentDocumentLink currentLink : linksList) {
            docIdSet.add(currentLink.ContentDocumentId);
        }

        if (!docIdSet.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docIdSet];
        }

        delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archiveIdsList];
    }

    /**
     * @description Retrieves the S3 file keys linked to a given archive record.
     * @param archiveIdStr The ID of the Data_Archive__c record.
     * @return A list of S3 file key strings (archiveId/Title.ext).
     */
    @AuraEnabled
    public static List<String> getS3FileKeys(String archiveIdStr) {

        List<String> fileKeysList = new List<String>();

        List<ContentDocumentLink> linksList = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :archiveIdStr
        ];

        Set<Id> docIdSet = new Set<Id>();

        for (ContentDocumentLink currentLink : linksList) {
            docIdSet.add(currentLink.ContentDocumentId);
        }

        if (docIdSet.isEmpty()) return fileKeysList;

        List<ContentVersion> versionsList = [
            SELECT Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIdSet
            AND IsLatest = true
        ];

        for (ContentVersion currentVersion : versionsList) {

            String keyStr = archiveIdStr + '/' + currentVersion.Title;

            if (String.isNotBlank(currentVersion.FileExtension)) {
                keyStr += '.' + currentVersion.FileExtension;
            }

            fileKeysList.add(keyStr);
        }

        return fileKeysList;
    }
}