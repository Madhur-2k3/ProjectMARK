public with sharing class sObjectsController {

    // -------------------------------
    // Wrapper for SObject Names
    // -------------------------------
    public class SObjectInfo {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }

        public SObjectInfo(String label, String apiName) {
            this.label = label;
            this.apiName = apiName;
        }
    }

    // -------------------------------
    // Get ALL SObjects sorted by label
    // -------------------------------
    @AuraEnabled(cacheable=true)
    public static List<SObjectInfo> getAllSObjectNames() {
        List<SObjectInfo> sObjectList = new List<SObjectInfo>();
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();

        List<String> apiNames = new List<String>(globalDescribeMap.keySet());
        apiNames.sort();

        for (String apiName : apiNames) {
            Schema.DescribeSObjectResult d = globalDescribeMap.get(apiName).getDescribe();

            sObjectList.add(new SObjectInfo(
                d.getLabel(),
                d.getName() // TRUE API NAME
            ));
        }
        return sObjectList;
    }

    // ---------------------------------------------------
    // Get ALL fields from SObject + required field logic
    // ---------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<FieldInfoWrapper> getFieldsBySObject(String sObjectApiName) {

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(sObjectApiName);
        Schema.DescribeSObjectResult describe = objType.getDescribe();
        Map<String, Schema.SObjectField> fields = describe.fields.getMap();

        List<FieldInfoWrapper> result = new List<FieldInfoWrapper>();

        for (String api : fields.keySet()) {
            Schema.DescribeFieldResult f = fields.get(api).getDescribe();

            Boolean isRequired =
                f.isNillable() == false &&
                f.isDefaultedOnCreate() == false &&
                f.isCalculated() == false &&
                api != 'Id';   // exclude Id

            result.add(new FieldInfoWrapper(
                f.getLabel(),
                api,
                String.valueOf(f.getType()),
                isRequired
            ));
        }

        return result;
    }

    // ---------------------------------------------------
    // Wrapper for fields
    // ---------------------------------------------------
    public class FieldInfoWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Boolean isRequired;

        public FieldInfoWrapper(String l, String a, String t, Boolean r) {
            label = l;
            apiName = a;
            fieldType = t;
            isRequired = r;
        }
    }
}