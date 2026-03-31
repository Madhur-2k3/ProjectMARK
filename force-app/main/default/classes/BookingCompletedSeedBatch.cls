/**
 * @description Batch class that seeds completed booking records for testing and
 *              development purposes. Creates sample records with randomized data.
 */
public class BookingCompletedSeedBatch implements Database.Batchable<Integer>, Database.Stateful {

    private Integer totalRecordsInt;
    private Integer batchSizeInt;
    private Integer createdCountInt = 0;

    /**
     * @description Constructs a new BookingCompletedSeedBatch.
     * @param totalRecordsInt The total number of records to create.
     * @param batchSizeInt The number of records per batch execution.
     */
    public BookingCompletedSeedBatch(Integer totalRecordsInt, Integer batchSizeInt) {

        this.totalRecordsInt = totalRecordsInt;
        this.batchSizeInt = batchSizeInt;
    }

    /**
     * @description Returns an iterable of integers representing batch chunks.
     * @param batchContext The BatchableContext provided by the platform.
     * @return An iterable of Integer values, one per batch chunk.
     */
    public Iterable<Integer> start(Database.BatchableContext batchContext) {

        List<Integer> chunksList = new List<Integer>();
        Integer numChunksInt = (Integer) Math.ceil((Decimal) totalRecordsInt / batchSizeInt);

        for (Integer chunkIndex = 0; chunkIndex < numChunksInt; chunkIndex++) {
            chunksList.add(chunkIndex);
        }

        return chunksList;
    }

    /**
     * @description Creates a batch of sample Account records.
     * @param batchContext The BatchableContext provided by the platform.
     * @param scopeList The list of chunk indices in this batch execution.
     */
    public void execute(Database.BatchableContext batchContext, List<Integer> scopeList) {

        List<Account> accountsList = new List<Account>();
        Integer remainingInt = totalRecordsInt - createdCountInt;
        Integer toCreateInt = Math.min(batchSizeInt, remainingInt);

        for (Integer recordIndex = 0; recordIndex < toCreateInt; recordIndex++) {

            Account newAccount = new Account();
            newAccount.Name = 'Seed Account ' + (createdCountInt + recordIndex + 1);
            newAccount.Phone = '555-' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000)).leftPad(4, '0');
            newAccount.Website = 'https://seed' + (createdCountInt + recordIndex + 1) + '.example.com';
            accountsList.add(newAccount);
        }

        if (!accountsList.isEmpty()) {
            insert accountsList;
            createdCountInt += accountsList.size();
        }
    }

    /**
     * @description Called when the batch job finishes. Logs the total records created.
     * @param batchContext The BatchableContext provided by the platform.
     */
    public void finish(Database.BatchableContext batchContext) {

        System.debug('BookingCompletedSeedBatch finished. Created ' + createdCountInt + ' records.');
    }
}