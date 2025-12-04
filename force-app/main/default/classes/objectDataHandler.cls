public with sharing class objectDataHandler {

    @AuraEnabled(cacheable=true)
    public static List<SObject> getFilteredAccounts(String objectName, String fields, String conditions, Integer offsetSize, Integer pageSize){
        if (pageSize == null) pageSize = 10;
        if (offsetSize == null) offsetSize = 0;

        String selectedFields = 'Id';
        if (String.isNotBlank(fields)) {
            selectedFields += ',' + fields;
        }

        String query = 'SELECT ' + selectedFields + ' FROM ' + objectName;

        if (String.isNotBlank(conditions)) {
            query += ' WHERE ' + conditions;
        }

        query += ' LIMIT ' + pageSize + ' OFFSET ' + offsetSize;
        System.debug('FINAL QUERY (paginated): ' + query);

        return Database.query(query);
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