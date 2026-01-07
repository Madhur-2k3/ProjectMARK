global class InsertAccountsBatch implements Database.Batchable<Integer>, Database.Stateful {

    private Integer totalRecords;

    // Constructor to accept number of records
    global InsertAccountsBatch(Integer totalRecords) {
        this.totalRecords = totalRecords;
    }

    // Step 1: Start method – create iterable range
    global Iterable<Integer> start(Database.BatchableContext bc) {
        List<Integer> recordIndexes = new List<Integer>();
        for (Integer i = 1; i <= totalRecords; i++) {
            recordIndexes.add(i);
        }
        return recordIndexes;
    }

    // Step 2: Execute method – insert accounts in batches
    global void execute(Database.BatchableContext bc, List<Integer> scope) {
        List<Account> accountList = new List<Account>();

        for (Integer i : scope) {
            Account acc = new Account();
            acc.Name = 'Process Account ' + i;
            acc.Type = 'Customer';
            acc.Industry = 'Technology';
            acc.Rating = 'Warm';
            acc.AccountNumber = 'PRC-' + i;
            acc.Description = 'Batch created account with Process name';

            accountList.add(acc);
        }

        if (!accountList.isEmpty()) {
            insert accountList;
        }
    }

    // Step 3: Finish method
    global void finish(Database.BatchableContext bc) {
        System.debug('✅ Successfully inserted ' + totalRecords + ' Process Accounts.');
    }
}