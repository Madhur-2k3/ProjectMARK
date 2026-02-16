public with sharing class DataArchiveScheduler implements Schedulable {

    private String objectName;
    private String criteriaField;
    private Integer days;
    private String filterValue;

    public DataArchiveScheduler(
        String objectName,
        String criteriaField,
        Integer days,
        String filterValue
    ){
        this.objectName    = objectName;
        this.criteriaField = criteriaField;
        this.days          = days;
        this.filterValue   = filterValue;
    }

    public void execute(SchedulableContext sc) {

        // ── Build fields CSV dynamically from the object's schema ──
        String fieldsCsv = buildFieldsCsv(this.objectName);

        // ── Build WHERE clause based on criteria type ──
        String whereClause;

        if (this.filterValue != null && this.filterValue != '') {
            // Text-based filter  →  WHERE Customer_Name__c = 'value'
            String safeValue = String.escapeSingleQuotes(this.filterValue);
            whereClause = this.criteriaField + ' = \'' + safeValue + '\'';
        } else {
            // Date-based filter  →  WHERE CreatedDate <= 2026-01-17
            Integer daysVal = (this.days != null) ? this.days : 0;
            Date targetDate = Date.today().addDays(-daysVal);
            whereClause = this.criteriaField + ' <= ' + String.valueOf(targetDate);
        }

        String soql =
            'SELECT ' + fieldsCsv +
            ' FROM '  + this.objectName +
            ' WHERE ' + whereClause;

        DataArchiveBatch batch =
            new DataArchiveBatch(objectName, fieldsCsv, soql);

        Database.executeBatch(batch, 200);
    }

    // ── Discover all accessible, createable fields for the object ──
    private String buildFieldsCsv(String objName) {

        Schema.SObjectType objType =
            Schema.getGlobalDescribe().get(objName);

        if (objType == null) {
            return 'Id';          // fallback
        }

        Map<String, Schema.SObjectField> fieldMap =
            objType.getDescribe().fields.getMap();

        List<String> fieldNames = new List<String>();

        for (String key : fieldMap.keySet()) {

            Schema.DescribeFieldResult fd =
                fieldMap.get(key).getDescribe();

            if (!fd.isAccessible()) continue;

            // Skip system-only fields that aren't useful
            if (key.endsWith('__pc') || key == 'isdeleted') continue;

            // Include createable fields + common read-only fields
            if (fd.isCreateable()
                || key == 'id'
                || key == 'name'
                || key == 'createddate'
                || key == 'createdbyid'
                || key == 'lastmodifieddate'
                || key == 'lastmodifiedbyid') {

                fieldNames.add(fd.getName());
            }
        }

        return fieldNames.isEmpty()
            ? 'Id'
            : String.join(fieldNames, ',');
    }
}