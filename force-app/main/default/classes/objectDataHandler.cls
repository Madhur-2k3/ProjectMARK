public with sharing class objectDataHandler {
    @AuraEnabled(cacheable=true)
    public static List<SObject> getObjData(String searchKey) {
        String query = 'SELECT Id, Name FROM ' + searchKey + ' LIMIT 10';
        List<SObject> records = Database.query(query);
        return records;
    }
    @AuraEnabled
public static List<SObject> getAllRecordsOfSelectedObject(String objectName, List<String> fieldNames) {

    // --- SAFEGUARD: fieldNames must never be empty ---
    if (fieldNames == null || fieldNames.isEmpty()) {
        fieldNames = new List<String>{ 'Id' };  // Default field
    }

    String soql =
        'SELECT ' + String.join(fieldNames, ',') +
        ' FROM ' + objectName;

    try {
        return Database.query(soql);
    } catch (Exception e) {
        throw new AuraHandledException('SOQL FAILED: ' + e.getMessage());
    }
}

    // @AuraEnabled(cacheable=true)
    // public static List<SObject> getFilteredAccounts(String objectName,List<String> field,String operator,String value){
    //     String fieldStr = String.join(field,',');
    //     String query = 'select Id,Name,'+fieldStr+' from '+objectName+' where '+field[0]+operator+value;
    //     List<SObject> accRecords = Database.query(query);
    //     return accRecords;
    // }
    @AuraEnabled(cacheable=true)
    public static List<SObject> getFilteredAccounts(String objectName,String fields,String conditions){
        try{
            
        // If no fields given, default to Id only
        String selectedFields = 'Id';

        if (String.isNotBlank(fields)) {
            selectedFields += ',' + fields;
        }

        String query = 'SELECT ' + selectedFields + ' FROM ' + objectName;

        if (String.isNotBlank(conditions)) {
            query += ' WHERE ' + conditions;
        }

        System.debug('FINAL QUERY: ' + query);

        return Database.query(query);
        }catch(Exception ex){
            System.debug('Error fetching filtered accounts: ' + ex.getMessage());
            throw new AuraHandledException('Error fetching filtered accounts: '+ex.getMessage());
        }
    }
    @AuraEnabled
    public static void updateRecords(List<SObject> recordsToUpdate){
        try{
            update recordsToUpdate;
        }catch(Exception ex){
            throw new AuraHandledException('Error updating records: '+ex.getMessage());
        }
    }
    @AuraEnabled
    public static void deleteRecords(List<Id> recordIds){
        try{
            List<SObject> recordsToDelete = [SELECT Id FROM Account WHERE Id IN :recordIds];
            delete recordsToDelete;
        }catch(Exception ex){
            throw new AuraHandledException('Error deleting records: '+ex.getMessage());
        }
    }
}