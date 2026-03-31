/**
 * @description Controller that provides a list of all accessible SObject types
 *              in the org, returning their labels and API names.
 */
public with sharing class ObjectController {

    /**
     * @description Retrieves all accessible SObject names from the global schema.
     * @return A list of maps, each containing 'label' and 'apiName' keys.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSObjectNames() {

        List<Map<String, String>> resultsList = new List<Map<String, String>>();

        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();

        for (String apiNameStr : schemaMap.keySet()) {

            Schema.SObjectType sObjectType = schemaMap.get(apiNameStr);
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();

            if (describeResult.isAccessible()) {
                resultsList.add(new Map<String, String>{
                    'label' => describeResult.getLabel(),
                    'apiName' => apiNameStr
                });
            }
        }

        return resultsList;
    }
}