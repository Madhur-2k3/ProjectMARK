public with sharing class DataArchiveScheduler implements Schedulable {

    private String objectName;
    private String criteriaField;
    private Integer days;
    private String filterValue;
    private String scheduleName;
    private List<String> selectedChildObjects;

    // Backward-compatible constructor (4 params - used by older tests)
    public DataArchiveScheduler(
        String objectName,
        String criteriaField,
        Integer days,
        String scheduleName
    ){
        this(objectName, criteriaField, days, null, scheduleName, null);
    }

    // Backward-compatible constructor (no child objects)
    public DataArchiveScheduler(
        String objectName,
        String criteriaField,
        Integer days,
        String filterValue,
        String scheduleName
    ){
        this(objectName, criteriaField, days, filterValue, scheduleName, null);
    }

    // Full constructor with child object selection
    public DataArchiveScheduler(
        String objectName,
        String criteriaField,
        Integer days,
        String filterValue,
        String scheduleName,
        List<String> selectedChildObjects
    ){
        this.objectName    = objectName;
        this.criteriaField = criteriaField;
        this.days          = days;
        this.filterValue   = filterValue;
        this.scheduleName  = scheduleName;
        this.selectedChildObjects = selectedChildObjects;
    }

    public void execute(SchedulableContext sc) {

        // ── Build fields CSV dynamically from the object's schema ──
        String fieldsCsv = buildFieldsCsv(this.objectName);

        // ── Build WHERE clause based on criteria type ──
        String whereClause;

        if (this.filterValue != null && this.filterValue != '') {
            // LWC criteria modal passes a pre-built WHERE clause
            whereClause = this.filterValue;
        } else {
            // Date-based filter  →  WHERE CreatedDate <= 2026-01-17
            Integer daysVal = (this.days != null) ? this.days : 0;
            Date targetDate = Date.today().addDays(-daysVal);
            
            // Format appropriately based on field type
            String formattedDate = String.valueOf(targetDate).substring(0, 10);
            
            try {
                Schema.SObjectType objType = Schema.getGlobalDescribe().get(this.objectName);
                if (objType != null) {
                    Map<String, Schema.SObjectField> fMap = objType.getDescribe().fields.getMap();
                    String fNameLower = this.criteriaField != null ? this.criteriaField.toLowerCase() : '';
                    if (fMap.containsKey(fNameLower)) {
                        Schema.DescribeFieldResult fd = fMap.get(fNameLower).getDescribe();
                        if (fd.getType() == Schema.DisplayType.DATETIME) {
                            Datetime dt = Datetime.newInstanceGmt(targetDate, Time.newInstance(0,0,0,0));
                            formattedDate = dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                        }
                    }
                }
            } catch (Exception e) {
                // Ignore schema errors, fallback to standard date format
            }
            
            whereClause = this.criteriaField + ' <= ' + formattedDate;
        }

        String soql =
            'SELECT ' + fieldsCsv +
            ' FROM '  + this.objectName +
            ' WHERE ' + whereClause;

        DataArchiveBatch batch =
            new DataArchiveBatch(objectName, fieldsCsv, soql, scheduleName, selectedChildObjects);

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