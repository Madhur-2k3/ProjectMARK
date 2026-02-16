/**
 * @description Tests for objectDataHandler
 * - getFilteredAccounts: verifies records + totalCount logic and WHERE extraction
 * - getRecordCount: verifies count with/without conditions
 */
@IsTest
private class objectDataHandlerTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 6; i++) {
            // Avoid '%' modulo operator tokenization issue in some linters by using arithmetic instead
            Boolean isEven = Math.mod(i, 2) == 0;
            String nm = (isEven) ? 'Filter Me ' + i : 'Other ' + i;
            accs.add(new Account(Name = nm, Phone = '800-000' + i));
        }
        insert accs;
    }

    @IsTest
    static void testGetFilteredAccounts_PaginationAndCount_WithWhere() {
        // Base SOQL selecting from Account
        String baseQuery = 'SELECT Id, Name FROM Account WHERE Name LIKE \'Filter Me %\' ORDER BY CreatedDate DESC';

        // Request first page (LIMIT/OFFSET applied inside the method)
        Test.startTest();
        Map<String, Object> result = objectDataHandler.getFilteredAccounts(
            baseQuery,
            0,     // offset
            2,     // pageSize
            'Account'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('records') && result.containsKey('totalCount'), 'Map should contain both records and totalCount');

        List<SObject> records = (List<SObject>)result.get('records');
        Integer totalCount = (Integer)result.get('totalCount');

        // We inserted 3 records matching 'Filter Me %%' (i=0,2,4)
        System.assertEquals(3, totalCount, 'Total count should reflect WHERE condition');
        System.assertEquals(2, records.size(), 'Should return limited page size');
    }

    @IsTest
    static void testGetFilteredAccounts_NullInputs() {
        Test.startTest();
        // Null SOQL
        try {
            objectDataHandler.getFilteredAccounts(null, 0, 2, 'Account');
            System.assert(false);
        } catch (Exception e) {}
        // Null object
        try {
            objectDataHandler.getFilteredAccounts('SELECT Id FROM Account', 0, 2, null);
            System.assert(false);
        } catch (Exception e) {}
        Test.stopTest();
    }

    @IsTest
    static void testGetFilteredAccounts_Pagination_NoWhere() {
        // Base SOQL without WHERE
        String baseQuery = 'SELECT Id, Name FROM Account ORDER BY CreatedDate DESC';

        Test.startTest();
        Map<String, Object> result = objectDataHandler.getFilteredAccounts(
            baseQuery,
            0,
            5,
            'Account'
        );
        Test.stopTest();

        List<SObject> records = (List<SObject>)result.get('records');
        Integer totalCount = (Integer)result.get('totalCount');

        System.assert(totalCount >= 6, 'Should count all accounts inserted in setup');
        System.assert(records.size() <= 5, 'Should obey page size');
    }

    @IsTest
    static void testGetRecordCount_WithAndWithoutConditions() {
        // Without conditions
        Integer allCount = objectDataHandler.getRecordCount('Account', null);
        System.assert(allCount >= 6, 'Should include all inserted accounts');

        // With conditions
        Integer filtered = objectDataHandler.getRecordCount('Account', 'Name LIKE \'Filter Me %\'');
        System.assertEquals(3, filtered, 'Should count only names matching Filter Me %');
    }
}