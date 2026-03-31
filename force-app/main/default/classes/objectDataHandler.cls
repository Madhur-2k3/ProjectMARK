/**
 * @description Controller class that handles paginated data queries and record counting
 *              for dynamic SObject data display in Lightning components.
 */
public with sharing class objectDataHandler {

    /**
     * @description Retrieves paginated records and total count for the given query.
     * @param queryStr The base SOQL query string (without LIMIT/OFFSET).
     * @param offsetSizeInt The offset for pagination.
     * @param pageSizeInt The number of records per page.
     * @param objectNameStr The API name of the SObject being queried (used for count query).
     * @return A map containing 'records' (List of SObject) and 'totalCount' (Integer).
     */
    @AuraEnabled
    public static Map<String, Object> getFilteredAccounts(
        String queryStr,
        Integer offsetSizeInt,
        Integer pageSizeInt,
        String objectNameStr
    ) {

        Map<String, Object> resultMap = new Map<String, Object>();

        String dataQueryStr = queryStr + ' LIMIT ' + pageSizeInt + ' OFFSET ' + offsetSizeInt;

        String wherePartStr = '';

        if (queryStr.contains('WHERE')) {

            String queryAfterWhereStr = queryStr.substringAfter('WHERE');

            if (queryAfterWhereStr.contains('ORDER BY')) {
                wherePartStr = queryAfterWhereStr.substringBefore('ORDER BY');
            } else {
                wherePartStr = queryAfterWhereStr;
            }

            wherePartStr = ' WHERE ' + wherePartStr.trim();
        }

        String countQueryStr = 'SELECT COUNT() FROM ' + objectNameStr + wherePartStr;

        List<SObject> recordsList = Database.query(dataQueryStr);
        Integer totalCountInt = Database.countQuery(countQueryStr);

        resultMap.put('records', recordsList);
        resultMap.put('totalCount', totalCountInt);

        return resultMap;
    }

    /**
     * @description Returns the total record count for a given SObject with optional conditions.
     * @param objectNameStr The API name of the SObject to count.
     * @param conditionsStr Optional WHERE clause conditions (without the 'WHERE' keyword).
     * @return The total number of records matching the criteria.
     */
    @AuraEnabled(cacheable=true)
    public static Integer getRecordCount(String objectNameStr, String conditionsStr) {

        String queryStr = 'SELECT COUNT() FROM ' + objectNameStr;

        if (String.isNotBlank(conditionsStr)) {
            queryStr += ' WHERE ' + conditionsStr;
        }

        return Database.countQuery(queryStr);
    }
}