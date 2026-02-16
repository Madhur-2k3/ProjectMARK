public class DataArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ===================== CONSTANTS =====================
    private static final Integer MAX_CSV_SIZE_BYTES = 6 * 1024 * 10; // 60 KB (6*1024*10)

    // ===================== STATE VARIABLES =====================
    private String objectName;
    private List<String> fields;
    private String soqlQuery;
    private Id archiveRecordId;
    private String archiveRecordName;

    // CSV accumulation across batches
    private String currentCsv;
    private Integer partNumber = 1;
    private String header;
    private Set<Id> generatedContentDocumentIds = new Set<Id>();

    // ===================== CONSTRUCTOR =====================
    public DataArchiveBatch(String objectName, String fieldsCsv, String soqlQuery) {
        this.objectName = objectName;
        this.fields = normalizeFields(fieldsCsv);
        this.soqlQuery = soqlQuery;
        
        // Create header
        this.header = String.join(this.fields, ',') + '\n';
        this.currentCsv = this.header;
    }

    // ===================== START METHOD =====================
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Create Data Archive record at start
        Data_Archive__c archiveRecord = new Data_Archive__c(
            Parent_Object__c = this.objectName,
            Fields__c = String.join(this.fields, ','),
            Status__c = 'Archive In Progress'
        );
        insert archiveRecord;

        // Re-query to get auto-number Name
        archiveRecord = [
            SELECT Id, Name
            FROM Data_Archive__c
            WHERE Id = :archiveRecord.Id
            LIMIT 1
        ];

        this.archiveRecordId = archiveRecord.Id;
        this.archiveRecordName = archiveRecord.Name;

        return Database.getQueryLocator(this.soqlQuery);
    }

    // ===================== EXECUTE METHOD =====================
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope.isEmpty()) return;

        List<String> csvLines = buildCsvLines(scope, this.fields);
        
        for (String line : csvLines) {
            // Safety: one record cannot exceed max size
            if (Blob.valueOf(this.header + line).size() > MAX_CSV_SIZE_BYTES) {
                System.debug('Warning: Single record exceeds CSV size limit, skipping.');
                continue;
            }

            String tentativeCsv = this.currentCsv + line + '\n';

            // If limit exceeded → save previous CSV
            if (Blob.valueOf(tentativeCsv).size() > MAX_CSV_SIZE_BYTES) {
                saveCsvFile(this.currentCsv, this.partNumber);
                this.partNumber++;
                this.currentCsv = this.header + line + '\n';
            } else {
                this.currentCsv = tentativeCsv;
            }
        }
    }

    // ===================== FINISH METHOD =====================
    public void finish(Database.BatchableContext bc) {
        // Save any remaining CSV data
        if (this.currentCsv != this.header) {
            saveCsvFile(this.currentCsv, this.partNumber);
        }

        update new Data_Archive__c(
            Id = archiveRecordId,
            Status__c = 'Ready for Unarchive'
        );

        List<Id> ids = new List<Id>();
        for (SObject s : Database.query(this.soqlQuery)) {
            ids.add(s.Id);
        }

        if (!ids.isEmpty()) {
            Integer queueableUsed = Limits.getQueueableJobs();
            Integer queueableLimit = Limits.getLimitQueueableJobs();
            System.debug('DataArchiveBatch.finish queueable usage: ' + queueableUsed + '/' + queueableLimit);

            if (queueableUsed < queueableLimit) {
                System.enqueueJob(
                    new ArchivePostProcessQueueable(
                        new List<Id>(generatedContentDocumentIds),
                        archiveRecordId,
                        objectName,
                        ids
                    )
                );
            } else {
                System.debug('DataArchiveBatch.finish: queueable limit reached, running delete inline as fallback and skipping S3 upload.');
                CascadeDeleteHelper.deleteParentWithRelations(objectName, ids);
            }
        } else if (!generatedContentDocumentIds.isEmpty()) {
            Integer queueableUsed = Limits.getQueueableJobs();
            Integer queueableLimit = Limits.getLimitQueueableJobs();
            System.debug('DataArchiveBatch.finish queueable usage for S3-only post-process: ' + queueableUsed + '/' + queueableLimit);
            if (queueableUsed < queueableLimit) {
                System.enqueueJob(
                    new ArchivePostProcessQueueable(
                        new List<Id>(generatedContentDocumentIds),
                        archiveRecordId,
                        objectName,
                        new List<Id>()
                    )
                );
            } else {
                System.debug('DataArchiveBatch.finish: queueable limit reached, skipping S3 upload post-process.');
            }
        }
    }

    // ===================== HELPER METHODS =====================

    private void saveCsvFile(String csvData, Integer partNum) {

        ContentVersion cv = new ContentVersion(
            Title = this.archiveRecordName,
            PathOnClient = this.archiveRecordName + '.csv',
            Description = 'Part ' + partNum,
            VersionData = Blob.valueOf(csvData)
        );
        insert cv;

        ContentVersion insertedCv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        generatedContentDocumentIds.add(insertedCv.ContentDocumentId);

        insert new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId = this.archiveRecordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    private static List<String> buildCsvLines(List<SObject> rows, List<String> fields) {
        List<String> lines = new List<String>();

        for (SObject row : rows) {
            List<String> cols = new List<String>();
            
            for (String f : fields) {
                Object value;
                
                if (f.contains('.')) {
                    List<String> parts = f.split('\\.');
                    SObject parent = row.getSObject(parts[0]);
                    value = parent != null ? parent.get(parts[1]) : null;
                } else {
                    value = row.get(f);
                }

                cols.add(escapeCsv(value == null ? '' : String.valueOf(value)));
            }
            
            lines.add(String.join(cols, ','));
        }
        return lines;
    }

    private static List<String> normalizeFields(String csv) {
        List<String> fields = new List<String>();
        for (String f : csv.split(',')) {
            if (!String.isBlank(f)) {
                fields.add(f.trim());
            }
        }
        return fields;
    }

    private static String escapeCsv(String v) {
        String s = v.replace('"', '""');
        return (s.contains(',') || s.contains('\n') || s.contains('"'))
            ? '"' + s + '"'
            : s;
    }
}