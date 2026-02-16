public with sharing class DataArchiveScheduleController {

    @AuraEnabled
    public static String scheduleArchive(
        String objectName,
        String frequency,
        String dateField,
        Integer days,
        String filterValue
    ){

        // ----------------------------
        // Check existing active schedule
        // ----------------------------
        List<Data_Archive_Schedule__c> existing =
            [SELECT Id, Job_Id__c, Frequency__c
             FROM Data_Archive_Schedule__c
             WHERE Object_Name__c = :objectName
             AND Date_Field__c = :dateField
             AND Status__c = 'Active'
             LIMIT 1];

        if(!existing.isEmpty()){

            // Abort old scheduled job
            if(existing[0].Job_Id__c != null){
                System.abortJob(existing[0].Job_Id__c);
            }

            delete existing[0];
        }

        // ----------------------------
        // Build cron & schedule the job
        // ----------------------------
        String cronExp = buildCronExpression(frequency);

        String jobName =
            'Archive_' + objectName + '_' +
            Datetime.now().getTime();

        // Pass criteria so the scheduler can build
        // the correct WHERE clause at execution time
        Id jobId = System.schedule(
            jobName,
            cronExp,
            new DataArchiveScheduler(
                objectName,
                dateField,
                days,
                filterValue
            )
        );

        // ----------------------------
        // Save schedule record
        // ----------------------------
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = objectName,
            Frequency__c       = frequency,
            Date_Field__c      = dateField,
            Days__c            = days,
            Cron_Expression__c = cronExp,
            Job_Id__c          = jobId,
            Status__c          = 'Active'
        );

        return 'Schedule Created Successfully';
    }


    private static String buildCronExpression(String frequency){

        if(frequency == 'DAILY'){
            return '0 39 16 * * ?';
        }
        if(frequency == 'WEEKLY_ONCE'){
            return '0 0 2 ? * MON';
        }
        if(frequency == 'WEEKLY'){
            return '0 0 2 ? * FRI';
        }
        if(frequency == 'MONTHLY'){
            return '0 0 2 1 * ?';
        }
        if(frequency == 'YEARLY'){
            return '0 0 2 1 1 ?';
        }

        return '0 0 2 * * ?';
    }
}