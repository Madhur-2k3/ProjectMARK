/**
 * @description Controller for the Data Archive Object Lightning component.
 *              Provides paginated archive views and unarchive functionality.
 */
public with sharing class DataArchiveObjectController {

    /**
     * @description Wrapper class for paginated archive data including columns and rows.
     */
    public class ArchiveWrapper {

        @AuraEnabled public List<Map<String, Object>> columns;
        @AuraEnabled public List<Map<String, Object>> data;
        @AuraEnabled public Integer totalRecords;
    }

    /**
     * @description Retrieves paginated Data_Archive__c records with column definitions.
     * @param pageNumberInt The current page number (1-based).
     * @param pageSizeInt The number of records per page.
     * @return An ArchiveWrapper containing columns, data rows, and total record count.
     */
    @AuraEnabled(cacheable=true)
    public static ArchiveWrapper getArchivedObjectPaginated(
        Integer pageNumberInt,
        Integer pageSizeInt
    ) {

        if (pageNumberInt == null) pageNumberInt = 1;
        if (pageSizeInt == null) pageSizeInt = 5;

        Integer offsetInt = (pageNumberInt - 1) * pageSizeInt;

        Integer totalCountInt = [
            SELECT COUNT() FROM Data_Archive__c
        ];

        List<Data_Archive__c> recordsList = [
            SELECT Id, Name, Fields__c, Parent_Object__c, Status__c
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
            LIMIT :pageSizeInt OFFSET :offsetInt
        ];

        List<Map<String, Object>> columnsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'label' => 'Data Archive Name',
                'fieldName' => 'recordUrl',
                'type' => 'url',
                'typeAttributes' => new Map<String, Object>{
                    'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
                    'target' => '_blank'
                }
            },
            new Map<String, Object>{
                'label' => 'Fields',
                'fieldName' => 'Fields__c',
                'type' => 'text'
            },
            new Map<String, Object>{
                'label' => 'Parent Object',
                'fieldName' => 'Parent_Object__c',
                'type' => 'text'
            },
            new Map<String, Object>{
                'label' => 'Status',
                'fieldName' => 'Status__c',
                'type' => 'text',
                'cellAttributes' => new Map<String, Object>{
                    'class' => new Map<String, Object>{
                        'fieldName' => 'statusClass'
                    }
                }
            }
        };

        List<Map<String, Object>> rowsList = new List<Map<String, Object>>();

        for (Data_Archive__c currentRecord : recordsList) {

            rowsList.add(new Map<String, Object>{
                'Id' => currentRecord.Id,
                'Name' => currentRecord.Name,
                'Fields__c' => currentRecord.Fields__c,
                'Parent_Object__c' => currentRecord.Parent_Object__c,
                'Status__c' => currentRecord.Status__c,
                'recordUrl' => '/' + currentRecord.Id,
                'isSelectable' => currentRecord.Status__c == 'Ready for Unarchive',
                'statusClass' =>
                    currentRecord.Status__c == 'In Progress'
                    ? 'slds-text-color_success slds-text-title_bold'
                    : ''
            });
        }

        ArchiveWrapper wrapper = new ArchiveWrapper();
        wrapper.columns = columnsList;
        wrapper.data = rowsList;
        wrapper.totalRecords = totalCountInt;
        return wrapper;
    }

    /**
     * @description Starts the unarchive process asynchronously for the given archive IDs.
     *              Updates each archive's status to 'In Progress' and enqueues the
     *              DataArchiveUnarchiveQueueable.
     * @param archiveRecordIdsList List of Data_Archive__c record IDs to unarchive.
     * @return A status message indicating the job has been started.
     */
    @AuraEnabled
    public static String unarchiveAsync(List<Id> archiveRecordIdsList) {

        if (archiveRecordIdsList == null || archiveRecordIdsList.isEmpty()) {
            return 'No records selected';
        }

        List<Data_Archive__c> updatesList = new List<Data_Archive__c>();

        for (Id currentId : archiveRecordIdsList) {
            updatesList.add(
                new Data_Archive__c(
                    Id = currentId,
                    Status__c = 'In Progress'
                )
            );
        }

        update updatesList;

        System.enqueueJob(
            new DataArchiveUnarchiveQueueable(archiveRecordIdsList)
        );

        return 'Un-archive started in background. This may take a few minutes.';
    }
}