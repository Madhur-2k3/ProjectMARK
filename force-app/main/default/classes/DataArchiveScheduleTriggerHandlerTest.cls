/**
 * @description Tests for DataArchiveScheduleTriggerHandler.
 */
@IsTest
public class DataArchiveScheduleTriggerHandlerTest {

    @IsTest
    static void testHandleAfterUpdate_ActivateSchedule() {

        Data_Archive_Schedule__c myScheduleRecord = new Data_Archive_Schedule__c(
            Name = 'Test Trigger Schedule',
            Object_Name__c = 'Account',
            Frequency__c = 'DAILY',
            Date_Field__c = 'CreatedDate',
            Days__c = 30,
            Status__c = 'In Active',
            Preferred_Time__c = '14:30',
            Selected_Child_Objects__c = 'Contact,Opportunity'
        );
        insert myScheduleRecord;

        myScheduleRecord.Status__c = 'Active';

        Test.startTest();
        update myScheduleRecord;
        Test.stopTest();

        Data_Archive_Schedule__c myUpdatedSchedule = [SELECT Job_Id__c, Cron_Expression__c, Status__c FROM Data_Archive_Schedule__c WHERE Id = :myScheduleRecord.Id];
        System.assertEquals('Active', myUpdatedSchedule.Status__c);
        System.assertNotEquals(null, myUpdatedSchedule.Job_Id__c, 'Job ID should be populated by the future method');
        System.assertNotEquals(null, myUpdatedSchedule.Cron_Expression__c, 'Cron Expression should be populated');
    }

    @IsTest
    static void testReactivateSchedules_WithExistingStaleJob() {

        Id myJobId = System.schedule(
            'TestStaleJob_' + Datetime.now().getTime(),
            '0 0 2 * * ?',
            new DataArchiveScheduler('Account', 'CreatedDate', 30, null, 'StaleJob')
        );

        Data_Archive_Schedule__c myScheduleRecord = new Data_Archive_Schedule__c(
            Name = 'Test Trigger Replace Schedule',
            Object_Name__c = 'Account',
            Frequency__c = 'WEEKLY',
            Day_Of_Week__c = 'WED',
            Date_Field__c = 'CreatedDate',
            Days__c = 15,
            Status__c = 'In Active',
            Preferred_Time__c = '09:00',
            Job_Id__c = myJobId
        );
        insert myScheduleRecord;

        myScheduleRecord.Status__c = 'Active';

        Test.startTest();
        update myScheduleRecord;
        Test.stopTest();

        Data_Archive_Schedule__c myUpdatedSchedule = [SELECT Job_Id__c, Cron_Expression__c FROM Data_Archive_Schedule__c WHERE Id = :myScheduleRecord.Id];

        System.assertNotEquals(myJobId, myUpdatedSchedule.Job_Id__c, 'A new Job ID should have been generated, replacing the stale one');
        System.assertEquals('0 0 9 ? * WED', myUpdatedSchedule.Cron_Expression__c, 'Cron expression should match WEEKLY WED at 09:00');
    }

    @IsTest
    static void testBuildCronExpression_VariousFrequencies() {

        Data_Archive_Schedule__c myMonthlySchedule = new Data_Archive_Schedule__c(
            Name = 'Monthly', Object_Name__c = 'Account', Frequency__c = 'MONTHLY',
            Date_Field__c = 'CreatedDate', Status__c = 'In Active', Preferred_Time__c = '10:15'
        );
        Data_Archive_Schedule__c myYearlySchedule = new Data_Archive_Schedule__c(
            Name = 'Yearly', Object_Name__c = 'Account', Frequency__c = 'YEARLY',
            Date_Field__c = 'CreatedDate', Status__c = 'In Active', Preferred_Time__c = '11:45'
        );
        insert new List<Data_Archive_Schedule__c>{myMonthlySchedule, myYearlySchedule};

        myMonthlySchedule.Status__c = 'Active';
        myYearlySchedule.Status__c = 'Active';

        Test.startTest();
        update new List<Data_Archive_Schedule__c>{myMonthlySchedule, myYearlySchedule};
        Test.stopTest();

        Map<Id, Data_Archive_Schedule__c> myResultsMap = new Map<Id, Data_Archive_Schedule__c>([
            SELECT Id, Cron_Expression__c FROM Data_Archive_Schedule__c
        ]);

        System.assertEquals('0 15 10 1 * ?', myResultsMap.get(myMonthlySchedule.Id).Cron_Expression__c);
        System.assertEquals('0 45 11 1 1 ?', myResultsMap.get(myYearlySchedule.Id).Cron_Expression__c);
    }
}