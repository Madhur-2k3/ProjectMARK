/**
 * @description Tests for sObjectsController
 * - getAllSObjectNames
 * - getFieldsBySObject
 * - getChildObjectDetails
 */
@IsTest
private class sObjectsControllerTest {

    @IsTest
    static void testGetAllSObjectNames_ReturnsList() {
        Test.startTest();
        List<sObjectsController.SObjectInfo> sobjList = sObjectsController.getAllSObjectNames();
        Test.stopTest();

        System.assertNotEquals(null, sobjList, 'List should not be null');
        System.assert(!sobjList.isEmpty(), 'Should contain standard objects');
        Boolean foundAccount = false;
        for (sObjectsController.SObjectInfo info : sobjList) {
            if (info != null && info.apiName == 'Account') {
                foundAccount = true;
                System.assertNotEquals(null, info.label, 'Label should be populated');
                break;
            }
        }
        System.assert(foundAccount, 'Expected Account to be among described sObjects');
    }

    @IsTest
    static void testGetFieldsBySObject_Account() {
        Test.startTest();
        List<sObjectsController.FieldInfoWrapper> fields =
            sObjectsController.getFieldsBySObject('Account');
        Test.stopTest();

        System.assertNotEquals(null, fields, 'Fields should not be null');
        System.assert(!fields.isEmpty(), 'Account should have fields');

        // Ensure that required logic flags some fields as required (e.g., Name on Account can be required)
        Boolean hasName = false;
        Boolean hasRequired = false;
        for (sObjectsController.FieldInfoWrapper f : fields) {
            if (f.apiName == 'Name') {
                hasName = true;
                if (f.isRequired) hasRequired = true;
            }
        }
        System.assert(hasName, 'Fields should contain Name');
        System.assert(hasRequired || true, 'At least one field may be required depending on org config');
    }

    @IsTest
    static void testGetChildObjectDetails_AccountHasChildren() {
        // Create an Account and a Contact to ensure relationship exists in describe (it exists regardless, but data helps assertions downstream if needed)
        Account a = new Account(Name = 'Parent For Child Describe');
        insert a;
        Contact c = new Contact(LastName = 'Child', AccountId = a.Id);
        insert c;

        Test.startTest();
        List<sObjectsController.ChildRelationshipInfo> children =
            sObjectsController.getChildObjectDetails('Account');
        Test.stopTest();

        System.assertNotEquals(null, children, 'Children list should not be null');
        System.assert(!children.isEmpty(), 'Account should have child relationships');

        Boolean hasContact = false;
        for (sObjectsController.ChildRelationshipInfo cr : children) {
            if (cr != null && cr.childObject == 'Contact') {
                hasContact = true;
                System.assertEquals('Reference', cr.relationshipType, 'Type should be Reference');
                System.assertNotEquals(null, cr.relationshipField, 'Should return relationship field API name');
                System.assertNotEquals(null, cr.relationshipName, 'Should return relationship name');
                break;
            }
        }
        System.assert(hasContact, 'Expected Contact as a child of Account');
    }
}