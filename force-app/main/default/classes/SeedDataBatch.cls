public class SeedDataBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ── Constants ────────────────────────────────────────────────
    private static final Integer TOTAL_ORDERS         = 2000;
    private static final Integer INVOICES_PER_ORDER   = 2;
    private static final Integer PAYMENTS_PER_INVOICE = 3;
    private static final Integer BATCH_SIZE           = 200;
    private static final Integer PAYMENT_CHUNK_SIZE   = 9000;

    // ── Phase ────────────────────────────────────────────────────
    public enum Phase { ORDERS, INVOICES, PAYMENTS }

    // ── Stateful counters ────────────────────────────────────────
    private Phase   currentPhase;
    private Integer totalOrders   = 0;
    private Integer totalInvoices = 0;
    private Integer totalPayments = 0;

    // ── Constructor ──────────────────────────────────────────────
    public SeedDataBatch(Phase phase) {
        this.currentPhase = phase;
    }

    // ─────────────────────────────────────────────────────────────
    // START
    // ─────────────────────────────────────────────────────────────
    public Iterable<SObject> start(Database.BatchableContext bc) {

        log('START', currentPhase.name(),
            'Target → Orders: ' + TOTAL_ORDERS +
            ' | Invoices: ' + (TOTAL_ORDERS * INVOICES_PER_ORDER) +
            ' | Payments: ' + (TOTAL_ORDERS * INVOICES_PER_ORDER * PAYMENTS_PER_INVOICE)
        );

        if (currentPhase == Phase.ORDERS) {
            return new SyntheticOrderIterable(TOTAL_ORDERS);
        }

        if (currentPhase == Phase.INVOICES) {
            return Database.getQueryLocator(
                'SELECT Id FROM Order__c ORDER BY CreatedDate DESC LIMIT ' + TOTAL_ORDERS
            );
        }

        return Database.getQueryLocator(
            'SELECT Id FROM Invoice__c ORDER BY CreatedDate DESC LIMIT ' +
            (TOTAL_ORDERS * INVOICES_PER_ORDER)
        );
    }

    // ─────────────────────────────────────────────────────────────
    // EXECUTE
    // ─────────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            if (currentPhase == Phase.ORDERS) {
                insertOrders(scope.size());
            } else if (currentPhase == Phase.INVOICES) {
                insertInvoices((List<Order__c>) scope);
            } else {
                insertPayments((List<Invoice__c>) scope);
            }
        } catch (Exception e) {
            log('ERROR', currentPhase.name(),
                e.getMessage() + ' | ' + e.getStackTraceString());
        }
    }

    // ─────────────────────────────────────────────────────────────
    // FINISH (CHAINING)
    // ─────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {

        log('FINISH', currentPhase.name(),
            'Orders: '   + totalOrders +
            ' | Invoices: ' + totalInvoices +
            ' | Payments: ' + totalPayments
        );

        if (currentPhase == Phase.ORDERS) {
            Database.executeBatch(new SeedDataBatch(Phase.INVOICES), BATCH_SIZE);

        } else if (currentPhase == Phase.INVOICES) {
            Database.executeBatch(new SeedDataBatch(Phase.PAYMENTS), BATCH_SIZE);

        } else {
            log('FINISH', 'ALL', '✅ Seed Data Completed Successfully');
        }
    }

    // ─────────────────────────────────────────────────────────────
    // INSERT ORDERS (🔥 UPDATED WITH RANDOM DATA)
    // ─────────────────────────────────────────────────────────────
    private void insertOrders(Integer count) {

        List<Order__c> records = new List<Order__c>();

        for (Integer i = 0; i < count; i++) {

            // 🎯 Random Date in 2024
            Date startDate = Date.newInstance(2024, 1, 1);
            Integer randomDays = Math.mod(Math.abs(Crypto.getRandomInteger()), 365);
            Date randomDate = startDate.addDays(randomDays);

            // 🎯 Random Amount (1000 - 100000)
            Integer randomAmount = 1000 + Math.mod(Math.abs(Crypto.getRandomInteger()), 99000);

            records.add(new Order__c(
                Order_Date__c = randomDate,
                Amount__c     = randomAmount
            ));
        }

        insert records;

        totalOrders += records.size();

        log('EXECUTE', 'ORDERS',
            'Inserted ' + records.size() +
            ' | Total: ' + totalOrders);
    }

    // ─────────────────────────────────────────────────────────────
    // INSERT INVOICES
    // ─────────────────────────────────────────────────────────────
    private void insertInvoices(List<Order__c> orders) {

        List<Invoice__c> records = new List<Invoice__c>();

        for (Order__c o : orders) {
            for (Integer i = 0; i < INVOICES_PER_ORDER; i++) {
                records.add(new Invoice__c(Order__c = o.Id));
            }
        }

        insert records;

        totalInvoices += records.size();

        log('EXECUTE', 'INVOICES',
            'Inserted ' + records.size() +
            ' | Total: ' + totalInvoices);
    }

    // ─────────────────────────────────────────────────────────────
    // INSERT PAYMENTS
    // ─────────────────────────────────────────────────────────────
    private void insertPayments(List<Invoice__c> invoices) {

        List<Payments__c> batch = new List<Payments__c>();
        Integer inserted = 0;

        for (Invoice__c inv : invoices) {

            for (Integer i = 0; i < PAYMENTS_PER_INVOICE; i++) {

                batch.add(new Payments__c(Invoice__c = inv.Id));

                if (batch.size() == PAYMENT_CHUNK_SIZE) {
                    insert batch;
                    inserted += batch.size();
                    batch.clear();
                }
            }
        }

        if (!batch.isEmpty()) {
            insert batch;
            inserted += batch.size();
        }

        totalPayments += inserted;

        log('EXECUTE', 'PAYMENTS',
            'Inserted ' + inserted +
            ' | Total: ' + totalPayments);
    }

    // ─────────────────────────────────────────────────────────────
    // LOGGER
    // ─────────────────────────────────────────────────────────────
    private static void log(String stage, String context, String msg) {
        System.debug(LoggingLevel.INFO,
            '[SeedDataBatch][' + stage + '][' + context + '] ' +
            msg + ' | ' + Datetime.now());
    }

    // ─────────────────────────────────────────────────────────────
    // SYNTHETIC ITERABLE
    // ─────────────────────────────────────────────────────────────
    private class SyntheticOrderIterable implements Iterable<SObject>, Iterator<SObject> {

        private Integer total;
        private Integer current = 0;

        public SyntheticOrderIterable(Integer total) {
            this.total = total;
        }

        public Iterator<SObject> iterator() {
            return this;
        }

        public Boolean hasNext() {
            return current < total;
        }

        public SObject next() {
            current++;
            return new Order__c();
        }
    }
}