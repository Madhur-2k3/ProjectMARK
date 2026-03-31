/**
 * @description Queueable class that handles unarchiving records from CSV files
 *              stored as ContentVersion attachments. Parses CSVs, inserts records
 *              back into Salesforce, and removes the archive and its documents.
 */
public with sharing class DataArchiveUnarchiveQueueable implements Queueable {

    private List<Id> archiveIdsList;

    /**
     * @description Constructs a new DataArchiveUnarchiveQueueable.
     * @param idsList List of Data_Archive__c record IDs to unarchive.
     */
    public DataArchiveUnarchiveQueueable(List<Id> idsList) {

        this.archiveIdsList = idsList;
    }

    /**
     * @description Executes the unarchive process: parses CSVs, inserts records,
     *              and cleans up archive records and documents.
     * @param queueableContext The QueueableContext provided by the platform.
     */
    public void execute(QueueableContext queueableContext) {

        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();

        List<Data_Archive__c> archivesList = [
            SELECT Id, Name, Parent_Object__c
            FROM Data_Archive__c
            WHERE Id IN :archiveIdsList
        ];

        Set<Id> archiveDeleteSet = new Set<Id>();
        Set<Id> docDeleteSet     = new Set<Id>();

        for (Data_Archive__c currentArchive : archivesList) {

            String parentObjectNameStr = currentArchive.Parent_Object__c;

            // ===== 1. Find ALL linked ContentDocuments =====
            List<ContentDocumentLink> linksList = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :currentArchive.Id
            ];

            if (linksList.isEmpty()) {
                archiveDeleteSet.add(currentArchive.Id);
                continue;
            }

            Set<Id> linkedDocIdSet = new Set<Id>();

            for (ContentDocumentLink currentLink : linksList) {
                linkedDocIdSet.add(currentLink.ContentDocumentId);
            }

            // ===== 2. Get all CSV ContentVersions =====
            List<ContentVersion> allCsvsList = [
                SELECT Title, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :linkedDocIdSet
                AND IsLatest = true
                AND FileExtension = 'csv'
            ];

            if (allCsvsList.isEmpty()) {
                archiveDeleteSet.add(currentArchive.Id);
                continue;
            }

            for (ContentVersion currentVersion : allCsvsList) {
                docDeleteSet.add(currentVersion.ContentDocumentId);
            }

            // ===== 3. Separate parent CSV vs child CSVs =====
            List<ContentVersion> parentCsvsList = new List<ContentVersion>();
            List<ContentVersion> childCsvsList  = new List<ContentVersion>();

            for (ContentVersion currentVersion : allCsvsList) {

                if (currentVersion.Title == parentObjectNameStr) {
                    parentCsvsList.add(currentVersion);
                } else {
                    childCsvsList.add(currentVersion);
                }
            }

            // ===== 4. Insert PARENT records first =====
            for (ContentVersion currentVersion : parentCsvsList) {

                Schema.SObjectType objType = globalMap.get(parentObjectNameStr);
                if (objType == null) continue;
                insertRecordsFromCsv(currentVersion, objType);
            }

            // ===== 5. Insert CHILD records after parent =====
            for (ContentVersion currentVersion : childCsvsList) {

                String childObjectNameStr = currentVersion.Title;
                Schema.SObjectType objType = globalMap.get(childObjectNameStr);

                if (objType == null) {
                    System.debug('Unknown object in CSV Title: ' + childObjectNameStr);
                    continue;
                }

                insertRecordsFromCsv(currentVersion, objType);
            }

            archiveDeleteSet.add(currentArchive.Id);
        }

        // ===== 6. Cleanup =====
        if (!docDeleteSet.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docDeleteSet];
        }

        if (!archiveDeleteSet.isEmpty()) {
            delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archiveDeleteSet];
        }
    }

    /**
     * @description Parses a CSV ContentVersion and inserts the records into
     *              the specified SObject type.
     * @param contentVersion The ContentVersion containing CSV data.
     * @param objType The Schema.SObjectType to insert records into.
     */
    private void insertRecordsFromCsv(ContentVersion contentVersion, Schema.SObjectType objType) {

        Map<String, Schema.SObjectField> fieldMap =
            objType.getDescribe().fields.getMap();

        List<String> linesList = contentVersion.VersionData.toString().split('\n');
        if (linesList.size() < 2) return;

        List<String> headersList = linesList[0].split(',');

        List<SObject> bufferList = new List<SObject>();

        for (Integer rowIndex = 1; rowIndex < linesList.size(); rowIndex++) {

            if (String.isBlank(linesList[rowIndex])) continue;

            List<String> valuesList = parseCsvLine(linesList[rowIndex]);
            SObject newRecord = objType.newSObject();
            Boolean hasDataFlag = false;

            for (Integer colIndex = 0; colIndex < headersList.size() && colIndex < valuesList.size(); colIndex++) {

                String fieldNameStr = headersList[colIndex].trim();

                if (fieldNameStr == 'Id' || !fieldMap.containsKey(fieldNameStr.toLowerCase())) continue;

                Schema.DescribeFieldResult fieldDescribe =
                    fieldMap.get(fieldNameStr.toLowerCase()).getDescribe();

                if (!fieldDescribe.isCreateable()) continue;

                String rawValueStr = valuesList[colIndex].replace('"', '').trim();
                if (String.isBlank(rawValueStr)) continue;

                try {
                    switch on fieldDescribe.getType() {
                        when Currency, Double, Percent {
                            newRecord.put(fieldNameStr, Decimal.valueOf(rawValueStr));
                        }
                        when Integer {
                            newRecord.put(fieldNameStr, Integer.valueOf(rawValueStr));
                        }
                        when Date {
                            newRecord.put(fieldNameStr, Date.valueOf(rawValueStr));
                        }
                        when DateTime {
                            newRecord.put(fieldNameStr, Datetime.valueOf(rawValueStr));
                        }
                        when Boolean {
                            newRecord.put(fieldNameStr, rawValueStr.toLowerCase() == 'true');
                        }
                        when else {
                            newRecord.put(fieldNameStr, rawValueStr);
                        }
                    }
                    hasDataFlag = true;
                } catch (Exception ex) {
                    // Ignore invalid values safely
                }
            }

            if (hasDataFlag) bufferList.add(newRecord);

            if (bufferList.size() == 200) {
                Database.insert(bufferList, false);
                bufferList.clear();
            }
        }

        if (!bufferList.isEmpty()) {
            Database.insert(bufferList, false);
        }
    }

    /**
     * @description Parses a single CSV line, handling quoted fields that may contain commas.
     * @param lineStr The CSV line to parse.
     * @return A list of field values extracted from the line.
     */
    private List<String> parseCsvLine(String lineStr) {

        List<String> resultList = new List<String>();
        Boolean inQuotesFlag = false;
        String currentStr = '';

        for (Integer charIndex = 0; charIndex < lineStr.length(); charIndex++) {

            String charStr = lineStr.substring(charIndex, charIndex + 1);

            if (charStr == '"') {
                inQuotesFlag = !inQuotesFlag;
                currentStr += charStr;
            } else if (charStr == ',' && !inQuotesFlag) {
                resultList.add(currentStr);
                currentStr = '';
            } else {
                currentStr += charStr;
            }
        }

        resultList.add(currentStr);
        return resultList;
    }
}