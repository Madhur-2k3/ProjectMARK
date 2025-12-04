public with sharing class DataArchiveObjectController {

    // Wrapper class for LWC
    public class ArchiveWrapper {
        @AuraEnabled public List<Map<String, Object>> columns { get; set; }
        @AuraEnabled public List<Map<String, Object>> data { get; set; }
        @AuraEnabled public Integer totalRecords { get; set; }
    }

    // ============================================================
    // 1) SERVER-SIDE PAGINATION
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static ArchiveWrapper getArchivedObjectPaginated(Integer pageNumber, Integer pageSize) {

        if (pageNumber == null) pageNumber = 1;
        if (pageSize == null) pageSize = 10;

        Integer offsetValue = (pageNumber - 1) * pageSize;

        // Total record count
        Integer totalCount = [SELECT COUNT() FROM Data_Archive__c];

        // Fetch only requested page
        List<Data_Archive__c> records = [
            SELECT Id, Name, Fields__c, Parent_Object__c, CreatedDate
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
            LIMIT :pageSize
            OFFSET :offsetValue
        ];

        // Fields for table
        List<String> selectedFields = new List<String>{
            'Name', 'Fields__c', 'Parent_Object__c', 'CreatedDate'
        };

        // Build columns dynamically
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap =
            Data_Archive__c.SObjectType.getDescribe().fields.getMap();

        for (String apiName : selectedFields) {
            Schema.DescribeFieldResult f = fieldMap.get(apiName).getDescribe();

            if (apiName == 'Name') {
                columns.add(new Map<String, Object>{
                    'label' => f.getLabel(),
                    'fieldName' => 'nameUrl',
                    'type' => 'url',
                    'typeAttributes' => new Map<String, Object>{
                        'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
                        'target' => '_blank'
                    }
                });
            } else {
                columns.add(new Map<String, Object>{
                    'label' => f.getLabel(),
                    'fieldName' => apiName,
                    'type' => 'text'
                });
            }
        }

        // Create data rows
        List<Map<String, Object>> processed = new List<Map<String, Object>>();

        for (Data_Archive__c rec : records) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', rec.Id);
            row.put('Name', rec.Name);
            row.put('Fields__c', rec.Fields__c);
            row.put('Parent_Object__c', rec.Parent_Object__c);
            row.put('CreatedDate', rec.CreatedDate);
            row.put('nameUrl', '/' + rec.Id);
            processed.add(row);
        }

        // Return wrapper
        ArchiveWrapper wrapper = new ArchiveWrapper();
        wrapper.columns = columns;
        wrapper.data = processed;
        wrapper.totalRecords = totalCount;
        return wrapper;
    }

    // ============================================================
    // 2) INSERT ARCHIVED RECORDS BACK + DELETE ARCHIVES + DELETE CSV
    // ============================================================
    @AuraEnabled
    public static String insertArchivedRecordsBulk(List<Id> archiveRecordIds) {

        List<Data_Archive__c> archives = [
            SELECT Id, Name, Fields__c, Parent_Object__c
            FROM Data_Archive__c
            WHERE Id IN :archiveRecordIds
        ];

        List<SObject> newRecords = new List<SObject>();
        List<Id> archivesToDelete = new List<Id>();
        List<Id> contentDocIds = new List<Id>();

        for (Data_Archive__c archive : archives) {

            List<ContentVersion> cvs = [
                SELECT Id, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Title = :archive.Name
                AND FileType = 'CSV'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (cvs.isEmpty()) continue;

            ContentVersion cv = cvs[0];
            contentDocIds.add(cv.ContentDocumentId);

            String csvContent = cv.VersionData.toString();
            List<String> lines = csvContent.split('\n');
            if (lines.size() < 2) continue;

            List<String> fieldNames = archive.Fields__c.split(',');
            Map<String, Schema.SObjectField> fieldMap =
                Schema.getGlobalDescribe()
                    .get(archive.Parent_Object__c)
                    .getDescribe()
                    .fields.getMap();

            for (Integer i = 1; i < lines.size(); i++) {

                if (String.isBlank(lines[i])) continue;

                List<String> values = lines[i].split(',');

                SObject sobj = Schema.getGlobalDescribe()
                    .get(archive.Parent_Object__c)
                    .newSObject();

                for (Integer j = 0; j < fieldNames.size(); j++) {

                    if (j >= values.size()) continue;

                    String fieldAPI = fieldNames[j].trim();
                    String rawVal = values[j].replace('"', '').trim();

                    if (!fieldMap.containsKey(fieldAPI)) continue;

                    Schema.DisplayType type = fieldMap.get(fieldAPI).getDescribe().getType();

                    if (type == Schema.DisplayType.Boolean)
                        sobj.put(fieldAPI, rawVal.toLowerCase() == 'true');

                    else if (type == Schema.DisplayType.Integer)
                        sobj.put(fieldAPI, rawVal == '' ? null : Integer.valueOf(rawVal));

                    else if (type == Schema.DisplayType.Double ||
                             type == Schema.DisplayType.Currency ||
                             type == Schema.DisplayType.Percent)
                        sobj.put(fieldAPI, rawVal == '' ? null : Decimal.valueOf(rawVal));

                    else if (type == Schema.DisplayType.Date)
                        sobj.put(fieldAPI, rawVal == '' ? null : Date.valueOf(rawVal));

                    else if (type == Schema.DisplayType.DateTime)
                        sobj.put(fieldAPI, rawVal == '' ? null : Datetime.valueOf(rawVal));

                    else
                        sobj.put(fieldAPI, rawVal);
                }

                newRecords.add(sobj);
            }

            archivesToDelete.add(archive.Id);
        }

        if (newRecords.isEmpty()) {
            return 'No records to insert';
        }

        insert newRecords;

        if (!archivesToDelete.isEmpty()) {
            delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archivesToDelete];
        }

        if (!contentDocIds.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocIds];
        }

        return 'Inserted ' + newRecords.size() + ' records and deleted archive + CSV file';
    }
}