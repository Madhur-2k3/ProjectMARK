public with sharing class DataArchiveScheduleTriggerHandler {

    // ─────────────────────────────────────────────────────────────
    //  Called from DataArchiveScheduleTrigger (after update)
    //  Detects records flipped from any non-Active status → 'Active'
    //  and re-creates the cron job using the record's stored criteria.
    // ─────────────────────────────────────────────────────────────
    public static void handleAfterUpdate(
        List<Data_Archive_Schedule__c> newRecords,
        Map<Id, Data_Archive_Schedule__c> oldMap
    ) {
        Set<Id> toActivateIds = new Set<Id>();

        for (Data_Archive_Schedule__c rec : newRecords) {
            Data_Archive_Schedule__c old = oldMap.get(rec.Id);

            // Only process records where status just changed TO 'Active'
            if (rec.Status__c == 'Active' && old.Status__c != 'Active') {
                toActivateIds.add(rec.Id);
            }
        }

        if (toActivateIds.isEmpty()) return;

        reactivateSchedules(toActivateIds);
    }

    // ─────────────────────────────────────────────────────────────
    //  For each newly-activated record:
    //   1. Abort any stale job that is still registered
    //   2. Build a new cron expression from stored settings
    //   3. Schedule a fresh DataArchiveScheduler job
    //   4. Write the new Job_Id__c + Cron_Expression__c back
    // ─────────────────────────────────────────────────────────────
    // @future only supports primitive types — pass record IDs and re-query inside
    @future
    public static void reactivateSchedules(Set<Id> recIds) {
        List<Data_Archive_Schedule__c> fullRecords = [
            SELECT Id, Name, Job_Id__c, Object_Name__c,
                   Frequency__c, Date_Field__c, Days__c,
                   Preferred_Time__c, Day_Of_Week__c,
                   Selected_Child_Objects__c
            FROM Data_Archive_Schedule__c
            WHERE Id IN :recIds
        ];

        List<Data_Archive_Schedule__c> toUpdate = new List<Data_Archive_Schedule__c>();

        for (Data_Archive_Schedule__c rec : fullRecords) {

            // Abort any still-existing stale cron job for this record
            if (rec.Job_Id__c != null) {
                try {
                    System.abortJob(rec.Job_Id__c);
                } catch (Exception e) {
                    // Already gone from Setup — that's fine
                }
            }

            // Build cron expression from stored frequency + time settings
            String cronExp = buildCronExpression(
                rec.Frequency__c,
                rec.Preferred_Time__c,
                rec.Day_Of_Week__c
            );

            String jobName =
                'Archive_' + rec.Object_Name__c + '_' +
                Datetime.now().getTime();

            // Parse stored child objects back into a List
            List<String> childObjects = null;
            if (rec.Selected_Child_Objects__c != null && rec.Selected_Child_Objects__c != '') {
                childObjects = rec.Selected_Child_Objects__c.split(',');
            }

            Id newJobId = System.schedule(
                jobName,
                cronExp,
                new DataArchiveScheduler(
                    rec.Object_Name__c,
                    rec.Date_Field__c,
                    rec.Days__c != null ? Integer.valueOf(rec.Days__c) : 0,
                    null,       // filterValue not persisted; scheduler uses date-based filter
                    rec.Name,   // pass the schedule record name
                    childObjects
                )
            );

            toUpdate.add(new Data_Archive_Schedule__c(
                Id                 = rec.Id,
                Job_Id__c          = newJobId,
                Cron_Expression__c = cronExp,
                Status__c          = 'Active'
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  buildCronExpression is intentionally duplicated here.
    //  System.schedule() + update DML cannot share a transaction
    //  with the non-setup DML that fired the trigger (Mixed-DML).
    //  @future runs in a separate transaction to avoid this.
    //  The cron logic in DataArchiveScheduleController is private,
    //  so we maintain a copy here rather than break encapsulation.
    // ─────────────────────────────────────────────────────────────
    private static String buildCronExpression(
        String frequency,
        String preferredTime,
        String dayOfWeek
    ) {
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
            String day = (dayOfWeek != null && dayOfWeek != '') ? dayOfWeek : 'MON';
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
}