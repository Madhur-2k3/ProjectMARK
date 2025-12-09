public with sharing class DataArchiveObjectController {

    public class ArchiveWrapper {
        @AuraEnabled public List<Map<String, Object>> columns { get; set; }
        @AuraEnabled public List<Map<String, Object>> data { get; set; }
        @AuraEnabled public Integer totalRecords { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static ArchiveWrapper getArchivedObjectPaginated(Integer pageNumber, Integer pageSize) {

        if (pageNumber == null) pageNumber = 1;
        if (pageSize == null) pageSize = 10;

        Integer offsetValue = (pageNumber - 1) * pageSize;
        Integer totalCount = [SELECT COUNT() FROM Data_Archive__c];

        List<Data_Archive__c> records = [
            SELECT Id, Name, Fields__c, Parent_Object__c, CreatedDate
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
            LIMIT :pageSize
            OFFSET :offsetValue
        ];

        List<Map<String, Object>> columns = new List<Map<String, Object>>{
            new Map<String, Object>{
                'label' => 'Data Archive Name',
                'fieldName' => 'nameUrl',
                'type' => 'url',
                'typeAttributes' => new Map<String, Object>{
                    'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
                    'target' => '_blank'
                }
            },
            new Map<String, Object>{ 'label' => 'Fields', 'fieldName' => 'Fields__c', 'type' => 'text' },
            new Map<String, Object>{ 'label' => 'Parent Object', 'fieldName' => 'Parent_Object__c', 'type' => 'text' },
            new Map<String, Object>{ 'label' => 'Created Date', 'fieldName' => 'CreatedDate', 'type' => 'text' },
            new Map<String, Object>{
                'type' => 'button-icon',
                'typeAttributes' => new Map<String, Object>{
                    'iconName' => 'utility:download',
                    'name' => 'downloadCsv',
                    'title' => 'Download CSV',
                    'variant' => 'border-filled',
                    'alternativeText' => 'Download CSV'
                },
                'initialWidth' => 50
            }
        };

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
        wrapper.totalRecords = totalCount;
        return wrapper;
    }

    @AuraEnabled
    public static String getArchiveCsvDownloadUrl(Id archiveId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :archiveId
            LIMIT 1
        ];
        if (links.isEmpty()) return null;
        return '/sfc/servlet.shepherd/document/download/' + links[0].ContentDocumentId;
    }

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

            ContentVersion cv = [
                SELECT VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Title = :archive.Name
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            contentDocIds.add(cv.ContentDocumentId);

            String csvContent = cv.VersionData.toString();
            List<String> lines = csvContent.split('\n');
            if (lines.size() < 2) continue;

            // ⭐ Build field list WITHOUT ID
            List<String> fieldNames = new List<String>();
            List<String> headerAll = archive.Fields__c.split(',');

            Integer idIndex = -1;

            for (Integer x = 0; x < headerAll.size(); x++) {
                String hf = headerAll[x].trim();
                if (hf.toLowerCase() == 'id') {
                    idIndex = x;
                } else {
                    fieldNames.add(hf);
                }
            }

            Map<String, Schema.SObjectField> fieldMap =
                Schema.getGlobalDescribe()
                    .get(archive.Parent_Object__c)
                    .getDescribe()
                    .fields.getMap();

            for (Integer i = 1; i < lines.size(); i++) {
                if (String.isBlank(lines[i])) continue;

                List<String> values = parseCsvLine(lines[i]);

                // ⭐ REMOVE EXACT ID COLUMN (so shifting never happens)
                if (idIndex >= 0 && idIndex < values.size()) {
                    values.remove(idIndex);
                }

                SObject sobj =
                    Schema.getGlobalDescribe()
                        .get(archive.Parent_Object__c)
                        .newSObject();

                for (Integer j = 0; j < fieldNames.size(); j++) {
                    if (j >= values.size()) continue;

                    String fieldAPI = fieldNames[j];
                    String rawVal = values[j].trim();
                    rawVal = rawVal.replace('"','');

                    if (!fieldMap.containsKey(fieldAPI)) continue;

                    Schema.DisplayType type =
                        fieldMap.get(fieldAPI).getDescribe().getType();

                    if (type == Schema.DisplayType.Id ||
                        type == Schema.DisplayType.String ||
                        type == Schema.DisplayType.Reference) {
                        sobj.put(fieldAPI, rawVal);
                    }
                    else if (type == Schema.DisplayType.Boolean) {
                        sobj.put(fieldAPI, rawVal.toLowerCase() == 'true');
                    }
                    else if (type == Schema.DisplayType.Integer) {
                        try {
                            sobj.put(fieldAPI, rawVal == '' ? null : Integer.valueOf(rawVal));
                        } catch (Exception e) {
                            sobj.put(fieldAPI, null);
                        }
                    }
                    else if (type == Schema.DisplayType.Double ||
                             type == Schema.DisplayType.Currency ||
                             type == Schema.DisplayType.Percent) {
                        try {
                            sobj.put(fieldAPI, rawVal == '' ? null : Decimal.valueOf(rawVal));
                        } catch (Exception e) {
                            sobj.put(fieldAPI, null);
                        }
                    }
                    else if (type == Schema.DisplayType.Date) {
                        sobj.put(fieldAPI, rawVal == '' ? null : Date.valueOf(rawVal));
                    }
                    else if (type == Schema.DisplayType.DateTime) {
                        sobj.put(fieldAPI, rawVal == '' ? null : Datetime.valueOf(rawVal));
                    }
                    else {
                        sobj.put(fieldAPI, rawVal);
                    }
                }

                newRecords.add(sobj);
            }

            archivesToDelete.add(archive.Id);
        }

        if (newRecords.isEmpty()) {
            return 'No valid data to insert (ID skipped)';
        }

        insert newRecords;
        delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archivesToDelete];
        delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocIds];

        return 'Inserted ' + newRecords.size() + ' records successfully.';
    }

    private static List<String> parseCsvLine(String line) {
        List<String> result = new List<String>();
        Boolean insideQuotes = false;
        String current = '';

        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i + 1);

            if (c == '"') {
                insideQuotes = !insideQuotes;
            }
            else if (c == ',' && !insideQuotes) {
                result.add(current);
                current = '';
            }
            else {
                current += c;
            }
        }
        result.add(current);
        return result;
    }
}