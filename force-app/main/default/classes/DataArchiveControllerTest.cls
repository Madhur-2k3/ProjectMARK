@IsTest
private class DataArchiveControllerTest {

    @TestSetup
    static void setupData() {
        insert new Account(Name = 'DA Test');
    }

    // ─── VALIDATION TESTS ────────────────────────────────────────────

    @IsTest
    static void testArchiveSelectedRecords_NullInputs() {
        try {
            DataArchiveController.archiveSelectedRecords(null, null, null);
            System.assert(false, 'Should throw');
        } catch (Exception e) {}

        try {
            DataArchiveController.archiveSelectedRecords('Account', null, 'Name');
            System.assert(false, 'Should throw');
        } catch (Exception e) {}

        try {
            DataArchiveController.archiveSelectedRecords('Account', new List<Id>(), null);
            System.assert(false, 'Should throw');
        } catch (Exception e) {}
    }

    @IsTest
    static void testValidations_NoRecordsFound_AndInvalidInputs() {
        try {
            DataArchiveController.archiveAllRecords('Account', 'Name', '');
            System.assert(false, 'Should throw');
        } catch (Exception e) {}

        try {
            DataArchiveController.archiveSelectedRecords(
                'Account',
                new List<Id>(),
                'Name'
            );
            System.assert(false, 'Should throw');
        } catch (Exception e) {}

        try {
            Account a = [SELECT Id FROM Account LIMIT 1];
            DataArchiveController.archiveSelectedRecords(
                'Invalid__c',
                new List<Id>{a.Id},
                'Name'
            );
            System.assert(false, 'Should throw');
        } catch (Exception e) {}
    }

    // ─── ARCHIVE ALL – Invalid SOQL (no FROM keyword) ────────────────

    @IsTest
    static void testArchiveAllRecords_InvalidSoql() {
        try {
            // This string has no ' from ' (with spaces), so replaceSelect throws
            DataArchiveController.archiveAllRecords('Account', 'Name', 'SELECTWHERENOFROMHERE');
            System.assert(false, 'Should throw for invalid SOQL');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
    }

    // ─── ARCHIVE ALL – Blank object / field validations ──────────────

    @IsTest
    static void testArchiveAllRecords_BlankObjectName() {
        try {
            DataArchiveController.archiveAllRecords('', 'Name', 'SELECT Id FROM Account');
            System.assert(false, 'Should throw for blank object');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null);
        }
    }

    @IsTest
    static void testArchiveAllRecords_BlankFields() {
        try {
            DataArchiveController.archiveAllRecords('Account', '', 'SELECT Id FROM Account');
            System.assert(false, 'Should throw for blank fields');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null);
        }
    }

    // ─── HAPPY PATH – SELECTED RECORDS ───────────────────────────────

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

        System.assertNotEquals(null, archiveId, 'archiveId should not be null');
    }

    // ─── HAPPY PATH – ARCHIVE ALL ────────────────────────────────────

    @IsTest
    static void testArchiveAllRecords_HappyPath() {
        String query = 'SELECT Id, Name FROM Account WHERE Name LIKE \'DA%\'';

        Test.startTest();
        Id archiveId = DataArchiveController.archiveAllRecords(
            'Account',
            'Name',
            query
        );
        Test.stopTest();

        System.assertNotEquals(null, archiveId);
    }

    // ─── getBatchStatus ──────────────────────────────────────────────

    @IsTest
    static void testGetBatchStatus() {
        String soql = 'SELECT Id, Name FROM Account WHERE Name LIKE \'DA%\'';

        Test.startTest();
        Id batchJobId = Database.executeBatch(
            new DataArchiveBatch('Account', 'Name', soql), 200
        );
        Test.stopTest();

        Map<String, Object> status = DataArchiveController.getBatchStatus(batchJobId);
        System.assertNotEquals(null, status, 'Status map should not be null');
        System.assert(status.containsKey('status'), 'Should contain status key');
        System.assert(status.containsKey('processed'), 'Should contain processed key');
        System.assert(status.containsKey('total'), 'Should contain total key');
        System.assert(status.containsKey('errors'), 'Should contain errors key');
    }

    // ─── getArchiveRecordId ──────────────────────────────────────────

    @IsTest
    static void testGetArchiveRecordId_WithRecord() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Id archiveId = DataArchiveController.archiveSelectedRecords(
            'Account',
            new List<Id>{ a.Id },
            'Name'
        );
        Test.stopTest();

        Id result = DataArchiveController.getArchiveRecordId(archiveId);
        System.assertNotEquals(null, result, 'Should return the archive record Id');
    }

    @IsTest
    static void testGetArchiveRecordId_NoRecords() {
        delete [SELECT Id FROM Data_Archive__c];

        Id result = DataArchiveController.getArchiveRecordId(null);
        System.assertEquals(null, result, 'Should return null when no archive records exist');
    }

    // ─── SELECTED – Multiple fields with Id already in the list ──────

    @IsTest
    static void testArchiveSelectedRecords_MultipleFieldsWithId() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Id archiveId = DataArchiveController.archiveSelectedRecords(
            'Account',
            new List<Id>{ a.Id },
            'Id,Name'
        );
        Test.stopTest();

        System.assertNotEquals(null, archiveId, 'Should succeed with Id already in fields');
    }
}