public class SeedDataBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ── Constants ────────────────────────────────────────────────
    // Ratio 3:2:1 → Payments:Invoices:Orders
    // 70,002 Payments | 46,668 Invoices | 23,334 Orders
    private static final Integer TOTAL_ORDERS         = 2000;
    private static final Integer INVOICES_PER_ORDER   = 2;      // 1 Order   → 2 Invoices
    private static final Integer PAYMENTS_PER_INVOICE = 3;      // 1 Invoice → 3 Payments
    private static final Integer BATCH_SIZE           = 200;
    private static final Integer PAYMENT_CHUNK_SIZE   = 9000;   // safe under 10k DML limit

    // ── Phase ────────────────────────────────────────────────────
    public enum Phase { ORDERS, INVOICES, PAYMENTS }

    // ── Stateful counters (survive across batch chunks) ──────────
    private Phase   currentPhase;
    private Integer totalOrders   = 0;
    private Integer totalInvoices = 0;
    private Integer totalPayments = 0;

    // ── Constructor ──────────────────────────────────────────────
    public SeedDataBatch(Phase phase) {
        this.currentPhase = phase;
    }

    // ─────────────────────────────────────────────────────────────
    // start()
    // ─────────────────────────────────────────────────────────────
    public Iterable<SObject> start(Database.BatchableContext bc) {
        log('START', currentPhase.name(),
            'Batch started | Target → Orders: ' + TOTAL_ORDERS +
            ' | Invoices: ' + (TOTAL_ORDERS * INVOICES_PER_ORDER) +
            ' | Payments: ' + (TOTAL_ORDERS * INVOICES_PER_ORDER * PAYMENTS_PER_INVOICE));

        if (currentPhase == Phase.ORDERS) {
            // No real records to query yet — synthetic iterable
            // drives the batch chunk count for order insertion
            return new SyntheticOrderIterable(TOTAL_ORDERS);
        }
        if (currentPhase == Phase.INVOICES) {
            return Database.getQueryLocator(
                'SELECT Id FROM Order__c ' +
                'ORDER BY CreatedDate DESC ' +
                'LIMIT ' + TOTAL_ORDERS
            );
        }
        // PAYMENTS — iterate all invoices seeded in previous phase
        return Database.getQueryLocator(
            'SELECT Id FROM Invoice__c ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT ' + (TOTAL_ORDERS * INVOICES_PER_ORDER)
        );
    }

    // ─────────────────────────────────────────────────────────────
    // execute()
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
                e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }
    }

    // ─────────────────────────────────────────────────────────────
    // finish() — chains ORDERS → INVOICES → PAYMENTS
    // ─────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {
        log('FINISH', currentPhase.name(),
            'Phase done → Orders: '   + totalOrders   +
            ' | Invoices: '           + totalInvoices +
            ' | Payments: '           + totalPayments);

        if (currentPhase == Phase.ORDERS) {
            Database.executeBatch(new SeedDataBatch(Phase.INVOICES), BATCH_SIZE);

        } else if (currentPhase == Phase.INVOICES) {
            Database.executeBatch(new SeedDataBatch(Phase.PAYMENTS), BATCH_SIZE);

        } else {
            log('FINISH', 'ALL',
                '=== Seed Complete ===' +
                ' | Orders: '   + totalOrders   +
                ' | Invoices: ' + totalInvoices +
                ' | Payments: ' + totalPayments);
        }
    }

    // ─────────────────────────────────────────────────────────────
    // ORDERS
    // ─────────────────────────────────────────────────────────────
    private void insertOrders(Integer count) {
        List<Order__c> records = new List<Order__c>();
        for (Integer i = 0; i < count; i++) {
            records.add(new Order__c());
        }
        insert records;
        totalOrders += records.size();
        log('EXECUTE', 'ORDERS', 'Inserted ' + records.size() +
            ' | Running total: ' + totalOrders);
    }

    // ─────────────────────────────────────────────────────────────
    // INVOICES — 2 per Order
    // chunk of 200 orders → 400 invoices per execute()
    // well within 10k DML row limit
    // ─────────────────────────────────────────────────────────────
    private void insertInvoices(List<Order__c> orderChunk) {
        List<Invoice__c> records = new List<Invoice__c>();
        for (Order__c o : orderChunk) {
            for (Integer j = 0; j < INVOICES_PER_ORDER; j++) {
                records.add(new Invoice__c(Order__c = o.Id));
            }
        }
        insert records;
        totalInvoices += records.size();
        log('EXECUTE', 'INVOICES',
            'Inserted ' + records.size() +
            ' for '     + orderChunk.size() + ' orders' +
            ' | Running total: ' + totalInvoices);
    }

    // ─────────────────────────────────────────────────────────────
    // PAYMENTS — 3 per Invoice
    // chunk of 200 invoices → 600 payments per execute()
    // well within 10k DML row limit
    // sub-chunking at 9,000 kept as safety net
    // ─────────────────────────────────────────────────────────────
    private void insertPayments(List<Invoice__c> invoiceChunk) {
        List<Payments__c> batch = new List<Payments__c>();
        Integer chunkTotal = 0;

        for (Invoice__c inv : invoiceChunk) {
            for (Integer k = 0; k < PAYMENTS_PER_INVOICE; k++) {
                batch.add(new Payments__c(Invoice__c = inv.Id));

                // Safety sub-chunk — keeps every DML under 10k rows
                if (batch.size() == PAYMENT_CHUNK_SIZE) {
                    insert batch;
                    chunkTotal += batch.size();
                    batch.clear();
                }
            }
        }

        // Insert remaining payments
        if (!batch.isEmpty()) {
            insert batch;
            chunkTotal += batch.size();
            batch.clear();
        }

        totalPayments += chunkTotal;
        log('EXECUTE', 'PAYMENTS',
            'Inserted ' + chunkTotal +
            ' for '     + invoiceChunk.size() + ' invoices' +
            ' | Running total: ' + totalPayments);
    }

    // ─────────────────────────────────────────────────────────────
    // LOGGER — inline private method
    // ─────────────────────────────────────────────────────────────
    private static void log(String stage, String context, String message) {
        System.debug(
            LoggingLevel.INFO,
            '[SeedDataBatch] [' + stage + '] [' + context + '] ' +
            message + ' | ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss')
        );
    }

    // ─────────────────────────────────────────────────────────────
    // SYNTHETIC ITERABLE — inner class
    // drives ORDERS phase since no records exist yet to query
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
            if (!hasNext()) throw new NoSuchElementException();
            current++;
            return new Order__c();
        }
    }
}