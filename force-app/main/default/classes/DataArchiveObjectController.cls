public with sharing class DataArchiveObjectController {

    /* ================= WRAPPER ================= */
    public class ArchiveWrapper {
        @AuraEnabled public List<Map<String, Object>> columns;
        @AuraEnabled public List<Map<String, Object>> data;
        @AuraEnabled public Integer totalRecords;
    }

    /* ================= PAGINATION ================= */
    @AuraEnabled(cacheable=true)
    public static ArchiveWrapper getArchivedObjectPaginated(
        Integer pageNumber,
        Integer pageSize
    ) {
        if (pageNumber == null) pageNumber = 1;
        if (pageSize == null) pageSize = 5;

        Integer offsetVal = (pageNumber - 1) * pageSize;

        Integer totalCount = [
            SELECT COUNT() FROM Data_Archive__c
        ];

        List<Data_Archive__c> records = [
            SELECT Id, Name, Fields__c, Parent_Object__c, Status__c
            FROM Data_Archive__c
            ORDER BY CreatedDate DESC
            LIMIT :pageSize OFFSET :offsetVal
        ];

        List<Map<String, Object>> columns = new List<Map<String, Object>>{
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

            // new Map<String, Object>{
            //     'type' => 'button-icon',
            //     'initialWidth' => 60,
            //     'typeAttributes' => new Map<String, Object>{
            //         'iconName' => 'utility:download',
            //         'name' => 'downloadCsv',
            //         'title' => 'Download All CSV'
            //     }
            // }
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Data_Archive__c r : records) {

          

            rows.add(new Map<String, Object>{
    'Id' => r.Id,
    'Name' => r.Name,
    'Fields__c' => r.Fields__c,
    'Parent_Object__c' => r.Parent_Object__c,
    'Status__c' => r.Status__c,
    'recordUrl' => '/' + r.Id,
    'isSelectable' => r.Status__c == 'Ready for Unarchive',
    'statusClass' =>
        r.Status__c == 'In Progress'
        ? 'slds-text-color_success slds-text-title_bold'
        : ''
});
        }

        ArchiveWrapper w = new ArchiveWrapper();
        w.columns = columns;
        w.data = rows;
        w.totalRecords = totalCount;
        return w;
    }

    /* ================= DOWNLOAD ALL CSV FILES ================= */
    // @AuraEnabled
    // public static List<String> getAllArchiveCsvDownloadUrls(Id archiveId) {

    //     List<String> urls = new List<String>();

    //     for (ContentDocumentLink cdl : [
    //         SELECT ContentDocumentId
    //         FROM ContentDocumentLink
    //         WHERE LinkedEntityId = :archiveId
    //         
    //     ]) {
    //         urls.add(
    //             '/sfc/servlet.shepherd/document/download/' +
    //             cdl.ContentDocumentId
    //         );
    //     }
    //     return urls;
    // }

    /* ================= START ASYNC ================= */
    @AuraEnabled
    public static String unarchiveAsync(List<Id> archiveRecordIds) {

        if (archiveRecordIds == null || archiveRecordIds.isEmpty()) {
            return 'No records selected';
        }

        List<Data_Archive__c> updates = new List<Data_Archive__c>();
        for (Id i : archiveRecordIds) {
            updates.add(
                new Data_Archive__c(
                    Id = i,
                    Status__c = 'In Progress'
                )
            );
        }
        update updates;

        System.enqueueJob(
            new DataArchiveUnarchiveQueueable(archiveRecordIds)
        );

        return 'Un-archive started in background. This may take a few minutes.';
    }
}

// public with sharing class DataArchiveObjectController {

//     /* ================= WRAPPER ================= */
//     public class ArchiveWrapper {
//         @AuraEnabled public List<Map<String, Object>> columns;
//         @AuraEnabled public List<Map<String, Object>> data;
//         @AuraEnabled public Integer totalRecords;
//     }

//     /* ================= PAGINATION ================= */
//     @AuraEnabled(cacheable=true)
//     public static ArchiveWrapper getArchivedObjectPaginated(
//         Integer pageNumber,
//         Integer pageSize
//     ) {
//         if (pageNumber == null) pageNumber = 1;
//         if (pageSize == null) pageSize = 5;

//         Integer offsetVal = (pageNumber - 1) * pageSize;

//         Integer totalCount = [
//             SELECT COUNT() FROM Data_Archive__c
//         ];

//         List<Data_Archive__c> records = [
//             SELECT Id, Name, Fields__c, Parent_Object__c, Status__c
//             FROM Data_Archive__c
//             ORDER BY CreatedDate DESC
//             LIMIT :pageSize OFFSET :offsetVal
//         ];

