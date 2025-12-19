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
            !f.isNillable() &&
            !f.isDefaultedOnCreate() &&
            !f.isCalculated() &&
            api != 'Id';

        result.add(new FieldInfoWrapper(
            f.getLabel(),
            f.getName(),        // ✔ exact field API name
            f.getType().name(), // ✔ exact API field type (String, DateTime, Currency, Reference, etc.)
            isRequired
        ));
    }

    return result;
}
public class ChildRelationshipInfo {
    @AuraEnabled public String childObject { get; set; }
    @AuraEnabled public String relationshipField { get; set; }
    @AuraEnabled public String relationshipName { get; set; }
    @AuraEnabled public String relationshipType { get; set; } // always "Reference"
}

public static List<ChildRelationshipInfo> getChildObjectDetails(String parentObjectApiName) {

    List<ChildRelationshipInfo> results = new List<ChildRelationshipInfo>();

    Schema.DescribeSObjectResult parentDescribe =
        Schema.getGlobalDescribe().get(parentObjectApiName).getDescribe();

    for (Schema.ChildRelationship cr : parentDescribe.getChildRelationships()) {

        if (cr.getRelationshipName() != null && cr.getChildSObject() != null && cr.getField() != null) {

            Schema.DescribeFieldResult fieldDescribe = cr.getField().getDescribe();

            ChildRelationshipInfo info = new ChildRelationshipInfo();
            info.childObject       = cr.getChildSObject().getDescribe().getName();
            info.relationshipField = fieldDescribe.getName();
            info.relationshipName  = cr.getRelationshipName();
            info.relationshipType  = 'Reference'; // Lookup or Master-Detail (Apex cannot distinguish)

            results.add(info);
        }
    }

    return results;
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