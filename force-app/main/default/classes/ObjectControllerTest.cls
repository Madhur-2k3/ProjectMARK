/**
 * @description Tests for ObjectController.getSObjectNames
 */
@IsTest
private class ObjectControllerTest {

    @IsTest
    static void testGetSObjectNames_ReturnsAccessibleObjects() {
        Test.startTest();
        List<Map<String, String>> objs = ObjectController.getSObjectNames();
        Test.stopTest();

        System.assertNotEquals(null, objs, 'Result should not be null');
        System.assert(!objs.isEmpty(), 'Should return some objects');

        // Should contain a known standard object like Account (API name must be Account)
        Boolean hasAccount = false;
        for (Map<String, String> row : objs) {
            if (row != null && row.containsKey('apiName') && row.get('apiName') == 'Account') {
                hasAccount = true;
                System.assert(row.containsKey('label'), 'Each item should include label');
                break;
            }
        }
        System.assert(hasAccount, 'Expected Account to be present among accessible objects');
    }

    @IsTest
    static void testGetSObjectNames_EmptyResult() {
        // This test assumes the method handles orgs with no accessible objects gracefully
        // Not possible to force empty in standard org, but method should not throw
        Test.startTest();
        List<Map<String, String>> objs = ObjectController.getSObjectNames();
        Test.stopTest();
        System.assertNotEquals(null, objs);
    }
    
}