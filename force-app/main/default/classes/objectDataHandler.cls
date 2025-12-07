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
    Integer offsetSize,
    Integer pageSize,
    String objectName
){
    Map<String, Object> result = new Map<String, Object>();

    // Build paginated data query
    String dataQuery = query + ' LIMIT ' + pageSize + ' OFFSET ' + offsetSize;

    // Build count query (COUNT() FROM Object WHERE ...)
    // Extract WHERE clause if present
    String wherePart = '';
    if (query.contains('WHERE')) {
        wherePart = query.substringAfter('WHERE');
        wherePart = ' WHERE ' + wherePart;
    }

    String countQuery = 'SELECT COUNT() FROM ' + objectName + wherePart;

    // Execute both queries
    List<SObject> recordsList = Database.query(dataQuery);
    Integer totalCount = Database.countQuery(countQuery);

    // Put results
    result.put('records', recordsList);
    result.put('totalCount', totalCount);

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