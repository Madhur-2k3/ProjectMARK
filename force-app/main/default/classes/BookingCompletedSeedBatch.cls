global class BookingCompletedSeedBatch implements Database.Batchable<Integer> {

    global Integer totalRecords;

    global BookingCompletedSeedBatch(Integer totalRecords){
        this.totalRecords = totalRecords;
    }

    // START
    global Iterable<Integer> start(Database.BatchableContext bc){
        List<Integer> indexes = new List<Integer>();
        for(Integer i=1;i<=totalRecords;i++){
            indexes.add(i);
        }
        return indexes;
    }

    // EXECUTE
    global void execute(Database.BatchableContext bc, List<Integer> scope){

        /* ---------------------------
           1️⃣ Insert Booking
        ----------------------------*/

        List<Booking__c> bookings = new List<Booking__c>();

        for(Integer i : scope){

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

        /* ---------------------------
           2️⃣ Insert Booking Orders
        ----------------------------*/

        List<Booking_Order__c> orders = new List<Booking_Order__c>();

        for(Booking__c b : bookings){

            orders.add(new Booking_Order__c(
                Booking__c = b.Id
            ));
        }

        insert orders;

        /* ---------------------------
           3️⃣ Insert Line Items
        ----------------------------*/

        List<Booking_Order_Line_Item__c> lineItems = new List<Booking_Order_Line_Item__c>();

        for(Booking_Order__c o : orders){

            lineItems.add(new Booking_Order_Line_Item__c(
                Booking_Order__c = o.Id
            ));
        }

        insert lineItems;

        /* ---------------------------
           4️⃣ Insert Booking History
        ----------------------------*/

        List<Booking_History__c> histories = new List<Booking_History__c>();

        for(Booking_Order__c o : orders){

            histories.add(new Booking_History__c(
                Booking_Order__c = o.Id
            ));
        }

        insert histories;

        /* ---------------------------
           5️⃣ Insert Booking Payments
        ----------------------------*/

        List<Booking_Payment__c> payments = new List<Booking_Payment__c>();

        for(Booking_Order_Line_Item__c li : lineItems){

            payments.add(new Booking_Payment__c(
                Booking_Order_Line_Item__c = li.Id
            ));
        }

        insert payments;
    }

    // FINISH
    global void finish(Database.BatchableContext bc){
        System.debug('Seeded ' + totalRecords + ' Booking hierarchy records.');
    }

    // Customer Name Generator
    private static String getRealCustomerName(Integer i){

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

    // Service Type
    private static String getServiceType(Integer i){
        List<String> services = new List<String>{
            'Hotel','Flight','Bus','Show'
        };
        return services[Math.mod(i, services.size())];
    }
}