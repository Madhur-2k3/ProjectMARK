public with sharing class ObjectController {
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSObjectNames() {
        List<Map<String, String>> results = new List<Map<String, String>>();

       
        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();

        for (String apiName : schemaMap.keySet()) {
            Schema.SObjectType sObjType = schemaMap.get(apiName);
            Schema.DescribeSObjectResult describe = sObjType.getDescribe();

           
            if (describe.isAccessible()) {
                results.add(new Map<String, String>{
                    'label' => describe.getLabel(),
                    'apiName' => apiName
                });
            }
        }
        

        return results;
    }
}