//         /* ================= COLUMNS ================= */
//         List<Map<String, Object>> columns = new List<Map<String, Object>>{
//             new Map<String, Object>{
//                 'label' => 'Data Archive Name',
//                 'fieldName' => 'recordUrl',
//                 'type' => 'url',
//                 'typeAttributes' => new Map<String, Object>{
//                     'label' => new Map<String, Object>{ 'fieldName' => 'Name' },
//                     'target' => '_blank'
//                 }
//             },
//             new Map<String, Object>{
//                 'label' => 'Fields',
//                 'fieldName' => 'Fields__c',
//                 'type' => 'text'
//             },
//             new Map<String, Object>{
//                 'label' => 'Parent Object',
//                 'fieldName' => 'Parent_Object__c',
//                 'type' => 'text'
//             },
//             new Map<String, Object>{
//                 'label' => 'Status',
//                 'fieldName' => 'Status__c',
//                 'type' => 'text',
//                 'cellAttributes' => new Map<String, Object>{
//                     'class' => new Map<String, Object>{
//                         'fieldName' => 'statusClass'
//                     }
//                 }
//             },

//             // ✅ Download button column
//             new Map<String, Object>{
//                 'type' => 'button-icon',
//                 'initialWidth' => 60,
//                 'typeAttributes' => new Map<String, Object>{
//                     'iconName' => 'utility:download',
//                     'name' => 'downloadCsv',
//                     'title' => 'Download All CSV',
//                     'variant' => 'border-filled',
//                     'alternativeText' => 'Download CSV'
//                 }
//             }
//         };

//         /* ================= ROWS ================= */
//         List<Map<String, Object>> rows = new List<Map<String, Object>>();

//         for (Data_Archive__c r : records) {

//             String statusClass = '';
//             if (r.Status__c == 'In Progress') {
//                 statusClass = 'slds-text-color_success slds-text-title_bold';
//             }

//             rows.add(new Map<String, Object>{
//                 'Id' => r.Id,
//                 'Name' => r.Name,
//                 'Fields__c' => r.Fields__c,
//                 'Parent_Object__c' => r.Parent_Object__c,
//                 'Status__c' => r.Status__c,
//                 'recordUrl' => '/' + r.Id,

//                 // disable selection if not ready
//                 'isSelectable' => r.Status__c == 'Ready for Unarchive',

//                 // for status color
//                 'statusClass' => statusClass
//             });
//         }

//         ArchiveWrapper w = new ArchiveWrapper();
//         w.columns = columns;
//         w.data = rows;
//         w.totalRecords = totalCount;
//         return w;
//     }

//     /* ================= DOWNLOAD ALL CSV FILES ================= */
//     @AuraEnabled
//     public static List<String> getAllArchiveCsvDownloadUrls(Id archiveId) {

//         List<String> urls = new List<String>();

//         // 1) Get all linked documents
//         List<ContentDocumentLink> links = [
//             SELECT ContentDocumentId
//             FROM ContentDocumentLink
//             WHERE LinkedEntityId = :archiveId
//             ORDER BY SystemModstamp DESC
//         ];

//         if (links.isEmpty()) return urls;

//         Set<Id> docIds = new Set<Id>();
//         for (ContentDocumentLink cdl : links) {
//             docIds.add(cdl.ContentDocumentId);
//         }

//         // 2) Filter only CSV latest versions
//         List<ContentVersion> csvFiles = [
//             SELECT ContentDocumentId, FileExtension
//             FROM ContentVersion
//             WHERE ContentDocumentId IN :docIds
//             AND IsLatest = true
//             AND FileExtension = 'csv'
//         ];

//         Set<Id> csvDocIds = new Set<Id>();
//         for (ContentVersion cv : csvFiles) {
//             csvDocIds.add(cv.ContentDocumentId);
//         }

//         // 3) Create download URLs
//         for (Id docId : csvDocIds) {
//             urls.add('/sfc/servlet.shepherd/document/download/' + docId);
//         }

//         return urls;
//     }

//     /* ================= START ASYNC ================= */
//     @AuraEnabled
//     public static String unarchiveAsync(List<Id> archiveRecordIds) {

//         if (archiveRecordIds == null || archiveRecordIds.isEmpty()) {
//             return 'No records selected';
//         }

//         // update status immediately
//         List<Data_Archive__c> updates = new List<Data_Archive__c>();
//         for (Id i : archiveRecordIds) {
//             updates.add(new Data_Archive__c(
//                 Id = i,
//                 Status__c = 'In Progress'
//             ));
//         }
//         update updates;

//         // run queueable
//         System.enqueueJob(new DataArchiveUnarchiveQueueable(archiveRecordIds));

//         return 'Un-archive started in background. This may take a few minutes.';
//     }
// }