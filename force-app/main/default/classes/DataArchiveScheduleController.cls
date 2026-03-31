/**
 * @description Controller for managing Data Archive Schedule records.
 *              Provides CRUD operations, pagination, orphan cleanup, and the
 *              main scheduleArchive method for creating and scheduling archive jobs.
 */
public with sharing class DataArchiveScheduleController {

    /**
     * @description Wrapper for returning schedule info to LWC components.
     */
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

    /**
     * @description Wrapper for paginated results including total count.
     */
    public class PaginatedResult {

        @AuraEnabled public List<ScheduleInfo> records { get; set; }
        @AuraEnabled public Integer totalRecords       { get; set; }
    }

    /**
     * @description Cleans up orphaned schedules whose CronTrigger jobs no longer exist.
     * @param schedulesList List of schedule records to check.
     * @return A filtered list of schedules whose jobs still exist.
     */
    private static List<Data_Archive_Schedule__c> cleanOrphanedSchedules(
        List<Data_Archive_Schedule__c> schedulesList
    ) {

        Set<Id> jobIdSet = new Set<Id>();

        for (Data_Archive_Schedule__c currentSchedule : schedulesList) {
            if (currentSchedule.Job_Id__c != null) {
                jobIdSet.add(currentSchedule.Job_Id__c);
            }
        }

        Set<Id> existingJobIdSet = new Set<Id>();

        if (!jobIdSet.isEmpty()) {
            for (CronTrigger cronTrigger : [
                SELECT Id FROM CronTrigger WHERE Id IN :jobIdSet
            ]) {
                existingJobIdSet.add(cronTrigger.Id);
            }
        }

        List<Data_Archive_Schedule__c> activeList  = new List<Data_Archive_Schedule__c>();
        List<Data_Archive_Schedule__c> orphansList = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c currentSchedule : schedulesList) {

            if (currentSchedule.Job_Id__c == null || !existingJobIdSet.contains(currentSchedule.Job_Id__c)) {
                currentSchedule.Status__c = 'In Active';
                orphansList.add(currentSchedule);
            } else {
                activeList.add(currentSchedule);
            }
        }

        if (!orphansList.isEmpty()) {
            update orphansList;
        }

        return activeList;
    }

    /**
     * @description Populates a ScheduleInfo wrapper from a Data_Archive_Schedule__c record.
     * @param scheduleRecord The schedule record to convert.
     * @return A populated ScheduleInfo wrapper.
     */
    private static ScheduleInfo buildScheduleInfo(Data_Archive_Schedule__c scheduleRecord) {

        ScheduleInfo info   = new ScheduleInfo();
        info.id             = scheduleRecord.Id;
        info.name           = scheduleRecord.Name;
        info.recordUrl      = '/' + scheduleRecord.Id;
        info.objectName     = scheduleRecord.Object_Name__c;
        info.frequency      = scheduleRecord.Frequency__c;
        info.dateField      = scheduleRecord.Date_Field__c;
        info.days           = scheduleRecord.Days__c;
        info.status         = scheduleRecord.Status__c;
        info.cronExpression = scheduleRecord.Cron_Expression__c;
        info.createdDate    = scheduleRecord.CreatedDate;
        info.preferredTime  = scheduleRecord.Preferred_Time__c;
        info.dayOfWeek      = scheduleRecord.Day_Of_Week__c;
        info.selectedChildObjects = scheduleRecord.Selected_Child_Objects__c;
        return info;
    }

    /**
     * @description Gets all active archive schedules, auto-cleaning orphaned ones.
     * @return A list of ScheduleInfo wrappers for active schedules.
     */
    @AuraEnabled
    public static List<ScheduleInfo> getActiveSchedules() {

        List<ScheduleInfo> resultList = new List<ScheduleInfo>();

        List<Data_Archive_Schedule__c> schedulesList = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Status__c = 'Active'
            ORDER BY CreatedDate DESC
        ];

        schedulesList = cleanOrphanedSchedules(schedulesList);

        for (Data_Archive_Schedule__c currentSchedule : schedulesList) {
            resultList.add(buildScheduleInfo(currentSchedule));
        }

        return resultList;
    }

    /**
     * @description Gets all schedules for a specific object (Active + Inactive).
     * @param objectNameStr The API name of the SObject to filter by.
     * @return A list of ScheduleInfo wrappers, Active first.
     */
    @AuraEnabled
    public static List<ScheduleInfo> getSchedulesForObject(String objectNameStr) {

        List<ScheduleInfo> resultList = new List<ScheduleInfo>();

        List<Data_Archive_Schedule__c> allSchedulesList = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = :objectNameStr
            ORDER BY CreatedDate DESC
        ];

        List<Data_Archive_Schedule__c> activeSchedulesList   = new List<Data_Archive_Schedule__c>();
        List<Data_Archive_Schedule__c> inactiveSchedulesList = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c currentSchedule : allSchedulesList) {

            if (currentSchedule.Status__c == 'Active') {
                activeSchedulesList.add(currentSchedule);
            } else {
                inactiveSchedulesList.add(currentSchedule);
            }
        }

        List<Data_Archive_Schedule__c> cleanedActiveList = cleanOrphanedSchedules(activeSchedulesList);

        List<Data_Archive_Schedule__c> orderedList = new List<Data_Archive_Schedule__c>();
        orderedList.addAll(cleanedActiveList);
        orderedList.addAll(inactiveSchedulesList);

        for (Data_Archive_Schedule__c currentSchedule : orderedList) {
            resultList.add(buildScheduleInfo(currentSchedule));
        }

        return resultList;
    }

    /**
     * @description Gets all active schedules with server-side pagination.
     * @param pageSizeInt Number of records per page.
     * @param pageNumberInt Current page number (1-based).
     * @return A PaginatedResult containing records and total count.
     */
    @AuraEnabled
    public static PaginatedResult getActiveSchedulesPaginated(
        Integer pageSizeInt, Integer pageNumberInt
    ) {

        Integer safePageInt = (pageNumberInt != null && pageNumberInt > 0) ? pageNumberInt : 1;
        Integer safeSizeInt = (pageSizeInt != null && pageSizeInt > 0) ? pageSizeInt : 5;
        Integer offsetInt   = (safePageInt - 1) * safeSizeInt;

        Integer totalInt = [SELECT COUNT()
                         FROM Data_Archive_Schedule__c
                         WHERE Status__c = 'Active'];

        List<Data_Archive_Schedule__c> schedulesList = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Status__c = 'Active'
            ORDER BY CreatedDate DESC
            LIMIT :safeSizeInt
            OFFSET :offsetInt
        ];

        schedulesList = cleanOrphanedSchedules(schedulesList);

        List<ScheduleInfo> recordsList = new List<ScheduleInfo>();

        for (Data_Archive_Schedule__c currentSchedule : schedulesList) {
            recordsList.add(buildScheduleInfo(currentSchedule));
        }

        PaginatedResult paginatedResult = new PaginatedResult();
        paginatedResult.records      = recordsList;
        paginatedResult.totalRecords = totalInt;
        return paginatedResult;
    }

    /**
     * @description Gets schedules for a specific object with server-side pagination.
     * @param objectNameStr The API name of the SObject to filter by.
     * @param pageSizeInt Number of records per page.
     * @param pageNumberInt Current page number (1-based).
     * @return A PaginatedResult containing records and total count.
     */
    @AuraEnabled
    public static PaginatedResult getSchedulesForObjectPaginated(
        String objectNameStr, Integer pageSizeInt, Integer pageNumberInt
    ) {

        Integer safePageInt = (pageNumberInt != null && pageNumberInt > 0) ? pageNumberInt : 1;
        Integer safeSizeInt = (pageSizeInt != null && pageSizeInt > 0) ? pageSizeInt : 5;
        Integer offsetInt   = (safePageInt - 1) * safeSizeInt;

        Integer totalInt = [SELECT COUNT()
                         FROM Data_Archive_Schedule__c
                         WHERE Object_Name__c = :objectNameStr];

        List<Data_Archive_Schedule__c> allSchedsList = [
            SELECT Id, Name, Object_Name__c, Frequency__c, Date_Field__c,
                   Days__c, Status__c, Cron_Expression__c, CreatedDate,
                   Preferred_Time__c, Day_Of_Week__c, Job_Id__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Object_Name__c = :objectNameStr
            ORDER BY Status__c ASC, CreatedDate DESC
            LIMIT :safeSizeInt
            OFFSET :offsetInt
        ];

        List<Data_Archive_Schedule__c> activeSchedulesList   = new List<Data_Archive_Schedule__c>();
        List<Data_Archive_Schedule__c> inactiveSchedulesList = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c currentSchedule : allSchedsList) {

            if (currentSchedule.Status__c == 'Active') {
                activeSchedulesList.add(currentSchedule);
            } else {
                inactiveSchedulesList.add(currentSchedule);
            }
        }

        List<Data_Archive_Schedule__c> cleanedActiveList = cleanOrphanedSchedules(activeSchedulesList);

        List<Data_Archive_Schedule__c> orderedList = new List<Data_Archive_Schedule__c>();
        orderedList.addAll(cleanedActiveList);
        orderedList.addAll(inactiveSchedulesList);

        List<ScheduleInfo> recordsList = new List<ScheduleInfo>();

        for (Data_Archive_Schedule__c currentSchedule : orderedList) {
            recordsList.add(buildScheduleInfo(currentSchedule));
        }

        PaginatedResult paginatedResult = new PaginatedResult();
        paginatedResult.records      = recordsList;
        paginatedResult.totalRecords = totalInt;
        return paginatedResult;
    }

    /**
     * @description Backward-compatible overload (7 params).
     * @param objectNameStr The SObject API name.
     * @param frequencyStr The schedule frequency.
     * @param dateFieldStr The criteria field.
     * @param daysInt Number of days.
     * @param filterValueStr Custom WHERE clause.
     * @param preferredTimeStr Preferred execution time.
     * @param dayOfWeekStr Day of week for WEEKLY schedules.
     * @return The ID of the created schedule record.
     */
    public static String scheduleArchive(
        String  objectNameStr,
        String  frequencyStr,
        String  dateFieldStr,
        Integer daysInt,
        String  filterValueStr,
        String  preferredTimeStr,
        String  dayOfWeekStr
    ) {

        return scheduleArchive(objectNameStr, frequencyStr, dateFieldStr, daysInt,
            filterValueStr, preferredTimeStr, dayOfWeekStr,
            'Schedule_' + Datetime.now().getTime(), null);
    }

    /**
     * @description Backward-compatible overload (8 params).
     * @param objectNameStr The SObject API name.
     * @param frequencyStr The schedule frequency.
     * @param dateFieldStr The criteria field.
     * @param daysInt Number of days.
     * @param filterValueStr Custom WHERE clause.
     * @param preferredTimeStr Preferred execution time.
     * @param dayOfWeekStr Day of week.
     * @param scheduleNameStr Custom schedule name.
     * @return The ID of the created schedule record.
     */
    public static String scheduleArchive(
        String  objectNameStr,
        String  frequencyStr,
        String  dateFieldStr,
        Integer daysInt,
        String  filterValueStr,
        String  preferredTimeStr,
        String  dayOfWeekStr,
        String  scheduleNameStr
    ) {

        return scheduleArchive(objectNameStr, frequencyStr, dateFieldStr, daysInt,
            filterValueStr, preferredTimeStr, dayOfWeekStr, scheduleNameStr, null);
    }

    /**
     * @description Main method: schedules or re-schedules an archive job.
     * @param objectNameStr The SObject API name to archive.
     * @param frequencyStr Schedule frequency (DAILY, WEEKLY, MONTHLY, YEARLY).
     * @param dateFieldStr The criteria field for date-based filtering.
     * @param daysInt Number of days for the date filter.
     * @param filterValueStr Custom WHERE clause filter value.
     * @param preferredTimeStr Preferred execution time (HH:mm format).
     * @param dayOfWeekStr Day of week for WEEKLY schedules.
     * @param scheduleNameStr Name for the schedule record.
     * @param selectedChildObjectsList List of child object API names to include.
     * @return The ID of the created schedule record.
     */
    @AuraEnabled
    public static String scheduleArchive(
        String  objectNameStr,
        String  frequencyStr,
        String  dateFieldStr,
        Integer daysInt,
        String  filterValueStr,
        String  preferredTimeStr,
        String  dayOfWeekStr,
        String  scheduleNameStr,
        List<String> selectedChildObjectsList
    ) {

        List<Data_Archive_Schedule__c> existingList =
            [SELECT Id, Job_Id__c, Frequency__c
             FROM Data_Archive_Schedule__c
             WHERE Object_Name__c = :objectNameStr
               AND Date_Field__c  = :dateFieldStr
               AND Status__c      = 'Active'
             LIMIT 1];

        if (!existingList.isEmpty()) {

            Boolean jobStillExistsFlag = false;

            if (existingList[0].Job_Id__c != null) {
                List<CronTrigger> cronTriggerList = [
                    SELECT Id FROM CronTrigger
                    WHERE Id = :existingList[0].Job_Id__c
                    LIMIT 1
                ];
                jobStillExistsFlag = !cronTriggerList.isEmpty();
            }

            if (!jobStillExistsFlag) {
                delete existingList[0];
                existingList.clear();
            }
        }

        List<Data_Archive_Schedule__c> duplicatesList =
            [SELECT Id
             FROM Data_Archive_Schedule__c
             WHERE Object_Name__c = :objectNameStr
               AND Date_Field__c  = :dateFieldStr
               AND Days__c        = :daysInt
               AND Frequency__c   = :frequencyStr
               AND Status__c      = 'Active'
             LIMIT 1];

        if (!duplicatesList.isEmpty()) {
            throw new AuraHandledException(
                'A schedule with the same object (' + objectNameStr + '), criteria (' +
                dateFieldStr + ', ' + daysInt + ' days), and frequency (' + frequencyStr +
                ') already exists. Please modify the criteria or frequency to create a new schedule.'
            );
        }

        if (!existingList.isEmpty()) {
            if (existingList[0].Job_Id__c != null) {
                System.abortJob(existingList[0].Job_Id__c);
            }
            delete existingList[0];
        }

        String cronExpStr = buildCronExpression(frequencyStr, preferredTimeStr, dayOfWeekStr);

        String jobNameStr =
            'Archive_' + objectNameStr + '_' +
            Datetime.now().getTime();

        String childObjectsCsvStr = (selectedChildObjectsList != null && !selectedChildObjectsList.isEmpty())
            ? String.join(selectedChildObjectsList, ',')
            : null;

        Data_Archive_Schedule__c newSchedule = new Data_Archive_Schedule__c(
            Name               = scheduleNameStr,
            Object_Name__c     = objectNameStr,
            Frequency__c       = frequencyStr,
            Date_Field__c      = dateFieldStr,
            Days__c            = daysInt,
            Cron_Expression__c = cronExpStr,
            Status__c          = 'Active',
            Preferred_Time__c  = preferredTimeStr,
            Day_Of_Week__c     = dayOfWeekStr,
            Selected_Child_Objects__c = childObjectsCsvStr
        );
        insert newSchedule;

        Id jobId = System.schedule(
            jobNameStr,
            cronExpStr,
            new DataArchiveScheduler(
                objectNameStr,
                dateFieldStr,
                daysInt,
                filterValueStr,
                newSchedule.Name,
                selectedChildObjectsList
            )
        );

        newSchedule.Job_Id__c = jobId;
        update newSchedule;
        return newSchedule.Id;
    }

    /**
     * @description Builds a cron expression from frequency, time, and day parameters.
     * @param frequencyStr The schedule frequency (DAILY, WEEKLY, MONTHLY, YEARLY).
     * @param preferredTimeStr Preferred execution time in HH:mm format.
     * @param dayOfWeekStr Day of week for WEEKLY schedules.
     * @return A valid Salesforce cron expression string.
     */
    private static String buildCronExpression(
        String frequencyStr,
        String preferredTimeStr,
        String dayOfWeekStr
    ) {

        Integer hourInt   = 2;
        Integer minuteInt = 0;

        if (preferredTimeStr != null && preferredTimeStr.contains(':')) {
            List<String> partsList = preferredTimeStr.split(':');
            hourInt   = Integer.valueOf(partsList[0]);
            minuteInt = Integer.valueOf(partsList[1]);
        }

        String secStr = '0';
        String minStr = String.valueOf(minuteInt);
        String hrStr  = String.valueOf(hourInt);

        if (frequencyStr == 'DAILY') {
            return secStr + ' ' + minStr + ' ' + hrStr + ' * * ?';
        }

        if (frequencyStr == 'WEEKLY') {
            String dayStr = (dayOfWeekStr != null && dayOfWeekStr != '')
                ? dayOfWeekStr
                : 'MON';
            return secStr + ' ' + minStr + ' ' + hrStr + ' ? * ' + dayStr;
        }

        if (frequencyStr == 'MONTHLY') {
            return secStr + ' ' + minStr + ' ' + hrStr + ' 1 * ?';
        }

        if (frequencyStr == 'YEARLY') {
            return secStr + ' ' + minStr + ' ' + hrStr + ' 1 1 ?';
        }

        return secStr + ' ' + minStr + ' ' + hrStr + ' * * ?';
    }

    /**
     * @description Updates the status of a schedule record. Aborts the job if deactivating.
     * @param scheduleId The ID of the schedule record to update.
     * @param statusStr The new status value ('Active' or 'In Active').
     */
    @AuraEnabled
    public static void updateScheduleStatus(Id scheduleId, String statusStr) {

        List<Data_Archive_Schedule__c> schedulesList = [
            SELECT Id, Job_Id__c, Status__c
            FROM Data_Archive_Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];

        if (schedulesList.isEmpty()) {
            throw new AuraHandledException('Schedule record not found.');
        }

        Data_Archive_Schedule__c scheduleRecord = schedulesList[0];

        if (statusStr == 'In Active' && scheduleRecord.Job_Id__c != null) {
            try {
                System.abortJob(scheduleRecord.Job_Id__c);
            } catch (Exception ex) {
                // Job may already have been deleted
            }
        }

        scheduleRecord.Status__c = statusStr;
        update scheduleRecord;
    }

    /**
     * @description Deactivates a schedule by aborting its cron job and setting status to 'In Active'.
     * @param scheduleId The ID of the schedule record to deactivate.
     * @return A success message string.
     */
    @AuraEnabled
    public static String deactivateSchedule(Id scheduleId) {

        List<Data_Archive_Schedule__c> schedulesList = [
            SELECT Id, Job_Id__c, Status__c
            FROM Data_Archive_Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];

        if (schedulesList.isEmpty()) {
            throw new AuraHandledException('Schedule record not found.');
        }

        Data_Archive_Schedule__c scheduleRecord = schedulesList[0];

        if (scheduleRecord.Job_Id__c != null) {
            try {
                System.abortJob(scheduleRecord.Job_Id__c);
            } catch (Exception ex) {
                // Job may already have been deleted from Setup
            }
        }

        scheduleRecord.Status__c = 'In Active';
        update scheduleRecord;
        return 'Schedule deactivated successfully';
    }
}