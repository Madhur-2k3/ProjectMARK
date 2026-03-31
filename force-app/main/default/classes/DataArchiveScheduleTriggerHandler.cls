/**
 * @description Trigger handler for Data_Archive_Schedule__c records.
 *              Manages scheduling and unscheduling of archive jobs when
 *              schedule records are inserted, updated, or deleted.
 */
public with sharing class DataArchiveScheduleTriggerHandler {

    /**
     * @description Handles after-insert logic: schedules archive jobs for
     *              newly created active schedule records.
     * @param newSchedulesList List of newly inserted Data_Archive_Schedule__c records.
     */
    public static void handleAfterInsert(List<Data_Archive_Schedule__c> newSchedulesList) {

        for (Data_Archive_Schedule__c currentSchedule : newSchedulesList) {

            if (currentSchedule.Status__c == 'Active' && String.isNotBlank(currentSchedule.Cron_Expression__c)) {
                scheduleJob(currentSchedule);
            }
        }
    }

    /**
     * @description Handles after-update logic: reschedules or unschedules archive jobs
     *              based on changes to schedule records.
     * @param newSchedulesList List of updated Data_Archive_Schedule__c records (new values).
     * @param oldSchedulesMap Map of old Data_Archive_Schedule__c records keyed by ID.
     */
    public static void handleAfterUpdate(
        List<Data_Archive_Schedule__c> newSchedulesList,
        Map<Id, Data_Archive_Schedule__c> oldSchedulesMap
    ) {

        for (Data_Archive_Schedule__c currentSchedule : newSchedulesList) {

            Data_Archive_Schedule__c oldSchedule = oldSchedulesMap.get(currentSchedule.Id);

            Boolean wasActiveFlag = oldSchedule.Status__c == 'Active';
            Boolean isActiveFlag = currentSchedule.Status__c == 'Active';

            if (isActiveFlag && String.isNotBlank(currentSchedule.Cron_Expression__c)) {

                if (wasActiveFlag) {
                    unscheduleJob(currentSchedule.Id);
                }

                scheduleJob(currentSchedule);

            } else if (!isActiveFlag && wasActiveFlag) {
                unscheduleJob(currentSchedule.Id);
            }
        }
    }

    /**
     * @description Handles before-delete logic: unschedules archive jobs
     *              for schedule records being deleted.
     * @param oldSchedulesList List of Data_Archive_Schedule__c records being deleted.
     */
    public static void handleBeforeDelete(List<Data_Archive_Schedule__c> oldSchedulesList) {

        for (Data_Archive_Schedule__c currentSchedule : oldSchedulesList) {
            unscheduleJob(currentSchedule.Id);
        }
    }

    /**
     * @description Schedules a DataArchiveScheduler job using the cron expression
     *              from the given schedule record.
     * @param scheduleRecord The Data_Archive_Schedule__c record containing schedule details.
     */
    private static void scheduleJob(Data_Archive_Schedule__c scheduleRecord) {

        try {
            String jobNameStr = 'DataArchive_' + scheduleRecord.Id;

            List<String> selectedChildObjectsList = null;

            if (String.isNotBlank(scheduleRecord.Selected_Child_Objects__c)) {
                selectedChildObjectsList = (List<String>) JSON.deserialize(
                    scheduleRecord.Selected_Child_Objects__c,
                    List<String>.class
                );
            }

            DataArchiveScheduler scheduler = new DataArchiveScheduler(
                scheduleRecord.Object_Name__c,
                scheduleRecord.Date_Field__c,
                scheduleRecord.Days__c != null ? Integer.valueOf(scheduleRecord.Days__c) : 0,
                null,
                jobNameStr,
                selectedChildObjectsList
            );

            System.schedule(jobNameStr, scheduleRecord.Cron_Expression__c, scheduler);

        } catch (Exception ex) {
            System.debug('Failed to schedule job for ' + scheduleRecord.Id + ': ' + ex.getMessage());
        }
    }

    /**
     * @description Unschedules a previously scheduled archive job by aborting
     *              the CronTrigger associated with the schedule record.
     * @param scheduleId The ID of the Data_Archive_Schedule__c record whose job should be aborted.
     */
    private static void unscheduleJob(Id scheduleId) {

        String jobNameStr = 'DataArchive_' + scheduleId;

        try {
            List<CronTrigger> jobsList = [
                SELECT Id
                FROM CronTrigger
                WHERE CronJobDetail.Name = :jobNameStr
                LIMIT 1
            ];

            if (!jobsList.isEmpty()) {
                System.abortJob(jobsList[0].Id);
            }
        } catch (Exception ex) {
            System.debug('Failed to unschedule job ' + jobNameStr + ': ' + ex.getMessage());
        }
    }
}