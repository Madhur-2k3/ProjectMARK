@IsTest
public class DataArchiveScheduleTriggerHandlerTest {
    
    @IsTest
    static void testHandleAfterUpdate_ActivateSchedule() {
        // Create an inactive schedule
        Data_Archive_Schedule__c schedule = new Data_Archive_Schedule__c(
            Name = 'Test Trigger Schedule',
            Object_Name__c = 'Account',
            Frequency__c = 'DAILY',
            Date_Field__c = 'CreatedDate',
            Days__c = 30,
            Status__c = 'In Active',
            Preferred_Time__c = '14:30',
            Selected_Child_Objects__c = 'Contact,Opportunity'
        );
        insert schedule;
        
        // Update to Active
        schedule.Status__c = 'Active';
        
        Test.startTest();
        update schedule;
        Test.stopTest(); // This forces the @future method to execute
        
        // Verify schedule was updated with Job_Id__c and Cron_Expression__c
        Data_Archive_Schedule__c updatedSchedule = [SELECT Job_Id__c, Cron_Expression__c, Status__c FROM Data_Archive_Schedule__c WHERE Id = :schedule.Id];
        System.assertEquals('Active', updatedSchedule.Status__c);
        System.assertNotEquals(null, updatedSchedule.Job_Id__c, 'Job ID should be populated by the future method');
        System.assertNotEquals(null, updatedSchedule.Cron_Expression__c, 'Cron Expression should be populated');
    }
    
    @IsTest
    static void testReactivateSchedules_WithExistingStaleJob() {
        // Create a real scheduled job so we have a valid Job_Id
        Id jobId = System.schedule(
            'TestStaleJob_' + Datetime.now().getTime(),
            '0 0 2 * * ?',
            new DataArchiveScheduler('Account', 'CreatedDate', 30, null, 'StaleJob')
        );
        
        // Create an inactive schedule linked to that Job_Id
        Data_Archive_Schedule__c schedule = new Data_Archive_Schedule__c(
            Name = 'Test Trigger Replace Schedule',
            Object_Name__c = 'Account',
            Frequency__c = 'WEEKLY',
            Day_Of_Week__c = 'WED',
            Date_Field__c = 'CreatedDate',
            Days__c = 15,
            Status__c = 'In Active',
            Preferred_Time__c = '09:00',
            Job_Id__c = jobId
        );
        insert schedule;
        
        // Update to Active to trigger the abortion of the old job and creation of a new one
        schedule.Status__c = 'Active';
        
        Test.startTest();
        update schedule;
        Test.stopTest(); // This forces the @future method to execute
        
        Data_Archive_Schedule__c updatedSchedule = [SELECT Job_Id__c, Cron_Expression__c FROM Data_Archive_Schedule__c WHERE Id = :schedule.Id];
        
        System.assertNotEquals(jobId, updatedSchedule.Job_Id__c, 'A new Job ID should have been generated, replacing the stale one');
        System.assertEquals('0 0 9 ? * WED', updatedSchedule.Cron_Expression__c, 'Cron expression should match WEEKLY WED at 09:00');
    }

    @IsTest
    static void testBuildCronExpression_VariousFrequencies() {
        // We can test Monthly and Yearly indirectly by creating schedules and activating them
        Data_Archive_Schedule__c monthlySchedule = new Data_Archive_Schedule__c(
            Name = 'Monthly', Object_Name__c = 'Account', Frequency__c = 'MONTHLY',
            Date_Field__c = 'CreatedDate', Status__c = 'In Active', Preferred_Time__c = '10:15'
        );
        Data_Archive_Schedule__c yearlySchedule = new Data_Archive_Schedule__c(
            Name = 'Yearly', Object_Name__c = 'Account', Frequency__c = 'YEARLY',
            Date_Field__c = 'CreatedDate', Status__c = 'In Active', Preferred_Time__c = '11:45'
        );
        insert new List<Data_Archive_Schedule__c>{monthlySchedule, yearlySchedule};
        
        monthlySchedule.Status__c = 'Active';
        yearlySchedule.Status__c = 'Active';
        
        Test.startTest();
        update new List<Data_Archive_Schedule__c>{monthlySchedule, yearlySchedule};
        Test.stopTest();
        
        Map<Id, Data_Archive_Schedule__c> results = new Map<Id, Data_Archive_Schedule__c>([
            SELECT Id, Cron_Expression__c FROM Data_Archive_Schedule__c
        ]);
        
        System.assertEquals('0 15 10 1 * ?', results.get(monthlySchedule.Id).Cron_Expression__c);
        System.assertEquals('0 45 11 1 1 ?', results.get(yearlySchedule.Id).Cron_Expression__c);
    }
}