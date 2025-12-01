public with sharing class sObjectsController {
    // Wrapper for SObject names
    public class SObjectInfo {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }

        public SObjectInfo(String label, String apiName) {
            this.label = label;
            this.apiName = apiName;
        }
    }

    // Wrapper for Field info including type
    public class FieldInfo {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String fieldType { get; set; }

        public FieldInfo(String label, String apiName, String fieldType) {
            this.label = label;
            this.apiName = apiName;
            this.fieldType = fieldType;
        }
    }

    // Fetch all SObject names - SORTED by label
    @AuraEnabled(cacheable=true)
    public static List<SObjectInfo> getAllSObjectNames() {
        List<SObjectInfo> sObjectList = new List<SObjectInfo>();
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();

        // Step 1: Convert keys to list
        List<String> apiNames = new List<String>(globalDescribeMap.keySet());

        // Step 2: Sort API names alphabetically
        apiNames.sort();

        // Step 3: Build wrapper list in sorted order
        for (String apiName : apiNames) {
            Schema.DescribeSObjectResult describeResult = globalDescribeMap.get(apiName).getDescribe();
            sObjectList.add(new SObjectInfo(describeResult.getLabel(), apiName));
        }

        return sObjectList;
    }

    // Fetch all fields of a given SObject - SORTED by label
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getFieldsBySObject(String sObjectApiName) {
        List<FieldInfo> fieldInfoList = new List<FieldInfo>();

        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(sObjectApiName);
        if (sObjectType == null) return fieldInfoList;

        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

        // Step 1: Convert field API names to a list
        List<String> fieldApiNames = new List<String>(fieldMap.keySet());

        // Step 2: Sort alphabetically
        fieldApiNames.sort();

        // Step 3: Build wrapper list in sorted order
        for (String fieldApiName : fieldApiNames) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            System.debug('Field API Name: ' + fieldDescribe.getName());
            String fieldTypeString = String.valueOf(fieldDescribe.getType());
            fieldInfoList.add(new FieldInfo(
                fieldDescribe.getLabel(),
                fieldDescribe.getName(),
                fieldTypeString
            ));
        }
        // System.debug('Field Info List: ' + fieldInfoList);
        return fieldInfoList;
    }
}