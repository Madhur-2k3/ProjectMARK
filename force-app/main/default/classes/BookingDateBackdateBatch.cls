global class BookingDateBackdateBatch
    implements Database.Batchable<SObject> {

    // 1️⃣ START
    global Database.QueryLocator start(Database.BatchableContext bc) {

        return Database.getQueryLocator([
            SELECT Id, Booking_Date__c
            FROM Booking__c
            WHERE Status__c = 'Completed'
        ]);
    }

    // 2️⃣ EXECUTE
    global void execute(Database.BatchableContext bc, List<Booking__c> scope) {

        Date backdatedDate = Date.today().addYears(-3);

        for (Booking__c booking : scope) {
            booking.Booking_Date__c = backdatedDate;
        }

        update scope;
    }

    // 3️⃣ FINISH
    global void finish(Database.BatchableContext bc) {
        System.debug('Booking Date updated to 3 years ago for completed bookings.');
    }
}