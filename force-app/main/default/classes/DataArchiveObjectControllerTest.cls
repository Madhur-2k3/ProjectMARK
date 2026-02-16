@IsTest
private class DataArchiveObjectControllerTest {

    @TestSetup
    static void setup() {

        Data_Archive__c da = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c = 'Name',
            Status__c = 'Ready for Unarchive'
        );
        insert da;

        ContentVersion cv = new ContentVersion(
            Title = da.Name,
            PathOnClient = da.Name + '.csv',
            VersionData = Blob.valueOf('Name\nTest')
        );
        insert cv;

        cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = da.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }


    @IsTest
    static void testUnarchiveAsync_NoSelection() {
        String msg =
            DataArchiveObjectController.unarchiveAsync(new List<Id>());
        System.assertEquals('No records selected', msg);
    }

    @IsTest
    static void testUnarchiveAsync_NullInput() {
        String msg = DataArchiveObjectController.unarchiveAsync(null);
        System.assertEquals('No records selected', msg);
    }

    @IsTest
    static void testGetArchivedObjectPaginated() {
        Test.startTest();
        DataArchiveObjectController.ArchiveWrapper result = 
            DataArchiveObjectController.getArchivedObjectPaginated(1, 5);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.columns, 'Columns should not be null');
        System.assertNotEquals(null, result.data, 'Data should not be null');
        System.assertNotEquals(null, result.totalRecords, 'Total records should not be null');
    }
}