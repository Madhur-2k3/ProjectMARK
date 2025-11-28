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

    // Fetch all SObject names
    @AuraEnabled(cacheable=true)
    public static List<SObjectInfo> getAllSObjectNames() {
        List<SObjectInfo> sObjectList = new List<SObjectInfo>();
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();

        for (String objectApiName : globalDescribeMap.keySet()) {
            Schema.DescribeSObjectResult describeResult = globalDescribeMap.get(objectApiName).getDescribe();
            sObjectList.add(new SObjectInfo(describeResult.getLabel(), objectApiName));
        }

        return sObjectList;
    }

    // Fetch all fields of a given SObject including field type
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getFieldsBySObject(String sObjectApiName) {
        List<FieldInfo> fieldInfoList = new List<FieldInfo>();

        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(sObjectApiName);
        if (sObjectType == null) return fieldInfoList;

        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

        for (String fieldApiName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            String fieldTypeString = String.valueOf(fieldDescribe.getType());

            fieldInfoList.add(new FieldInfo(
                fieldDescribe.getLabel(),
                fieldApiName,
                fieldTypeString
            ));
        }

        return fieldInfoList;
    }
}