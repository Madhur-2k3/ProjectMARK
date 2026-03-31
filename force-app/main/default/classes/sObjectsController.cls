/**
 * @description Controller that provides SObject metadata operations including
 *              retrieving all SObject types, field details, child relationships,
 *              and child records for parent record IDs.
 */
public with sharing class sObjectsController {

    /**
     * @description Set of child object name suffixes that indicate system/internal
     *              objects which should be excluded from child relationship results.
     */
    private static final Set<String> EXCLUDED_SUFFIXES = new Set<String>{
        'Feed', 'Share', 'History', 'ChangeEvent', 'Tag',
        'ViewStat', 'VoteStat', 'DataCategorySelection'
    };

    /**
     * @description Set of specific child object names to exclude.
     */
    private static final Set<String> EXCLUDED_OBJECTS = new Set<String>{
        // Activity & event system objects
        'ActivityHistory', 'OpenActivity', 'TaskRelation',
        'EventRelation', 'EmailMessageRelation',

        // Content & document system objects
        'ContentDocumentLink', 'EntitySubscription',

        // Feed system objects
        'FeedComment', 'FeedItem',

        // Topic & flow system objects
        'TopicAssignment', 'NetworkActivityAudit',
        'FlowRecordRelation', 'DuplicateRecordItem',
        'RecordActionHistory', 'RecordAction',

        // Approval & process objects
        'ApprovalSubmission', 'ApprovalSubmissionDetail',
        'ProcessInstance', 'ProcessInstanceNode',
        'ProcessInstanceStep', 'ProcessInstanceHistory',
        'ProcessInstanceWorkitem',

        // Orchestration objects
        'OrchestrationWorkItem',

        // Advanced Account Forecast objects
        'AdvAcctForecastFactAdj', 'AdvAcctForecastSetUse',
        'AdvAcctForecastFact',

        // Assessment objects
        'AssessmentTaskContentDocument', 'AssessmentTask',

        // Finance objects
        'FinanceBalanceSnapshot', 'FinanceTransaction',

        // Engagement objects
        'EngagementTopic', 'EngagementInteraction',

        // Other platform/system objects
        'AuthorizationFormConsent', 'ContactRequest',
        'DigitalSignature', 'DocumentChecklistItem',
        'LabelAssignment', 'ProcessException',
        'RecordAlert', 'ActionPlan', 'ActionPlanItem',
        'ProductItemTransaction', 'ProductRequired',
        'VisitedParty', 'Visitor'
    };

    /**
     * @description Determines whether a child object is a relevant (non-system)
     *              object worth displaying.
     * @param childApiName The API name of the child SObject.
     * @return True if the child object should be included; false if it should be filtered out.
     */
    public static Boolean isRelevantChildObject(String childApiName) {

        if (EXCLUDED_OBJECTS.contains(childApiName)) {
            return false;
        }

        for (String suffix : EXCLUDED_SUFFIXES) {
            if (childApiName.endsWith(suffix)) {
                return false;
            }
        }

        return true;
    }

    /**
     * @description Wrapper class for SObject name information.
     */
    public class SObjectInfo {

        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }

        /**
         * @description Constructs a new SObjectInfo with label and API name.
         * @param labelStr The display label of the SObject.
         * @param apiNameStr The API name of the SObject.
         */
        public SObjectInfo(String labelStr, String apiNameStr) {

            this.label = labelStr;
            this.apiName = apiNameStr;
        }
    }

    /**
     * @description Retrieves all SObject types in the org, sorted by API name.
     * @return A list of SObjectInfo wrappers containing label and API name.
     */
    @AuraEnabled(cacheable=true)
    public static List<SObjectInfo> getAllSObjectNames() {

        List<SObjectInfo> sObjectInfoList = new List<SObjectInfo>();
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();

        List<String> apiNamesList = new List<String>(globalDescribeMap.keySet());
        apiNamesList.sort();

        for (String apiNameStr : apiNamesList) {

            Schema.DescribeSObjectResult describeResult = globalDescribeMap.get(apiNameStr).getDescribe();

            sObjectInfoList.add(new SObjectInfo(
                describeResult.getLabel(),
                describeResult.getName()
            ));
        }

        return sObjectInfoList;
    }

    /**
     * @description Retrieves all fields for a given SObject, including metadata
     *              about whether each field is required.
     * @param sObjectApiNameStr The API name of the SObject to describe.
     * @return A list of FieldInfoWrapper objects with field metadata.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldInfoWrapper> getFieldsBySObject(String sObjectApiNameStr) {

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(sObjectApiNameStr);
        Schema.DescribeSObjectResult describeResult = objType.getDescribe();
        Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();

        List<FieldInfoWrapper> resultList = new List<FieldInfoWrapper>();

        for (String apiStr : fieldsMap.keySet()) {

            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(apiStr).getDescribe();

            Boolean isRequiredFlag =
                !fieldDescribe.isNillable() &&
                !fieldDescribe.isDefaultedOnCreate() &&
                !fieldDescribe.isCalculated() &&
                apiStr != 'Id';

            resultList.add(new FieldInfoWrapper(
                fieldDescribe.getLabel(),
                fieldDescribe.getName(),
                fieldDescribe.getType().name(),
                isRequiredFlag
            ));
        }

        return resultList;
    }

    /**
     * @description Wrapper class for child relationship information.
     */
    public class ChildRelationshipInfo {

        @AuraEnabled public String childObject { get; set; }
        @AuraEnabled public String relationshipField { get; set; }
        @AuraEnabled public String relationshipName { get; set; }
        @AuraEnabled public String relationshipType { get; set; }
    }

    /**
     * @description Retrieves child relationship details for a parent SObject.
     * @param parentObjectApiNameStr The API name of the parent SObject.
     * @return A list of ChildRelationshipInfo wrappers describing child relationships.
     */
    public static List<ChildRelationshipInfo> getChildObjectDetails(String parentObjectApiNameStr) {

        List<ChildRelationshipInfo> resultsList = new List<ChildRelationshipInfo>();

        Schema.DescribeSObjectResult parentDescribe =
            Schema.getGlobalDescribe().get(parentObjectApiNameStr).getDescribe();

        for (Schema.ChildRelationship childRel : parentDescribe.getChildRelationships()) {

            if (childRel.getRelationshipName() != null && childRel.getChildSObject() != null && childRel.getField() != null) {

                String childApiName = childRel.getChildSObject().getDescribe().getName();

                if (!isRelevantChildObject(childApiName)) {
                    continue;
                }

                Schema.DescribeFieldResult fieldDescribe = childRel.getField().getDescribe();

                ChildRelationshipInfo infoRecord = new ChildRelationshipInfo();
                infoRecord.childObject       = childApiName;
                infoRecord.relationshipField = fieldDescribe.getName();
                infoRecord.relationshipName  = childRel.getRelationshipName();
                infoRecord.relationshipType  = childRel.isCascadeDelete() ? 'Master-Detail' : 'Lookup';

                resultsList.add(infoRecord);
            }
        }

        return resultsList;
    }

    /**
     * @description Wrapper for child records grouped by child object.
     */
    public class ChildRecordsWrapper {

        @AuraEnabled public String childObjectName  { get; set; }
        @AuraEnabled public String childObjectLabel { get; set; }
        @AuraEnabled public String relationshipField { get; set; }
        @AuraEnabled public Integer recordCount     { get; set; }
        @AuraEnabled public List<SObject> records   { get; set; }
    }

    /**
     * @description Retrieves child records for given parent record IDs, grouped by child object.
     * @param parentObjectApiNameStr The API name of the parent SObject.
     * @param parentRecordIdsList List of parent record ID strings.
     * @return A list of ChildRecordsWrapper objects containing child records by object.
     */
    @AuraEnabled
    public static List<ChildRecordsWrapper> getChildRecordsByParentIds(
        String parentObjectApiNameStr,
        List<String> parentRecordIdsList
    ) {

        List<ChildRecordsWrapper> wrappersList = new List<ChildRecordsWrapper>();

        if (String.isBlank(parentObjectApiNameStr) || parentRecordIdsList == null || parentRecordIdsList.isEmpty()) {
            return wrappersList;
        }

        Schema.DescribeSObjectResult parentDescribe =
            Schema.getGlobalDescribe().get(parentObjectApiNameStr).getDescribe();

        for (Schema.ChildRelationship childRel : parentDescribe.getChildRelationships()) {

            if (childRel.getRelationshipName() == null || childRel.getChildSObject() == null || childRel.getField() == null) {
                continue;
            }

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();

            if (!childDescribe.isQueryable() || !childDescribe.isAccessible()) {
                continue;
            }

            String childObjectApiStr   = childDescribe.getName();

            if (!isRelevantChildObject(childObjectApiStr)) {
                continue;
            }

            String childObjectLabelStr = childDescribe.getLabel();
            String lookupFieldApiStr   = childRel.getField().getDescribe().getName();

            Map<String, Schema.SObjectField> childFieldsMap = childDescribe.fields.getMap();
            Boolean hasNameFlag = childFieldsMap.containsKey('Name')
                           && childFieldsMap.get('Name').getDescribe().isAccessible();

            String fieldListStr = hasNameFlag ? 'Id, Name' : 'Id';
            String queryStr = 'SELECT ' + fieldListStr
                         + ' FROM ' + String.escapeSingleQuotes(childObjectApiStr)
                         + ' WHERE ' + String.escapeSingleQuotes(lookupFieldApiStr)
                         + ' IN :parentRecordIdsList'
                         + ' ORDER BY Id'
                         + ' LIMIT 2000';

            try {
                List<SObject> recordsList = Database.query(queryStr);

                if (!recordsList.isEmpty()) {
                    ChildRecordsWrapper wrapper = new ChildRecordsWrapper();
                    wrapper.childObjectName  = childObjectApiStr;
                    wrapper.childObjectLabel = childObjectLabelStr;
                    wrapper.relationshipField = lookupFieldApiStr;
                    wrapper.recordCount      = recordsList.size();
                    wrapper.records          = recordsList;
                    wrappersList.add(wrapper);
                }
            } catch (Exception ex) {
                System.debug('Skipping child object ' + childObjectApiStr + ': ' + ex.getMessage());
            }
        }

        return wrappersList;
    }

    /**
     * @description Wrapper class for field information including label, API name,
     *              field type, and whether the field is required.
     */
    public class FieldInfoWrapper {

        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Boolean isRequired;

        /**
         * @description Constructs a new FieldInfoWrapper.
         * @param labelStr The display label of the field.
         * @param apiNameStr The API name of the field.
         * @param fieldTypeStr The data type of the field.
         * @param isRequiredFlag Whether the field is required.
         */
        public FieldInfoWrapper(String labelStr, String apiNameStr, String fieldTypeStr, Boolean isRequiredFlag) {

            label = labelStr;
            apiName = apiNameStr;
            fieldType = fieldTypeStr;
            isRequired = isRequiredFlag;
        }
    }
}