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
// Wrapper for child records grouped by child object
// ---------------------------------------------------
public class ChildRecordsWrapper {
    @AuraEnabled public String childObjectName  { get; set; }
    @AuraEnabled public String childObjectLabel { get; set; }
    @AuraEnabled public String relationshipField { get; set; }
    @AuraEnabled public Integer recordCount     { get; set; }
    @AuraEnabled public List<SObject> records   { get; set; }
}

// ---------------------------------------------------
// Get child records for given parent record IDs
// ---------------------------------------------------
@AuraEnabled
public static List<ChildRecordsWrapper> getChildRecordsByParentIds(
    String parentObjectApiName,
    List<String> parentRecordIds
) {
    List<ChildRecordsWrapper> wrappers = new List<ChildRecordsWrapper>();

    if (String.isBlank(parentObjectApiName) || parentRecordIds == null || parentRecordIds.isEmpty()) {
        return wrappers;
    }

    // Get all child relationships for the parent object
    Schema.DescribeSObjectResult parentDescribe =
        Schema.getGlobalDescribe().get(parentObjectApiName).getDescribe();

    for (Schema.ChildRelationship cr : parentDescribe.getChildRelationships()) {
        if (cr.getRelationshipName() == null || cr.getChildSObject() == null || cr.getField() == null) {
            continue;
        }

        Schema.DescribeSObjectResult childDescribe = cr.getChildSObject().getDescribe();

        // Skip objects that are not queryable or accessible
        if (!childDescribe.isQueryable() || !childDescribe.isAccessible()) {
            continue;
        }

        String childObjectApi   = childDescribe.getName();
        String childObjectLabel = childDescribe.getLabel();
        String lookupFieldApi   = cr.getField().getDescribe().getName();

        // Build a dynamic query: SELECT Id, Name FROM ChildObject WHERE lookupField IN :parentRecordIds
        // Check if the child object has a Name field
        Map<String, Schema.SObjectField> childFields = childDescribe.fields.getMap();
        Boolean hasName = childFields.containsKey('Name')
                       && childFields.get('Name').getDescribe().isAccessible();

        String fieldList = hasName ? 'Id, Name' : 'Id';
        String query = 'SELECT ' + fieldList
                     + ' FROM ' + String.escapeSingleQuotes(childObjectApi)
                     + ' WHERE ' + String.escapeSingleQuotes(lookupFieldApi)
                     + ' IN :parentRecordIds'
                     + ' ORDER BY Id'
                     + ' LIMIT 2000';

        try {
            List<SObject> records = Database.query(query);
            if (!records.isEmpty()) {
                ChildRecordsWrapper w = new ChildRecordsWrapper();
                w.childObjectName  = childObjectApi;
                w.childObjectLabel = childObjectLabel;
                w.relationshipField = lookupFieldApi;
                w.recordCount      = records.size();
                w.records          = records;
                wrappers.add(w);
            }
        } catch (Exception e) {
            // Skip objects that fail to query (e.g. permission issues)
            System.debug('Skipping child object ' + childObjectApi + ': ' + e.getMessage());
        }
    }

    return wrappers;
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