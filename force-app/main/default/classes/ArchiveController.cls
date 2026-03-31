/**
 * @description Controller for the ArchiveController LWC component.
 *              Handles building CSV content from queried records and linking
 *              the resulting CSV files to Data_Archive__c records.
 */
public with sharing class ArchiveController {

    /**
     * @description Archives the specified records by building a CSV, creating a
     *              Data_Archive__c record, and deleting the originals.
     * @param objectNameStr The API name of the SObject to archive.
     * @param recordIdsList List of record IDs to archive.
     * @param fieldsCsvStr Comma-separated field API names for CSV columns.
     * @return 'OK' on success.
     */
    @AuraEnabled
    public static String archiveRecords(String objectNameStr, List<Id> recordIdsList, String fieldsCsvStr) {

        if (String.isBlank(objectNameStr)) {
            throw new AuraHandledException('Object name is required.');
        }
        if (recordIdsList == null || recordIdsList.isEmpty()) {
            throw new AuraHandledException('Record IDs are required.');
        }
        if (String.isBlank(fieldsCsvStr)) {
            throw new AuraHandledException('Fields are required.');
        }

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectNameStr);
        if (objType == null) {
            throw new AuraHandledException('Invalid object: ' + objectNameStr);
        }

        // Build SOQL
        List<String> fieldsList = fieldsCsvStr.split(',');
        List<String> trimmedFieldsList = new List<String>();
        Boolean hasIdFlag = false;

        for (String fieldStr : fieldsList) {
            String trimmedStr = fieldStr.trim();
            trimmedFieldsList.add(trimmedStr);
            if (trimmedStr.equalsIgnoreCase('Id')) hasIdFlag = true;
        }

        if (!hasIdFlag) {
            trimmedFieldsList.add(0, 'Id');
        }

        String soqlStr = 'SELECT ' + String.join(trimmedFieldsList, ', ') +
            ' FROM ' + objectNameStr +
            ' WHERE Id IN :recordIdsList';

        List<SObject> recordsList;
        try {
            recordsList = Database.query(soqlStr);
        } catch (Exception ex) {
            throw new AuraHandledException('Query failed: ' + ex.getMessage());
        }

        if (recordsList.isEmpty()) {
            throw new AuraHandledException('No records found for the given IDs.');
        }

        // Create archive record
        Data_Archive__c archiveRecord = new Data_Archive__c();
        archiveRecord.Parent_Object__c = objectNameStr;
        archiveRecord.Fields__c = fieldsCsvStr;
        archiveRecord.Status__c = 'Archiving';
        insert archiveRecord;

        archiveRecord = [SELECT Id, Name FROM Data_Archive__c WHERE Id = :archiveRecord.Id LIMIT 1];

        // Build CSV
        String csvContentStr = String.join(trimmedFieldsList, ',') + '\n';

        for (SObject currentRecord : recordsList) {
            List<String> valuesList = new List<String>();

            for (String fieldNameStr : trimmedFieldsList) {
                Object fieldValue = currentRecord.get(fieldNameStr.trim());
                String cellValueStr = (fieldValue != null) ? String.valueOf(fieldValue) : '';

                if (cellValueStr.contains(',') || cellValueStr.contains('"') || cellValueStr.contains('\n')) {
                    cellValueStr = '"' + cellValueStr.replace('"', '""') + '"';
                }

                valuesList.add(cellValueStr);
            }

            csvContentStr += String.join(valuesList, ',') + '\n';
        }

        // Create ContentVersion
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.Title = objectNameStr;
        contentVersion.PathOnClient = archiveRecord.Name + '-' + objectNameStr + '.csv';
        contentVersion.VersionData = Blob.valueOf(csvContentStr);
        contentVersion.Description = objectNameStr + ' - ' + archiveRecord.Name;
        insert contentVersion;

        ContentVersion insertedVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
        ];

        // Link to archive record
        ContentDocumentLink docLink = new ContentDocumentLink();
        docLink.ContentDocumentId = insertedVersion.ContentDocumentId;
        docLink.LinkedEntityId = archiveRecord.Id;
        docLink.ShareType = 'V';
        docLink.Visibility = 'AllUsers';
        insert docLink;

        // Delete original records
        try {
            delete recordsList;
        } catch (Exception ex) {
            System.debug('Delete failed: ' + ex.getMessage());
        }

        archiveRecord.Status__c = 'Completed';
        update archiveRecord;

        return 'OK';
    }

    /**
     * @description Builds CSV content from the given records and attaches it as a
     *              ContentVersion linked to the specified Data_Archive__c record.
     * @param recordsList The list of SObject records to convert to CSV.
     * @param fieldsCsvStr Comma-separated field API names defining CSV columns.
     * @param archiveId The ID of the Data_Archive__c record to link the CSV to.
     * @param objectNameStr The API name of the SObject being archived.
     * @param partNumberInt The part number for multi-part CSV files.
     */
    @AuraEnabled
    public static void buildCsvAndLink(
        List<SObject> recordsList,
        String fieldsCsvStr,
        Id archiveId,
        String objectNameStr,
        Integer partNumberInt
    ) {

        if (recordsList == null || recordsList.isEmpty()) return;

        List<String> fieldsList = fieldsCsvStr.split(',');

        String csvContentStr = String.join(fieldsList, ',') + '\n';

        for (SObject currentRecord : recordsList) {

            List<String> valuesList = new List<String>();

            for (String fieldNameStr : fieldsList) {

                String trimmedFieldStr = fieldNameStr.trim();
                Object fieldValue = currentRecord.get(trimmedFieldStr);
                String cellValueStr = (fieldValue != null) ? String.valueOf(fieldValue) : '';

                if (cellValueStr.contains(',') || cellValueStr.contains('"') || cellValueStr.contains('\n')) {
                    cellValueStr = '"' + cellValueStr.replace('"', '""') + '"';
                }

                valuesList.add(cellValueStr);
            }

            csvContentStr += String.join(valuesList, ',') + '\n';
        }

        Data_Archive__c archiveRecord = [SELECT Name FROM Data_Archive__c WHERE Id = :archiveId LIMIT 1];
        String titleStr = objectNameStr;
        String descriptionStr = objectNameStr + ' - ' + archiveRecord.Name;

        if (partNumberInt != null && partNumberInt > 1) {
            titleStr += ' Part ' + partNumberInt;
            descriptionStr += ' Part ' + partNumberInt;
        }

        ContentVersion contentVersion = new ContentVersion();
        contentVersion.Title = titleStr;
        contentVersion.PathOnClient = archiveRecord.Name + '-' + objectNameStr + '.csv';
        contentVersion.VersionData = Blob.valueOf(csvContentStr);
        contentVersion.Description = descriptionStr;
        insert contentVersion;

        ContentVersion insertedVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
        ];

        ContentDocumentLink docLink = new ContentDocumentLink();
        docLink.ContentDocumentId = insertedVersion.ContentDocumentId;
        docLink.LinkedEntityId = archiveId;
        docLink.ShareType = 'V';
        docLink.Visibility = 'AllUsers';
        insert docLink;
    }

    /**
     * @description Retrieves the maximum CSV length limit from the custom label.
     * @return The maximum CSV length as an Integer.
     */
    @AuraEnabled(cacheable=true)
    public static Integer getMaxCsvLength() {

        return Integer.valueOf(Label.MAX_CSV_LENGTH);
    }

    /**
     * @description Creates a new Data_Archive__c record with the specified details.
     * @param objectNameStr The API name of the archived SObject.
     * @param fieldsCsvStr Comma-separated field API names.
     * @param recordCountInt The number of records being archived.
     * @param childObjectsStr JSON string of selected child objects.
     * @return The ID of the newly created Data_Archive__c record.
     */
    @AuraEnabled
    public static Id createArchiveRecord(
        String objectNameStr,
        String fieldsCsvStr,
        Integer recordCountInt,
        String childObjectsStr
    ) {

        Data_Archive__c archiveRecord = new Data_Archive__c();
        archiveRecord.Parent_Object__c = objectNameStr;
        archiveRecord.Fields__c = fieldsCsvStr;
        archiveRecord.Status__c = 'Archiving';
        insert archiveRecord;

        return archiveRecord.Id;
    }

    /**
     * @description Updates an existing Data_Archive__c record with the final
     *              status and encryption key after archival completes.
     * @param archiveId The ID of the Data_Archive__c record to update.
     * @param statusStr The new status value.
     * @param encryptionKeyStr The base64-encoded AES encryption key (optional).
     */
    @AuraEnabled
    public static void updateArchiveRecord(Id archiveId, String statusStr, String encryptionKeyStr) {

        Data_Archive__c archiveRecord = new Data_Archive__c(Id = archiveId);
        archiveRecord.Status__c = statusStr;

        if (String.isNotBlank(encryptionKeyStr)) {
            archiveRecord.Encryption_Key__c = encryptionKeyStr;
        }

        update archiveRecord;
    }
}