public with sharing class DataArchiveScheduleController {

    // ─────────────────────────────────────────────────
    //  Wrapper for returning schedule info to LWC
    // ─────────────────────────────────────────────────
    public class ScheduleInfo {
        @AuraEnabled public String id              { get; set; }
        @AuraEnabled public String name            { get; set; }
        @AuraEnabled public String recordUrl       { get; set; }
        @AuraEnabled public String objectName      { get; set; }
        @AuraEnabled public String frequency       { get; set; }
        @AuraEnabled public String dateField       { get; set; }
        @AuraEnabled public Decimal days           { get; set; }
        @AuraEnabled public String status          { get; set; }
        @AuraEnabled public String cronExpression  { get; set; }
        @AuraEnabled public Datetime createdDate   { get; set; }
        @AuraEnabled public String preferredTime   { get; set; }
        @AuraEnabled public String dayOfWeek       { get; set; }
        @AuraEnabled public String selectedChildObjects { get; set; }
    }

    // ─────────────────────────────────────────────────
    //  Wrapper for paginated results
    // ─────────────────────────────────────────────────
    public class PaginatedResult {
        @AuraEnabled public List<ScheduleInfo> records { get; set; }
        @AuraEnabled public Integer totalRecords       { get; set; }
    }

    // ─────────────────────────────────────────────────
    //  Helper: clean up orphaned schedules in bulk
    //  If a job was deleted from Setup, mark record Inactive.
    // ─────────────────────────────────────────────────
    private static List<Data_Archive_Schedule__c> cleanOrphanedSchedules(
        List<Data_Archive_Schedule__c> schedules
    ) {
        // Collect all non-null Job Ids
        Set<Id> jobIds = new Set<Id>();
        for (Data_Archive_Schedule__c s : schedules) {
            if (s.Job_Id__c != null) {
                jobIds.add(s.Job_Id__c);
            }
        }

        // Query CronTrigger to find which jobs still exist
        Set<Id> existingJobIds = new Set<Id>();
        if (!jobIds.isEmpty()) {
            for (CronTrigger ct : [
                SELECT Id FROM CronTrigger WHERE Id IN :jobIds
            ]) {
                existingJobIds.add(ct.Id);
            }
        }

        // Separate into still-active vs orphaned
        List<Data_Archive_Schedule__c> active  = new List<Data_Archive_Schedule__c>();
        List<Data_Archive_Schedule__c> orphans = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c s : schedules) {
            if (s.Job_Id__c == null || !existingJobIds.contains(s.Job_Id__c)) {
                s.Status__c = 'In Active';
                orphans.add(s);
            } else {
                active.add(s);
            }
        }

        // Persist the status change for orphaned records
        if (!orphans.isEmpty()) {
            update orphans;
        }

        return active;
    }

    // ─────────────────────────────────────────────────
    //  Get ALL active schedules (for View Scheduled Objects)
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static List<ScheduleInfo> getActiveSchedules() {

        List<ScheduleInfo> result = new List<ScheduleInfo>();

        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Status__c = 'Active'
            ORDER BY CreatedDate DESC
        ];

        // Auto-clean orphaned schedules whose jobs were deleted from Setup
        schedules = cleanOrphanedSchedules(schedules);

        for (Data_Archive_Schedule__c s : schedules) {
            ScheduleInfo info   = new ScheduleInfo();
            info.id             = s.Id;
            info.name           = s.Name;
            info.recordUrl      = '/' + s.Id;
            info.objectName     = s.Object_Name__c;
            info.frequency      = s.Frequency__c;
            info.dateField      = s.Date_Field__c;
            info.days           = s.Days__c;
            info.status         = s.Status__c;
            info.cronExpression = s.Cron_Expression__c;
            info.createdDate    = s.CreatedDate;
            info.preferredTime  = s.Preferred_Time__c;
            info.dayOfWeek      = s.Day_Of_Week__c;
            info.selectedChildObjects = s.Selected_Child_Objects__c;
            result.add(info);
        }

        return result;
    }

    // ─────────────────────────────────────────────────
    //  Get ALL schedules for a SPECIFIC object
    //  Returns Active + Inactive, sorted Active first
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static List<ScheduleInfo> getSchedulesForObject(String objectName) {

        List<ScheduleInfo> result = new List<ScheduleInfo>();

        // Fetch all schedules for this object (Active + Inactive)
        List<Data_Archive_Schedule__c> allSchedules = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = :objectName
            ORDER BY CreatedDate DESC
        ];

        // Separate Active vs Inactive so we only run orphan-cleanup on Active ones
        List<Data_Archive_Schedule__c> activeSchedules   = new List<Data_Archive_Schedule__c>();
        List<Data_Archive_Schedule__c> inactiveSchedules = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c s : allSchedules) {
            if (s.Status__c == 'Active') {
                activeSchedules.add(s);
            } else {
                inactiveSchedules.add(s);
            }
        }

        // Auto-clean orphaned active schedules whose cron jobs were deleted from Setup
        List<Data_Archive_Schedule__c> cleanedActive = cleanOrphanedSchedules(activeSchedules);

        // Build result: Active records first, then Inactive
        List<Data_Archive_Schedule__c> ordered = new List<Data_Archive_Schedule__c>();
        ordered.addAll(cleanedActive);
        ordered.addAll(inactiveSchedules);

        for (Data_Archive_Schedule__c s : ordered) {
            ScheduleInfo info   = new ScheduleInfo();
            info.id             = s.Id;
            info.name           = s.Name;
            info.recordUrl      = '/' + s.Id;
            info.objectName     = s.Object_Name__c;
            info.frequency      = s.Frequency__c;
            info.dateField      = s.Date_Field__c;
            info.days           = s.Days__c;
            info.status         = s.Status__c;
            info.cronExpression = s.Cron_Expression__c;
            info.createdDate    = s.CreatedDate;
            info.preferredTime  = s.Preferred_Time__c;
            info.dayOfWeek      = s.Day_Of_Week__c;
            info.selectedChildObjects = s.Selected_Child_Objects__c;
            result.add(info);
        }

        return result;
    }

    // ─────────────────────────────────────────────────
    //  Get ALL active schedules — PAGINATED (server-side)
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static PaginatedResult getActiveSchedulesPaginated(
        Integer pageSize, Integer pageNumber
    ) {
        Integer safePage = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;
        Integer safeSize = (pageSize != null && pageSize > 0) ? pageSize : 5;
        Integer offset   = (safePage - 1) * safeSize;

        Integer total = [SELECT COUNT()
                         FROM Data_Archive_Schedule__c
                         WHERE Status__c = 'Active'];

        List<Data_Archive_Schedule__c> schedules = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Status__c = 'Active'
            ORDER BY CreatedDate DESC
            LIMIT :safeSize
            OFFSET :offset
        ];

        schedules = cleanOrphanedSchedules(schedules);

        List<ScheduleInfo> records = new List<ScheduleInfo>();
        for (Data_Archive_Schedule__c s : schedules) {
            ScheduleInfo info   = new ScheduleInfo();
            info.id             = s.Id;
            info.name           = s.Name;
            info.recordUrl      = '/' + s.Id;
            info.objectName     = s.Object_Name__c;
            info.frequency      = s.Frequency__c;
            info.dateField      = s.Date_Field__c;
            info.days           = s.Days__c;
            info.status         = s.Status__c;
            info.cronExpression = s.Cron_Expression__c;
            info.createdDate    = s.CreatedDate;
            info.preferredTime  = s.Preferred_Time__c;
            info.dayOfWeek      = s.Day_Of_Week__c;
            info.selectedChildObjects = s.Selected_Child_Objects__c;
            records.add(info);
        }

        PaginatedResult pr = new PaginatedResult();
        pr.records      = records;
        pr.totalRecords = total;
        return pr;
    }

    // ─────────────────────────────────────────────────
    //  Get schedules for a SPECIFIC object — PAGINATED
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static PaginatedResult getSchedulesForObjectPaginated(
        String objectName, Integer pageSize, Integer pageNumber
    ) {
        Integer safePage = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;
        Integer safeSize = (pageSize != null && pageSize > 0) ? pageSize : 5;
        Integer offset   = (safePage - 1) * safeSize;

        Integer total = [SELECT COUNT()
                         FROM Data_Archive_Schedule__c
                         WHERE Object_Name__c = :objectName];

        List<Data_Archive_Schedule__c> allScheds = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = :objectName
            ORDER BY Status__c ASC, CreatedDate DESC
            LIMIT :safeSize
            OFFSET :offset
        ];

        List<Data_Archive_Schedule__c> activeSchedules   = new List<Data_Archive_Schedule__c>();
        List<Data_Archive_Schedule__c> inactiveSchedules = new List<Data_Archive_Schedule__c>();
        for (Data_Archive_Schedule__c s : allScheds) {
            if (s.Status__c == 'Active') {
                activeSchedules.add(s);
            } else {
                inactiveSchedules.add(s);
            }
        }

        List<Data_Archive_Schedule__c> cleanedActive = cleanOrphanedSchedules(activeSchedules);

        List<Data_Archive_Schedule__c> ordered = new List<Data_Archive_Schedule__c>();
        ordered.addAll(cleanedActive);
        ordered.addAll(inactiveSchedules);

        List<ScheduleInfo> records = new List<ScheduleInfo>();
        for (Data_Archive_Schedule__c s : ordered) {
            ScheduleInfo info   = new ScheduleInfo();
            info.id             = s.Id;
            info.name           = s.Name;
            info.recordUrl      = '/' + s.Id;
            info.objectName     = s.Object_Name__c;
            info.frequency      = s.Frequency__c;
            info.dateField      = s.Date_Field__c;
            info.days           = s.Days__c;
            info.status         = s.Status__c;
            info.cronExpression = s.Cron_Expression__c;
            info.createdDate    = s.CreatedDate;
            info.preferredTime  = s.Preferred_Time__c;
            info.dayOfWeek      = s.Day_Of_Week__c;
            info.selectedChildObjects = s.Selected_Child_Objects__c;
            records.add(info);
        }

        PaginatedResult pr = new PaginatedResult();
        pr.records      = records;
        pr.totalRecords = total;
        return pr;
    }

    // ── Backward Compatibility Overload (7 params) ────────
    public static String scheduleArchive(
        String  objectName,
        String  frequency,
        String  dateField,
        Integer days,
        String  filterValue,
        String  preferredTime,
        String  dayOfWeek
    ){
        return scheduleArchive(objectName, frequency, dateField, days, filterValue, preferredTime, dayOfWeek, 'Schedule_' + Datetime.now().getTime(), null);
    }

    // ── Backward Compatibility Overload (8 params) ────────
    public static String scheduleArchive(
        String  objectName,
        String  frequency,
        String  dateField,
        Integer days,
        String  filterValue,
        String  preferredTime,
        String  dayOfWeek,
        String  scheduleName
    ){
        return scheduleArchive(objectName, frequency, dateField, days, filterValue, preferredTime, dayOfWeek, scheduleName, null);
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
        String  dayOfWeek,
        String  scheduleName,
        List<String> selectedChildObjects
    ){

        // ── Clean up orphaned schedules first ────────
        // If a job was deleted from Setup, the record still says 'Active'.
        // Remove it before the duplicate check so re-creating works.
        List<Data_Archive_Schedule__c> existing =
            [SELECT Id, Job_Id__c, Frequency__c
             FROM Data_Archive_Schedule__c
             WHERE Object_Name__c = :objectName
               AND Date_Field__c  = :dateField
               AND Status__c      = 'Active'
             LIMIT 1];

        if (!existing.isEmpty()) {
            Boolean jobStillExists = false;
            if (existing[0].Job_Id__c != null) {
                List<CronTrigger> ct = [
                    SELECT Id FROM CronTrigger
                    WHERE Id = :existing[0].Job_Id__c
                    LIMIT 1
                ];
                jobStillExists = !ct.isEmpty();
            }

            if (!jobStillExists) {
                // Job was deleted from Setup — clean up the stale record
                delete existing[0];
                existing.clear();
            }
        }

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

        // ── Abort any remaining active schedule for same object+field ──
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

        

        // ── Build child objects CSV for storage ──────────
        String childObjectsCsv = (selectedChildObjects != null && !selectedChildObjects.isEmpty())
            ? String.join(selectedChildObjects, ',')
            : null;

        // ── Save schedule record (without Job_Id; set after scheduling) ──
        Data_Archive_Schedule__c newSchedule = new Data_Archive_Schedule__c(
            Name               = scheduleName,
            Object_Name__c     = objectName,
            Frequency__c       = frequency,
            Date_Field__c      = dateField,
            Days__c            = days,
            Cron_Expression__c = cronExp,
            Status__c          = 'Active',
            Preferred_Time__c  = preferredTime,
            Day_Of_Week__c     = dayOfWeek,
            Selected_Child_Objects__c = childObjectsCsv
        );
        insert newSchedule;

        // ── Schedule the job (after insert so we can use newSchedule.Name) ──
        Id jobId = System.schedule(
            jobName,
            cronExp,
            new DataArchiveScheduler(
                objectName,
                dateField,
                days,
                filterValue,
                newSchedule.Name,
                selectedChildObjects
            )
        );

        // ── Update the schedule record with the Job Id ──
        newSchedule.Job_Id__c = jobId;
        update newSchedule;
        return newSchedule.Id;
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
    //  Update schedule status (inline edit from LWC)
    // ─────────────────────────────────────────────────
    @AuraEnabled
    public static void updateScheduleStatus(Id scheduleId, String status) {
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

        // If changing to Inactive, abort the cron job
        if (status == 'In Active' && schedule.Job_Id__c != null) {
            try {
                System.abortJob(schedule.Job_Id__c);
            } catch (Exception e) {
                // Job may already have been deleted
            }
        }

        schedule.Status__c = status;
        update schedule;
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

        schedule.Status__c = 'In Active';
        update schedule;
        return 'Schedule deactivated successfully';
    }
}