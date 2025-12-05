public with sharing class objectDataHandler {

    // @AuraEnabled(cacheable=true)
    // public static List<SObject> getFilteredAccounts(String query, String conditions, Integer offsetSize, Integer pageSize){
    //     // if (pageSize == null) pageSize = 10;
    //     // if (offsetSize == null) offsetSize = 0;

    //     // String selectedFields = 'Id';
    //     // if (String.isNotBlank(fields)) {
    //     //     selectedFields += ',' + fields;
    //     // }

    //     // String query = 'SELECT ' + selectedFields + ' FROM ' + objectName;

    //     // if (String.isNotBlank(conditions)) {
    //     //     query += ' WHERE ' + conditions;
    //     // }

    //     // query += ' LIMIT ' + pageSize + ' OFFSET ' + offsetSize;
    //     // System.debug('FINAL QUERY (paginated): ' + query);

    //     // return Database.query(query);
    //     String paginatedQuery = '';
    //     try{
    //         paginatedQuery = query+' '+conditions + ' LIMIT ' + pageSize + ' OFFSET ' + offsetSize;
    //         //  return Database.query(paginatedQuery);
    //     }
    //     catch(Exception e){
    //         System.debug('Error in query formation: ' + e.getMessage());
    //     }
    //     return Database.query(paginatedQuery);
    // }

    @AuraEnabled
    public static Map<String, Object> getFilteredAccounts(
        String query,
        String conditions,
        Integer offsetSize,
        Integer pageSize,
        String objectName
    ){
        Map<String, Object> result = new Map<String, Object>();
        
        // Build data query
        String dataQuery = query + ' ' + conditions + 
            ' LIMIT ' + pageSize + ' OFFSET ' + offsetSize;
        
        // Build count query
        String countQuery = 'SELECT COUNT() FROM ' + objectName;
        if (String.isNotBlank(conditions)) {
            countQuery +=  conditions;
        }

        // Put values in result map
        result.put('records', Database.query(dataQuery));
        result.put('totalCount', Database.countQuery(countQuery));

        return result;
    }


    @AuraEnabled(cacheable=true)
    public static Integer getRecordCount(String objectName, String conditions){
        String query = 'SELECT COUNT() FROM ' + objectName;
        if (String.isNotBlank(conditions)) {
            query += ' WHERE ' + conditions;
        }
        return Database.countQuery(query);
    }
}