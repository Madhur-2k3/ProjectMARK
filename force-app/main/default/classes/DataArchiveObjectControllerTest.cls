/**
 * @description Tests for DataArchiveObjectController.
 */
@IsTest
private class DataArchiveObjectControllerTest {

    @TestSetup
    static void setup() {

        Data_Archive__c myArchiveRecord = new Data_Archive__c(
            Parent_Object__c = 'Account',
            Fields__c = 'Name',
            Status__c = 'Ready for Unarchive'
        );
        insert myArchiveRecord;

        ContentVersion myContentVersion = new ContentVersion(
            Title = myArchiveRecord.Name,
            PathOnClient = myArchiveRecord.Name + '.csv',
            VersionData = Blob.valueOf('Name\nTest')
        );
        insert myContentVersion;

        myContentVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :myContentVersion.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = myContentVersion.ContentDocumentId,
            LinkedEntityId = myArchiveRecord.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    @IsTest
    static void testUnarchiveAsync_NoSelection() {

        String myMessageStr =
            DataArchiveObjectController.unarchiveAsync(new List<Id>());
        System.assertEquals('No records selected', myMessageStr);
    }

    @IsTest
    static void testUnarchiveAsync_NullInput() {

        String myMessageStr = DataArchiveObjectController.unarchiveAsync(null);
        System.assertEquals('No records selected', myMessageStr);
    }

    @IsTest
    static void testGetArchivedObjectPaginated() {

        Test.startTest();
        DataArchiveObjectController.ArchiveWrapper myResult =
            DataArchiveObjectController.getArchivedObjectPaginated(1, 5);
        Test.stopTest();

        System.assertNotEquals(null, myResult, 'Result should not be null');
        System.assertNotEquals(null, myResult.columns, 'Columns should not be null');
        System.assertNotEquals(null, myResult.data, 'Data should not be null');
        System.assertNotEquals(null, myResult.totalRecords, 'Total records should not be null');
    }
}