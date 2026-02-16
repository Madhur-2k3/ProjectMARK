@IsTest
private class DataArchiveControllerTest {

    @TestSetup
    static void setupData() {
        insert new Account(Name = 'DA Test');
    }

    // -------- VALIDATION TESTS (EXISTING) --------
    @IsTest
    static void testArchiveSelectedRecords_NullInputs() {
        try {
            DataArchiveController.archiveSelectedRecords(null, null, null);
            System.assert(false);
        } catch (Exception e) {}
        try {
            DataArchiveController.archiveSelectedRecords('Account', null, 'Name');
            System.assert(false);
        } catch (Exception e) {}
        try {
            DataArchiveController.archiveSelectedRecords('Account', new List<Id>(), null);
            System.assert(false);
        } catch (Exception e) {}
    }
    @IsTest
    static void testValidations_NoRecordsFound_AndInvalidInputs() {

        try {
            DataArchiveController.archiveAllRecords('Account', 'Name', '');
            System.assert(false);
        } catch (Exception e) {}

        try {
            DataArchiveController.archiveSelectedRecords(
                'Account',
                new List<Id>(),
                'Name'
            );
            System.assert(false);
        } catch (Exception e) {}

        try {
            Account a = [SELECT Id FROM Account LIMIT 1];
            DataArchiveController.archiveSelectedRecords(
                'Invalid__c',
                new List<Id>{a.Id},
                'Name'
            );
            System.assert(false);
        } catch (Exception e) {}
    }

    // -------- HAPPY PATH – SELECTED RECORDS --------
    @IsTest
    static void testArchiveSelectedRecords_HappyPath() {

        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Id archiveId = DataArchiveController.archiveSelectedRecords(
            'Account',
            new List<Id>{ a.Id },
            'Name'
        );
        Test.stopTest();

        System.assertNotEquals(null, archiveId);

        Integer links = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :archiveId
        ];
        System.assert(links > 0);
    }

    // -------- HAPPY PATH – ARCHIVE ALL --------
    @IsTest
    static void testArchiveAllRecords_HappyPath() {

        String query =
            'SELECT Id, Name FROM Account WHERE Name LIKE \'DA%\''; 

        Test.startTest();
        Id archiveId = DataArchiveController.archiveAllRecords(
            'Account',
            'Name',
            query
        );
        Test.stopTest();

        System.assertNotEquals(null, archiveId);
    }
}