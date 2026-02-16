@IsTest
private class DataArchiveScheduleControllerTest {
    @IsTest
    static void testScheduleArchive_CoversAuraEnabled() {
        // Insert required custom metadata/objects if needed for scheduleArchive
        String objectName = 'Account';
        String frequency = 'Daily';
        String dateField = 'LastModifiedDate'; // Use a standard field guaranteed to exist
        Integer days = 1;
        Test.startTest();
        String result = DataArchiveScheduleController.scheduleArchive(objectName, frequency, dateField, days);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return a job id or message');
    }
}