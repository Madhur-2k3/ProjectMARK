public with sharing class DataArchiveObjectController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getArchivedObject() {

        List<String> selectedFields = new List<String>{
            'Name',
            'Fields__c',
            'Parent_Object__c',
            'CreatedDate'
        };

        String query = 'SELECT ' + String.join(selectedFields, ',') +
                       ' FROM Data_Archive__c';

        List<SObject> records = Database.query(query);

        List<Map<String, Object>> columns = new List<Map<String, Object>>();

        Map<String, Schema.SObjectField> fieldMap = 
            Data_Archive__c.SObjectType.getDescribe().fields.getMap();

        for (String apiName : selectedFields) {
            Schema.DescribeFieldResult f = fieldMap.get(apiName).getDescribe();

            columns.add(new Map<String, Object>{
                'label'     => f.getLabel(),
                'fieldName' => apiName
                
            });
        }

        return new Map<String, Object>{
            'columns' => columns,
            'data'    => records
        };
    }
}