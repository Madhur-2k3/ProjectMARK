public with sharing class DataArchiveObjectController {

    // Wrapper class for LWC
    public class ArchiveWrapper {
        @AuraEnabled public List<Map<String, Object>> columns { get; set; }
        @AuraEnabled public List<Map<String, Object>> data { get; set; }
    }

    // ================================================
    // 1) GET Data Archive Records (Dynamic Columns)
    // ================================================
    @AuraEnabled(cacheable=true)
    public static ArchiveWrapper getArchivedObject() {

        List<Data_Archive__c> records = [
            SELECT Id, Name, Fields__c, Parent_Object__c, CreatedDate
            FROM Data_Archive__c
        ];

        // Selected fields for datatable
        List<String> selectedFields = new List<String>{ 'Name', 'Fields__c', 'Parent_Object__c', 'CreatedDate' };

        // Dynamic columns
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap = Data_Archive__c.SObjectType.getDescribe().fields.getMap();

        for(String apiName : selectedFields){
            Schema.DescribeFieldResult f = fieldMap.get(apiName).getDescribe();

            if(apiName == 'Name'){
                columns.add(new Map<String, Object>{
                    'label' => f.getLabel(),
                    'fieldName' => 'nameUrl',
                    'type' => 'url',
                    'typeAttributes' => new Map<String, Object>{
                        'label' => 'Name',
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

        // Prepare data
        List<Map<String, Object>> processedRecords = new List<Map<String, Object>>();
        for(Data_Archive__c rec : records){
            Map<String, Object> mapRec = new Map<String, Object>();
            mapRec.put('Id', rec.Id);
            mapRec.put('Name', rec.Name);
            mapRec.put('Fields__c', rec.Fields__c);
            mapRec.put('Parent_Object__c', rec.Parent_Object__c);
            mapRec.put('CreatedDate', rec.CreatedDate);
            mapRec.put('nameUrl', '/' + rec.Id); // For Name link
            processedRecords.add(mapRec);
        }

        ArchiveWrapper wrapper = new ArchiveWrapper();
        wrapper.columns = columns;
        wrapper.data = processedRecords;

        return wrapper;
    }

    // ================================================
    // 2) INSERT ARCHIVED RECORDS FROM CSV
    // ================================================
    @AuraEnabled
    public static String insertArchivedRecordsBulk(List<Id> archiveRecordIds) {

        List<Data_Archive__c> archives = [
            SELECT Id, Name, Parent_Object__c, Fields__c
            FROM Data_Archive__c
            WHERE Id IN :archiveRecordIds
        ];

        List<SObject> allNewRecords = new List<SObject>();

        for(Data_Archive__c archive : archives) {

            List<ContentVersion> cvsFiles = [
                SELECT VersionData
                FROM ContentVersion
                WHERE Title = :archive.Name
                AND FileType = 'CSV'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if(cvsFiles.isEmpty()) continue;

            String csvContent = cvsFiles[0].VersionData.toString();
            List<String> csvLines = csvContent.split('\n');
            if(csvLines.size() < 2) continue;

            List<String> fieldApiNames = archive.Fields__c.split(',');
            String parentObjectName = archive.Parent_Object__c;

            for(Integer i = 1; i < csvLines.size(); i++){
                List<String> values = csvLines[i].split(',');

                if(values.isEmpty()) continue;

                SObject sobj = Schema.getGlobalDescribe().get(parentObjectName).newSObject();

                Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                    .get(parentObjectName).getDescribe().fields.getMap();

                for(Integer j = 0; j < fieldApiNames.size(); j++){
                    if(values.size() > j){
                        String fieldAPI = fieldApiNames[j].trim();
                        String rawVal = values[j].replace('"','').trim();

                        if(!fieldMap.containsKey(fieldAPI)) continue;

                        Schema.DisplayType dtype = fieldMap.get(fieldAPI).getDescribe().getType();

                        if(dtype == Schema.DisplayType.Boolean){
                            sobj.put(fieldAPI, rawVal.toLowerCase() == 'true');
                        } else if(dtype == Schema.DisplayType.Integer){
                            sobj.put(fieldAPI, rawVal == '' ? null : Integer.valueOf(rawVal));
                        } else if(dtype == Schema.DisplayType.Double || dtype == Schema.DisplayType.Currency || dtype == Schema.DisplayType.Percent){
                            sobj.put(fieldAPI, rawVal == '' ? null : Decimal.valueOf(rawVal));
                        } else if(dtype == Schema.DisplayType.Date){
                            sobj.put(fieldAPI, rawVal == '' ? null : Date.valueOf(rawVal));
                        } else if(dtype == Schema.DisplayType.DateTime){
                            sobj.put(fieldAPI, rawVal == '' ? null : Datetime.valueOf(rawVal));
                        } else {
                            sobj.put(fieldAPI, rawVal);
                        }
                    }
                }
                allNewRecords.add(sobj);
            }
        }

        if(!allNewRecords.isEmpty()){
            insert allNewRecords;
            return 'Inserted ' + allNewRecords.size() + ' records';
        }

        return 'No records to insert';
    }
}