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

        List<SObject> buffer = new List<SObject>();
        Set<Id> archiveDelete = new Set<Id>();
        Set<Id> docDelete = new Set<Id>();

        for (Data_Archive__c archive : archives) {

            Schema.SObjectType objType =
                globalMap.get(archive.Parent_Object__c);
            if (objType == null) continue;

            Map<String, Schema.SObjectField> fieldMap =
                objType.getDescribe().fields.getMap();

            for (ContentVersion cv : [
                SELECT VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Title = :archive.Name
                AND FileType = 'CSV'
            ]) {

                docDelete.add(cv.ContentDocumentId);

                List<String> lines = cv.VersionData.toString().split('\n');
                if (lines.size() < 2) continue;

                List<String> headers = lines[0].split(',');

                for (Integer r = 1; r < lines.size(); r++) {
                    if (String.isBlank(lines[r])) continue;

                    List<String> values = lines[r].split(',');
                    SObject sobj = objType.newSObject();
                    Boolean hasData = false;

                    for (Integer i = 0; i < headers.size() && i < values.size(); i++) {

                        String f = headers[i].trim();
                        if (f == 'Id' || !fieldMap.containsKey(f)) continue;

                        String raw = values[i].replace('"','').trim();
                        if (String.isBlank(raw)) continue;

                        Schema.DescribeFieldResult d =
                            fieldMap.get(f).getDescribe();

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
            }
            archiveDelete.add(archive.Id);
        }

        if (!buffer.isEmpty()) {
            Database.insert(buffer, false);
        }

        delete [SELECT Id FROM Data_Archive__c WHERE Id IN :archiveDelete];
        delete [SELECT Id FROM ContentDocument WHERE Id IN :docDelete];
    }
}