/**
 * @description Tests for ObjectController.getSObjectNames.
 */
@IsTest
private class ObjectControllerTest {

    @IsTest
    static void testGetSObjectNames_ReturnsAccessibleObjects() {

        Test.startTest();
        List<Map<String, String>> myObjectsList = ObjectController.getSObjectNames();
        Test.stopTest();

        System.assertNotEquals(null, myObjectsList, 'Result should not be null');
        System.assert(!myObjectsList.isEmpty(), 'Should return some objects');

        // Should contain a known standard object like Account
        Boolean myHasAccountFlag = false;

        for (Map<String, String> myCurrentRow : myObjectsList) {

            if (myCurrentRow != null && myCurrentRow.containsKey('apiName') && myCurrentRow.get('apiName') == 'Account') {
                myHasAccountFlag = true;
                System.assert(myCurrentRow.containsKey('label'), 'Each item should include label');
                break;
            }
        }

        System.assert(myHasAccountFlag, 'Expected Account to be present among accessible objects');
    }

    @IsTest
    static void testGetSObjectNames_EmptyResult() {

        Test.startTest();
        List<Map<String, String>> myObjectsList = ObjectController.getSObjectNames();
        Test.stopTest();

        System.assertNotEquals(null, myObjectsList);
    }
}