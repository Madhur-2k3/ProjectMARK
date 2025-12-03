public with sharing class DataArchiveObjectController {

    // Wrapper class for LWC
    public class ArchiveWrapper {
        @AuraEnabled public List<Map<String, Object>> columns { get; set; }
        @AuraEnabled public List<Map<String, Object>> data { get; set; }
    }

    // ============================================================
    // 1) GET ARCHIVED OBJECTS
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static ArchiveWrapper getArchivedObject() {

        List<Data_Archive__c> records = [
            SELECT Id, Name, Fields__c, Parent_Object__c, CreatedDate
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
        ];

        List<String> selectedFields = new List<String>{
            'Name', 'Fields__c', 'Parent_Object__c', 'CreatedDate'
        };

        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap =
            Data_Archive__c.SObjectType.getDescribe().fields.getMap();

        // Dynamic Columns
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

        ArchiveWrapper wrapper = new ArchiveWrapper();
        wrapper.columns = columns;
        wrapper.data = processed;

        return wrapper;
    }

    // ============================================================
    // 2) INSERT + DELETE ARCHIVE + DELETE CSV FILE
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

            // Fetch CSV File
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

        // ✅ FIXED DELETE BLOCK
        if (!archivesToDelete.isEmpty()) {
            List<Data_Archive__c> toDelete = [
                SELECT Id FROM Data_Archive__c
                WHERE Id IN :archivesToDelete
            ];
            delete toDelete;
        }

        // Delete CSV ContentDocuments
        if (!contentDocIds.isEmpty()) {
            List<ContentDocument> docs = [
                SELECT Id FROM ContentDocument
                WHERE Id IN :contentDocIds
            ];
            delete docs;
        }

        return 'Inserted ' + newRecords.size() + ' records and deleted archive + CSV file';
    }
}