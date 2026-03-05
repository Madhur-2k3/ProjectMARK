trigger DataArchiveScheduleTrigger on Data_Archive_Schedule__c (after update) {
    DataArchiveScheduleTriggerHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}