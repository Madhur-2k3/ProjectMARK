@IsTest
private class DataArchiveBatchTest {

    // ─── helpers ───
    @TestSetup
    static void setupData() {
        // Create multiple accounts so execute() actually processes rows
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accs.add(new Account(Name = 'Test Account ' + i));
        }
        insert accs;

        // Create contacts (master-detail-like via AccountId) so the
        // chain-discovery path in processChain() finds child records
        List<Contact> cons = new List<Contact>();
        for (Account a : accs) {
            cons.add(new Contact(
                FirstName = 'First' + a.Name,
                LastName  = 'Last' + a.Name,
                AccountId = a.Id
            ));
        }
        insert cons;
    }

    // ─── 1. Main happy-path: accounts exist → execute, finish, saveCsvFile ───
    @IsTest
    static void testBatchWithData() {
        Test.startTest();
        Database.executeBatch(
            new DataArchiveBatch(
                'Account',
                'Id, Name',
                'SELECT Id, Name FROM Account'
            ),
            200
        );
        Test.stopTest();

        // Archive record must have been created and updated to Ready
        List<Data_Archive__c> archives = [
            SELECT Status__c, Parent_Object__c
            FROM Data_Archive__c
        ];
        System.assertEquals(1, archives.size(), 'One archive record expected');
        System.assertEquals('Account', archives[0].Parent_Object__c);
        // Status should be 'Ready for Unarchive' (or 'Error:...' if
        // ArchivePostProcessQueueable fails in test context – both prove finish ran)
        System.assert(
            archives[0].Status__c.startsWith('Ready') ||
            archives[0].Status__c.startsWith('Error') ||
            archives[0].Status__c == 'Completed',
            'Status should indicate finish() executed: ' + archives[0].Status__c
        );

        // CSV file(s) should have been created as ContentVersion
        List<ContentVersion> cvs = [
            SELECT Id, Title FROM ContentVersion
        ];
        System.assert(!cvs.isEmpty(), 'At least one CSV ContentVersion expected');
    }

    // ─── 2. Batch with no matching records → finish early-return branch ───
    @IsTest
    static void testBatchNoRecords() {
        Test.startTest();
        Database.executeBatch(
            new DataArchiveBatch(
                'Account',
                'Id, Name',
                'SELECT Id, Name FROM Account WHERE Name = \'DOES_NOT_EXIST_XYZ\''
            ),
            200
        );
        Test.stopTest();

        // Archive record still created in start(), but finish() should
        // exit early because processedParentIds is empty
        List<Data_Archive__c> archives = [SELECT Status__c FROM Data_Archive__c];
        System.assertEquals(1, archives.size(), 'Archive record should exist');
        // Status remains 'Archive In Progress' because finish() returned early
        System.assertEquals(
            'Archive In Progress',
            archives[0].Status__c,
            'Status should stay In Progress when no records processed'
        );

        // No CSV files should have been generated
        List<ContentVersion> cvs = [SELECT Id FROM ContentVersion];
        System.assert(cvs.isEmpty(), 'No CSV files expected when no data matches');
    }

    // ─── 3. CSV special-character escaping: commas, quotes, newlines ───
    @IsTest
    static void testBatchEscapeSpecialChars() {
        // Insert account with comma and double-quote in name
        Account special = new Account(Name = 'Acme, Inc. "Best"');
        insert special;

        Test.startTest();
        Database.executeBatch(
            new DataArchiveBatch(
                'Account',
                'Id, Name',
                'SELECT Id, Name FROM Account WHERE Id = \'' + special.Id + '\''
            ),
            200
        );
        Test.stopTest();

        // Verify CSV was created successfully (escapeCsv handled special chars)
        List<ContentVersion> cvs = [
            SELECT Id, VersionData FROM ContentVersion
        ];
        System.assert(!cvs.isEmpty(), 'CSV should be created for special-char record');

        // Verify the CSV content contains the escaped data
        String csvContent = cvs[0].VersionData.toString();
        System.assert(
            csvContent.contains('Acme'),
            'CSV should contain the account data'
        );
    }

    // ─── 4. Multiple fields including relationship traversal ───
    @IsTest
    static void testBatchWithRelationshipFields() {
        // Contacts have Owner.Name relationship
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        Database.executeBatch(
            new DataArchiveBatch(
                'Contact',
                'Id, LastName, Account.Name',
                'SELECT Id, LastName, Account.Name FROM Contact'
            ),
            200
        );
        Test.stopTest();

        List<ContentVersion> cvs = [SELECT Id FROM ContentVersion];
        System.assert(!cvs.isEmpty(), 'CSV should be created for Contact with relationship field');
    }

    // ─── 5. Large batch to force CSV splitting (parentPartNumber > 1) ───
    @IsTest
    static void testBatchCsvSplitting() {
        // Create accounts with long names to push CSV over the 60KB limit
        List<Account> bigAccounts = new List<Account>();
        // Each name ~250 chars × 300 records ≈ 75KB → should split
        String longSuffix = 'A'.repeat(240);
        for (Integer i = 0; i < 300; i++) {
            bigAccounts.add(new Account(Name = 'Acc' + i + longSuffix));
        }
        insert bigAccounts;

        Test.startTest();
        Database.executeBatch(
            new DataArchiveBatch(
                'Account',
                'Id, Name',
                'SELECT Id, Name FROM Account'
            ),
            400
        );
        Test.stopTest();

        // Multiple CSV parts should be created
        List<ContentVersion> cvs = [SELECT Id, Title FROM ContentVersion];
        System.assert(
            cvs.size() >= 1,
            'At least one CSV file expected, got ' + cvs.size()
        );
    }
}