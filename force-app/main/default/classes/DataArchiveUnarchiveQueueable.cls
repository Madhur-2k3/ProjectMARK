public with sharing class DataArchiveUnarchiveQueueable implements Queueable {

    private List<Id> archiveIds;

    public DataArchiveUnarchiveQueueable(List<Id> ids) {
        this.archiveIds = ids;
    }

    public void execute(QueueableContext qc) {

        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();

        List<Data_Archive__c> archives = [
            SELECT Id, Name, Parent_Object__c
            FROM Data_Archive__c
            WHERE Id IN :archiveIds
        ];

        Set<Id> archiveDelete = new Set<Id>();
        Set<Id> docDelete     = new Set<Id>();

        for (Data_Archive__c archive : archives) {

            String parentObjectName = archive.Parent_Object__c;

            // ===== 1. Find ALL linked ContentDocuments =====
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :archive.Id
            ];

            if (links.isEmpty()) {
                archiveDelete.add(archive.Id);
                continue;
            }

            Set<Id> linkedDocIds = new Set<Id>();
            for (ContentDocumentLink cdl : links) {
                linkedDocIds.add(cdl.ContentDocumentId);
            }

            // ===== 2. Get all CSV ContentVersions =====
            List<ContentVersion> allCsvs = [
                SELECT Title, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :linkedDocIds
                AND IsLatest = true
                AND FileExtension = 'csv'
            ];

            if (allCsvs.isEmpty()) {
                archiveDelete.add(archive.Id);
                continue;
            }

            // Collect doc IDs for cleanup
            for (ContentVersion cv : allCsvs) {
                docDelete.add(cv.ContentDocumentId);
            }

            // ===== 3. Separate parent CSV vs child CSVs =====
            // Archive saves CSVs with Title = objectApiName
            // Parent CSV has Title = parentObjectName
            List<ContentVersion> parentCsvs = new List<ContentVersion>();
            List<ContentVersion> childCsvs  = new List<ContentVersion>();

            for (ContentVersion cv : allCsvs) {
                if (cv.Title == parentObjectName) {
                    parentCsvs.add(cv);
                } else {
                    childCsvs.add(cv);
                }
            }

            // ===== 4. Insert PARENT records first =====
            for (ContentVersion cv : parentCsvs) {
                Schema.SObjectType objType = globalMap.get(parentObjectName);
                if (objType == null) continue;
                insertRecordsFromCsv(cv, objType);
            }

            // ===== 5. Insert CHILD records after parent =====
            for (ContentVersion cv : childCsvs) {
                String childObjectName = cv.Title;
                Schema.SObjectType objType = globalMap.get(childObjectName);
                if (objType == null) {
                    System.debug('Unknown object in CSV Title: ' + childObjectName);
                    continue;
                }
                insertRecordsFromCsv(cv, objType);
            }

            archiveDelete.add(archive.Id);
        }

        // ===== 6. Cleanup =====
        if (!docDelete.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docDelete];
        }
        if (!archiveDelete.isEmpty()) {
            delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archiveDelete];
        }
    }

    // =============== PARSE CSV & INSERT RECORDS ===============
    private void insertRecordsFromCsv(ContentVersion cv, Schema.SObjectType objType) {

        Map<String, Schema.SObjectField> fieldMap =
            objType.getDescribe().fields.getMap();

        List<String> lines = cv.VersionData.toString().split('\n');
        if (lines.size() < 2) return;

        List<String> headers = lines[0].split(',');

        List<SObject> buffer = new List<SObject>();

        for (Integer r = 1; r < lines.size(); r++) {
            if (String.isBlank(lines[r])) continue;

            List<String> values = parseCsvLine(lines[r]);
            SObject sobj = objType.newSObject();
            Boolean hasData = false;

            for (Integer i = 0; i < headers.size() && i < values.size(); i++) {

                String f = headers[i].trim();

                // Skip Id and non-createable system fields
                if (f == 'Id' || !fieldMap.containsKey(f.toLowerCase())) continue;

                Schema.DescribeFieldResult d =
                    fieldMap.get(f.toLowerCase()).getDescribe();

                // Only set createable fields
                if (!d.isCreateable()) continue;

                String raw = values[i].replace('"','').trim();
                if (String.isBlank(raw)) continue;

                try {
                    switch on d.getType() {
                        when Currency, Double, Percent {
                            sobj.put(f, Decimal.valueOf(raw));
                        }
                        when Integer {
                            sobj.put(f, Integer.valueOf(raw));
                        }
                        when Date {
                            sobj.put(f, Date.valueOf(raw));
                        }
                        when DateTime {
                            sobj.put(f, Datetime.valueOf(raw));
                        }
                        when Boolean {
                            sobj.put(f, raw.toLowerCase() == 'true');
                        }
                        when else {
                            sobj.put(f, raw);
                        }
                    }
                    hasData = true;
                } catch (Exception e) {
                    // ignore invalid values safely
                }
            }

            if (hasData) buffer.add(sobj);

            if (buffer.size() == 200) {
                Database.insert(buffer, false);
                buffer.clear();
            }
        }

        if (!buffer.isEmpty()) {
            Database.insert(buffer, false);
        }
    }

    // =============== CSV LINE PARSER (handles quoted commas) ===============
    private List<String> parseCsvLine(String line) {
        List<String> result = new List<String>();
        Boolean inQuotes = false;
        String current = '';

        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);

            if (ch == '"') {
                inQuotes = !inQuotes;
                current += ch;
            } else if (ch == ',' && !inQuotes) {
                result.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current);
        return result;
    }
}