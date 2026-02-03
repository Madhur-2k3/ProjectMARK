@IsTest
private class ArchiveControllerTest {

    @TestSetup
    static void setupData() {
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accts.add(new Account(
                Name = 'Test Account ' + i,
                Phone = '9000' + i
            ));
        }
        insert accts;
    }

    // ---------------- VALIDATION TESTS (EXISTING) ----------------
    @IsTest
    static void testArchiveRecords_ValidationErrors() {

        try {
            ArchiveController.archiveRecords('', new List<Id>(), 'Name');
            System.assert(false);
        } catch (Exception e) {}

        try {
            ArchiveController.archiveRecords('Account', new List<Id>(), 'Name');
            System.assert(false);
        } catch (Exception e) {}

        try {
            ArchiveController.archiveRecords(
                'Account',
                new List<Id>{UserInfo.getUserId()},
                ''
            );
            System.assert(false);
        } catch (Exception e) {}

        try {
            ArchiveController.archiveRecords(
                'Invalid__c',
                new List<Id>{UserInfo.getUserId()},
                'Name'
            );
            System.assert(false);
        } catch (Exception e) {}
    }

    // ---------------- HAPPY PATH (NEW – REQUIRED) ----------------
    @IsTest
    static void testArchiveRecords_HappyPath() {

        List<Account> accts = [
            SELECT Id FROM Account LIMIT 2
        ];

        Test.startTest();
        String result = ArchiveController.archiveRecords(
            'Account',
            new List<Id>{ accts[0].Id, accts[1].Id },
            'Name,Phone'
        );
        Test.stopTest();

        System.assertEquals('OK', result);

        // Archive record created
        Data_Archive__c da = [
            SELECT Id, Parent_Object__c
            FROM Data_Archive__c
            LIMIT 1
        ];
        System.assertEquals('Account', da.Parent_Object__c);

        // CSV file linked
        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :da.Id
        ];
        System.assert(linkCount > 0);

        // Original records deleted
        Integer remaining = [
            SELECT COUNT()
            FROM Account
            WHERE Id IN :new List<Id>{ accts[0].Id, accts[1].Id }
        ];
        System.assertEquals(0, remaining);
    }
}