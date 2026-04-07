/**
 * @description Tests for objectDataHandler.
 *              Verifies getFilteredAccounts and getRecordCount logic.
 */
@IsTest
private class objectDataHandlerTest {

    @TestSetup
    static void setupData() {

        List<Account> myAccountsList = new List<Account>();

        for (Integer myIndex = 0; myIndex < 6; myIndex++) {

            Boolean myIsEvenFlag = Math.mod(myIndex, 2) == 0;
            String myNameStr = (myIsEvenFlag) ? 'Filter Me ' + myIndex : 'Other ' + myIndex;
            myAccountsList.add(new Account(Name = myNameStr, Phone = '800-000' + myIndex));
        }

        insert myAccountsList;
    }

    @IsTest
    static void testGetFilteredAccounts_PaginationAndCount_WithWhere() {

        String myBaseQueryStr = 'SELECT Id, Name FROM Account WHERE Name LIKE \'Filter Me %\' ORDER BY CreatedDate DESC';

        Test.startTest();
        Map<String, Object> myResultMap = objectDataHandler.getFilteredAccounts(
            myBaseQueryStr,
            0,
            2,
            'Account'
        );
        Test.stopTest();

        System.assertNotEquals(null, myResultMap, 'Result should not be null');
        System.assert(myResultMap.containsKey('records') && myResultMap.containsKey('totalCount'),
            'Map should contain both records and totalCount');

        List<SObject> myRecordsList = (List<SObject>)myResultMap.get('records');
        Integer myTotalCountInt = (Integer)myResultMap.get('totalCount');

        System.assertEquals(3, myTotalCountInt, 'Total count should reflect WHERE condition');
        System.assertEquals(2, myRecordsList.size(), 'Should return limited page size');
    }

    @IsTest
    static void testGetFilteredAccounts_NullInputs() {

        Test.startTest();

        try {
            objectDataHandler.getFilteredAccounts(null, 0, 2, 'Account');
            System.assert(false);
        } catch (Exception myException) {}

        try {
            objectDataHandler.getFilteredAccounts('SELECT Id FROM Account', 0, 2, null);
            System.assert(false);
        } catch (Exception myException) {}

        Test.stopTest();
    }

    @IsTest
    static void testGetFilteredAccounts_Pagination_NoWhere() {

        String myBaseQueryStr = 'SELECT Id, Name FROM Account ORDER BY CreatedDate DESC';

        Test.startTest();
        Map<String, Object> myResultMap = objectDataHandler.getFilteredAccounts(
            myBaseQueryStr,
            0,
            5,
            'Account'
        );
        Test.stopTest();

        List<SObject> myRecordsList = (List<SObject>)myResultMap.get('records');
        Integer myTotalCountInt = (Integer)myResultMap.get('totalCount');

        System.assert(myTotalCountInt >= 6, 'Should count all accounts inserted in setup');
        System.assert(myRecordsList.size() <= 5, 'Should obey page size');
    }

    @IsTest
    static void testGetRecordCount_WithAndWithoutConditions() {

        Integer myAllCountInt = objectDataHandler.getRecordCount('Account', null);
        System.assert(myAllCountInt >= 6, 'Should include all inserted accounts');

        Integer myFilteredCountInt = objectDataHandler.getRecordCount('Account', 'Name LIKE \'Filter Me %\'');
        System.assertEquals(3, myFilteredCountInt, 'Should count only names matching Filter Me %');
    }
}