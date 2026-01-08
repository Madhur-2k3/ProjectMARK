global class BookingCompletedSeedBatch
    implements Database.Batchable<Integer> {

    global Integer totalRecords;

    global BookingCompletedSeedBatch(Integer totalRecords) {
        this.totalRecords = totalRecords;
    }

    // 1️⃣ START
    global Iterable<Integer> start(Database.BatchableContext bc) {
        List<Integer> indexes = new List<Integer>();
        for (Integer i = 1; i <= totalRecords; i++) {
            indexes.add(i);
        }
        return indexes;
    }

    // 2️⃣ EXECUTE
    global void execute(Database.BatchableContext bc, List<Integer> scope) {

        List<Booking__c> bookings = new List<Booking__c>();

        for (Integer i : scope) {

            Booking__c booking = new Booking__c(
                Customer_Name__c = getRealCustomerName(i),
                Booking_Date__c = Date.today().addYears(-3),
                Service_Type__c = getServiceType(i),
                Status__c = 'Completed',
                Amount__c = 2000 + i
            );

            bookings.add(booking);
        }

        insert bookings;
    }

    // 3️⃣ FINISH
    global void finish(Database.BatchableContext bc) {
        System.debug('Inserted ' + totalRecords + ' completed booking records.');
    }

    // 🔹 Realistic customer names
    private static String getRealCustomerName(Integer i) {

        List<String> firstNames = new List<String>{
            'Amit','Rahul','Sneha','Priya','Anjali',
            'Rohit','Kiran','Vikram','Neha','Arjun'
        };

        List<String> lastNames = new List<String>{
            'Sharma','Verma','Reddy','Patel','Gupta',
            'Mehta','Iyer','Kumar','Singh','Das'
        };

        return firstNames[Math.mod(i, firstNames.size())] + ' ' +
               lastNames[Math.mod(i, lastNames.size())];
    }

    // 🔹 Service Type: ONLY Hotel, Flight, Bus, Show
    private static String getServiceType(Integer i) {
        List<String> services = new List<String>{
            'Hotel','Flight','Bus','Show'
        };
        return services[Math.mod(i, services.size())];
    }
}