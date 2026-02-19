public with sharing class DataArchiveScheduleController {

    // ─────────────────────────────────────────────────
    //  Wrapper for returning schedule info to LWC
    // ─────────────────────────────────────────────────
    public class ScheduleInfo {
        @AuraEnabled public String id              { get; set; }
        @AuraEnabled public String objectName      { get; set; }
        @AuraEnabled public String frequency       { get; set; }
        @AuraEnabled public String dateField       { get; set; }
        @AuraEnabled public Decimal days           { get; set; }
        @AuraEnabled public String status          { get; set; }
        @AuraEnabled public String cronExpression  { get; set; }
        @AuraEnabled public Datetime createdDate   { get; set; }
        @AuraEnabled public String preferredTime   { get; set; }
        @AuraEnabled public String dayOfWeek       { get; set; }
    }

    // ─────────────────────────────────────────────────
    //  Get ALL active schedules (for View Scheduled Objects)
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static List<ScheduleInfo> getActiveSchedules() {

        List<ScheduleInfo> result = new List<ScheduleInfo>();

        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c
            FROM Data_Archive_Schedule__c
            WHERE Status__c = 'Active'
            ORDER BY CreatedDate DESC
        ];

        // Cross-check Job IDs against CronTrigger
        Set<Id> jobIds = new Set<Id>();
        for (Data_Archive_Schedule__c s : schedules) {
            if (s.Job_Id__c != null) {
                jobIds.add(s.Job_Id__c);
            }
        }

        Set<Id> validJobIds = new Set<Id>();
        if (!jobIds.isEmpty()) {
            for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE Id IN :jobIds]) {
                validJobIds.add(ct.Id);
            }
        }

        // Auto-deactivate orphaned schedules
        List<Data_Archive_Schedule__c> toDeactivate = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c s : schedules) {
            if (s.Job_Id__c == null || !validJobIds.contains(s.Job_Id__c)) {
                toDeactivate.add(new Data_Archive_Schedule__c(
                    Id = s.Id, Status__c = 'Inactive'
                ));
                continue;
            }

            ScheduleInfo info   = new ScheduleInfo();
            info.id             = s.Id;
            info.objectName     = s.Object_Name__c;
            info.frequency      = s.Frequency__c;
            info.dateField      = s.Date_Field__c;
            info.days           = s.Days__c;
            info.status         = s.Status__c;
            info.cronExpression = s.Cron_Expression__c;
            info.createdDate    = s.CreatedDate;
            info.preferredTime  = s.Preferred_Time__c;
            info.dayOfWeek      = s.Day_Of_Week__c;
            result.add(info);
        }

        if (!toDeactivate.isEmpty()) {
            update toDeactivate;
        }

        return result;
    }

    // ─────────────────────────────────────────────────
    //  Get active schedules for a SPECIFIC object
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static List<ScheduleInfo> getSchedulesForObject(String objectName) {

        List<ScheduleInfo> result = new List<ScheduleInfo>();

        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = :objectName
            AND Status__c = 'Active'
            ORDER BY CreatedDate DESC
        ];

        // Cross-check Job IDs against CronTrigger
        Set<Id> jobIds = new Set<Id>();
        for (Data_Archive_Schedule__c s : schedules) {
            if (s.Job_Id__c != null) {
                jobIds.add(s.Job_Id__c);
            }
        }

        Set<Id> validJobIds = new Set<Id>();
        if (!jobIds.isEmpty()) {
            for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE Id IN :jobIds]) {
                validJobIds.add(ct.Id);
            }
        }

        // Auto-deactivate orphaned schedules
        List<Data_Archive_Schedule__c> toDeactivate = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c s : schedules) {
            if (s.Job_Id__c == null || !validJobIds.contains(s.Job_Id__c)) {
                toDeactivate.add(new Data_Archive_Schedule__c(
                    Id = s.Id, Status__c = 'Inactive'
                ));
                continue;
            }

            ScheduleInfo info   = new ScheduleInfo();
            info.id             = s.Id;
            info.objectName     = s.Object_Name__c;
            info.frequency      = s.Frequency__c;
            info.dateField      = s.Date_Field__c;
            info.days           = s.Days__c;
            info.status         = s.Status__c;
            info.cronExpression = s.Cron_Expression__c;
            info.createdDate    = s.CreatedDate;
            info.preferredTime  = s.Preferred_Time__c;
            info.dayOfWeek      = s.Day_Of_Week__c;
            result.add(info);
        }

        if (!toDeactivate.isEmpty()) {
            update toDeactivate;
        }

        return result;
    }

    // ─────────────────────────────────────────────────
    //  MAIN: Schedule or re-schedule an archive job
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static String scheduleArchive(
        String  objectName,
        String  frequency,
        String  dateField,
        Integer days,
        String  filterValue,
        String  preferredTime,
        String  dayOfWeek
    ){

        // ── Duplicate validation ──────────────────────
        List<Data_Archive_Schedule__c> duplicates =
            [SELECT Id
             FROM Data_Archive_Schedule__c
             WHERE Object_Name__c = :objectName
               AND Date_Field__c  = :dateField
               AND Days__c        = :days
               AND Frequency__c   = :frequency
               AND Status__c      = 'Active'
             LIMIT 1];

        if (!duplicates.isEmpty()) {
            throw new AuraHandledException(
                'A schedule with the same object (' + objectName + '), criteria (' +
                dateField + ', ' + days + ' days), and frequency (' + frequency +
                ') already exists. Please modify the criteria or frequency to create a new schedule.'
            );
        }

        // ── Abort any existing schedule for same object+field ──
        List<Data_Archive_Schedule__c> existing =
            [SELECT Id, Job_Id__c, Frequency__c
             FROM Data_Archive_Schedule__c
             WHERE Object_Name__c = :objectName
               AND Date_Field__c  = :dateField
               AND Status__c      = 'Active'
             LIMIT 1];

        if (!existing.isEmpty()) {
            if (existing[0].Job_Id__c != null) {
                System.abortJob(existing[0].Job_Id__c);
            }
            delete existing[0];
        }

        // ── Build cron & schedule the job ─────────────
        String cronExp = buildCronExpression(frequency, preferredTime, dayOfWeek);

        String jobName =
            'Archive_' + objectName + '_' +
            Datetime.now().getTime();

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

        // ── Save schedule record ──────────────────────
        insert new Data_Archive_Schedule__c(
            Object_Name__c     = objectName,
            Frequency__c       = frequency,
            Date_Field__c      = dateField,
            Days__c            = days,
            Cron_Expression__c = cronExp,
            Job_Id__c          = jobId,
            Status__c          = 'Active',
            Preferred_Time__c  = preferredTime,
            Day_Of_Week__c     = dayOfWeek
        );

        return 'Schedule Created Successfully';
    }


    // ─────────────────────────────────────────────────
    //  Cron builder — now supports custom time & day
    // ─────────────────────────────────────────────────
    private static String buildCronExpression(
        String frequency,
        String preferredTime,
        String dayOfWeek
    ){
        // Parse preferred time (HH:mm) or default to 02:00
        Integer hour   = 2;
        Integer minute = 0;

        if (preferredTime != null && preferredTime.contains(':')) {
            List<String> parts = preferredTime.split(':');
            hour   = Integer.valueOf(parts[0]);
            minute = Integer.valueOf(parts[1]);
        }

        String sec = '0';
        String min = String.valueOf(minute);
        String hr  = String.valueOf(hour);

        if (frequency == 'DAILY') {
            return sec + ' ' + min + ' ' + hr + ' * * ?';
        }
        if (frequency == 'WEEKLY') {
            String day = (dayOfWeek != null && dayOfWeek != '')
                ? dayOfWeek
                : 'MON';
            return sec + ' ' + min + ' ' + hr + ' ? * ' + day;
        }
        if (frequency == 'MONTHLY') {
            return sec + ' ' + min + ' ' + hr + ' 1 * ?';
        }
        if (frequency == 'YEARLY') {
            return sec + ' ' + min + ' ' + hr + ' 1 1 ?';
        }

        // Default — daily at preferred time
        return sec + ' ' + min + ' ' + hr + ' * * ?';
    }

    // ─────────────────────────────────────────────────
    //  Deactivate a schedule (abort job + set Inactive)
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static String deactivateSchedule(Id scheduleId) {
        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Job_Id__c, Status__c
            FROM Data_Archive_Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];

        if (schedules.isEmpty()) {
            throw new AuraHandledException('Schedule record not found.');
        }

        Data_Archive_Schedule__c schedule = schedules[0];

        // Abort the CronTrigger if it still exists
        if (schedule.Job_Id__c != null) {
            try {
                System.abortJob(schedule.Job_Id__c);
            } catch (Exception e) {
                // Job may already have been deleted from Setup — that's fine
            }
        }

        schedule.Status__c = 'Inactive';
        update schedule;
        return 'Schedule deactivated successfully';
    }
}