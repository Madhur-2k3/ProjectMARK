/**
 * @description Schedulable class that builds and executes a DataArchiveBatch job
 *              based on configured criteria (date-based or custom filter).
 *              Supports multiple constructors for backward compatibility.
 */
public with sharing class DataArchiveScheduler implements Schedulable {

    private String objectNameStr;
    private String criteriaFieldStr;
    private Integer daysInt;
    private String filterValueStr;
    private String scheduleNameStr;
    private List<String> selectedChildObjectsList;

    /**
     * @description Backward-compatible constructor (4 params — used by older tests).
     * @param objectNameStr The API name of the SObject to archive.
     * @param criteriaFieldStr The field used for date-based filtering.
     * @param daysInt Number of days back for the date filter.
     * @param scheduleNameStr Name for the scheduled job.
     */
    public DataArchiveScheduler(
        String objectNameStr,
        String criteriaFieldStr,
        Integer daysInt,
        String scheduleNameStr
    ) {

        this(objectNameStr, criteriaFieldStr, daysInt, null, scheduleNameStr, null);
    }

    /**
     * @description Backward-compatible constructor (no child objects).
     * @param objectNameStr The API name of the SObject to archive.
     * @param criteriaFieldStr The field used for date-based filtering.
     * @param daysInt Number of days back for the date filter.
     * @param filterValueStr Pre-built WHERE clause, or null for date-based filter.
     * @param scheduleNameStr Name for the scheduled job.
     */
    public DataArchiveScheduler(
        String objectNameStr,
        String criteriaFieldStr,
        Integer daysInt,
        String filterValueStr,
        String scheduleNameStr
    ) {

        this(objectNameStr, criteriaFieldStr, daysInt, filterValueStr, scheduleNameStr, null);
    }

    /**
     * @description Full constructor with child object selection.
     * @param objectNameStr The API name of the SObject to archive.
     * @param criteriaFieldStr The field used for date-based filtering.
     * @param daysInt Number of days back for the date filter.
     * @param filterValueStr Pre-built WHERE clause, or null for date-based filter.
     * @param scheduleNameStr Name for the scheduled job.
     * @param selectedChildObjectsList List of child object API names to include.
     */
    public DataArchiveScheduler(
        String objectNameStr,
        String criteriaFieldStr,
        Integer daysInt,
        String filterValueStr,
        String scheduleNameStr,
        List<String> selectedChildObjectsList
    ) {

        this.objectNameStr           = objectNameStr;
        this.criteriaFieldStr        = criteriaFieldStr;
        this.daysInt                 = daysInt;
        this.filterValueStr          = filterValueStr;
        this.scheduleNameStr         = scheduleNameStr;
        this.selectedChildObjectsList = selectedChildObjectsList;
    }

    /**
     * @description Executes the scheduled archive job by building a SOQL query
     *              and launching a DataArchiveBatch.
     * @param scheduleContext The SchedulableContext provided by the platform.
     */
    public void execute(SchedulableContext scheduleContext) {

        String fieldsCsvStr = buildFieldsCsv(this.objectNameStr);

        String whereClauseStr;

        if (this.filterValueStr != null && this.filterValueStr != '') {
            whereClauseStr = this.filterValueStr;
        } else {
            Integer daysValInt = (this.daysInt != null) ? this.daysInt : 0;
            Date targetDt = Date.today().addDays(-daysValInt);

            String formattedDateStr = String.valueOf(targetDt).substring(0, 10);

            try {
                Schema.SObjectType objType = Schema.getGlobalDescribe().get(this.objectNameStr);

                if (objType != null) {
                    Map<String, Schema.SObjectField> fieldsMap = objType.getDescribe().fields.getMap();
                    String fieldNameLowerStr = this.criteriaFieldStr != null ? this.criteriaFieldStr.toLowerCase() : '';

                    if (fieldsMap.containsKey(fieldNameLowerStr)) {
                        Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldNameLowerStr).getDescribe();

                        if (fieldDescribe.getType() == Schema.DisplayType.DATETIME) {
                            Datetime datetimeDtm = Datetime.newInstanceGmt(targetDt, Time.newInstance(0, 0, 0, 0));
                            formattedDateStr = datetimeDtm.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                        }
                    }
                }
            } catch (Exception ex) {
                // Ignore schema errors, fallback to standard date format
            }

            whereClauseStr = this.criteriaFieldStr + ' <= ' + formattedDateStr;
        }

        String soqlStr =
            'SELECT ' + fieldsCsvStr +
            ' FROM '  + this.objectNameStr +
            ' WHERE ' + whereClauseStr;

        DataArchiveBatch batch =
            new DataArchiveBatch(objectNameStr, fieldsCsvStr, soqlStr, scheduleNameStr, selectedChildObjectsList);

        Database.executeBatch(batch, 200);
    }

    /**
     * @description Discovers all accessible, createable fields for the given object
     *              and returns them as a comma-separated string.
     * @param objNameStr The API name of the SObject to describe.
     * @return A comma-separated string of field API names.
     */
    private String buildFieldsCsv(String objNameStr) {

        Schema.SObjectType objType =
            Schema.getGlobalDescribe().get(objNameStr);

        if (objType == null) {
            return 'Id';
        }

        Map<String, Schema.SObjectField> fieldMap =
            objType.getDescribe().fields.getMap();

        List<String> fieldNamesList = new List<String>();

        for (String keyStr : fieldMap.keySet()) {

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(keyStr).getDescribe();

            if (!fieldDescribe.isAccessible()) continue;

            if (keyStr.endsWith('__pc') || keyStr == 'isdeleted') continue;

            if (fieldDescribe.isCreateable()
                || keyStr == 'id'
                || keyStr == 'name'
                || keyStr == 'createddate'
                || keyStr == 'createdbyid'
                || keyStr == 'lastmodifieddate'
                || keyStr == 'lastmodifiedbyid') {

                fieldNamesList.add(fieldDescribe.getName());
            }
        }

        return fieldNamesList.isEmpty()
            ? 'Id'
            : String.join(fieldNamesList, ',');
    }
}