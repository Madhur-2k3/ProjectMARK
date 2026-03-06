public with sharing class ChildObjectTreeController {

    /* =====================================================
     *   WRAPPER — represents one node in the child tree
     * ===================================================== */
    public class ChildNode {
        @AuraEnabled public String       objectName;
        @AuraEnabled public String       objectLabel;
        @AuraEnabled public String       relationshipField;
        @AuraEnabled public String       parentObjectName;
        @AuraEnabled public Integer      depth;
        @AuraEnabled public Boolean      isSelected;
        @AuraEnabled public List<ChildNode> children;

        public ChildNode(String objectName, String objectLabel,
                         String relationshipField, String parentObjectName,
                         Integer depth) {
            this.objectName        = objectName;
            this.objectLabel       = objectLabel;
            this.relationshipField = relationshipField;
            this.parentObjectName  = parentObjectName;
            this.depth             = depth;
            this.isSelected        = true;
            this.children          = new List<ChildNode>();
        }
    }

    /* =====================================================
     *   PUBLIC API — returns the full child tree for an object
     * ===================================================== */
    @AuraEnabled(cacheable=true)
    public static List<ChildNode> getChildObjectTree(String objectName) {
        if (String.isBlank(objectName) ||
            !Schema.getGlobalDescribe().containsKey(objectName)) {
            return new List<ChildNode>();
        }

        Set<String> visited = new Set<String>();
        visited.add(objectName); // prevent root from appearing as its own child

        return discoverChildren(objectName, 1, visited);
    }

    /* =====================================================
     *   SYSTEM OBJECT SUFFIXES TO SKIP
     * ===================================================== */
    private static final Set<String> SKIP_SUFFIXES = new Set<String>{
        'Share', 'History', 'Feed', 'ChangeEvent',
        'CleanInfo', 'ContactRole', 'Partner',
        'Tag', 'Insight', 'FieldHistory',
        'OwnerSharingRule', 'TeamMember'
    };

    /* =====================================================
     *   SPECIFIC SYSTEM OBJECTS TO SKIP
     * ===================================================== */
    private static final Set<String> SKIP_OBJECTS = new Set<String>{
        // Attachments & Content
        'Attachment', 'ContentDocumentLink', 'Note', 'CombinedAttachment',
        // Process / Approval
        'ProcessInstance', 'ProcessInstanceNode',
        'ProcessInstanceStep', 'ProcessInstanceWorkitem',
        'ProcessInstanceHistory', 'FlowRecordRelation',
        // Collaboration / Topics
        'CollaborationGroupRecord', 'TopicAssignment',
        'EntitySubscription', 'FeedComment', 'FeedItem',
        // Duplicates / Data quality
        'DuplicateRecordItem',
        // Usage / Analytics
        'AppUsageAssignment',
        // Actions
        'ActionPlan', 'ActionPlanItem',
        // Sharing / Access
        'UserRecordAccess',
        // Email
        'EmailMessage', 'EmailMessageRelation',
        // Asset system children
        'AssetAction', 'AssetActionSource', 'AssetStatePeriod',
        'AssetRelationship',
        // Other platform objects
        'NetworkActivityAudit', 'AuthorizationFormConsent',
        'FinanceBalanceSnapshot', 'FinanceTransaction',
        'RecordAction', 'RecordActionHistory',
        'WorkOrder', 'WorkOrderLineItem',
        'ActivityHistory', 'OpenActivity'
    };

    /* =====================================================
     *   RECURSIVE DISCOVERY
     *   — only follows master-detail (cascade-delete) rels
     *   — skips system objects automatically
     *   — max depth = 5
     * ===================================================== */
    private static List<ChildNode> discoverChildren(String parentObjName,
                                                     Integer depth,
                                                     Set<String> visited) {
        List<ChildNode> nodes = new List<ChildNode>();
        if (depth > 5) return nodes;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(parentObjName);
        if (objType == null) return nodes;

        List<Schema.ChildRelationship> childRels =
            objType.getDescribe().getChildRelationships();

        for (Schema.ChildRelationship childRel : childRels) {

            // Only master-detail (cascade-delete)
            if (!childRel.isCascadeDelete()) continue;

            Schema.DescribeSObjectResult childDescribe =
                childRel.getChildSObject().getDescribe();
            String childObjectName   = childDescribe.getName();
            String relationshipField = childRel.getField().getDescribe().getName();
            String relationshipName  = childRel.getRelationshipName();

            // Skip if no relationship name
            if (relationshipName == null) continue;

            // Skip duplicates / loops
            if (visited.contains(childObjectName)) continue;

            // Skip explicitly blocked objects
            if (SKIP_OBJECTS.contains(childObjectName)) continue;

            // Skip by suffix pattern
            if (isSystemSuffix(childObjectName)) continue;

            // Skip inaccessible / non-queryable / non-custom-and-non-standard-data
            if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) continue;

            // Mark visited BEFORE recursing to prevent infinite loops
            visited.add(childObjectName);

            ChildNode node = new ChildNode(
                childObjectName,
                childDescribe.getLabel(),
                relationshipField,
                parentObjName,
                depth
            );

            // Recurse into children
            node.children = discoverChildren(childObjectName, depth + 1, visited);

            nodes.add(node);
        }

        return nodes;
    }

    /* =====================================================
     *   SUFFIX CHECK
     * ===================================================== */
    private static Boolean isSystemSuffix(String objectName) {
        for (String suffix : SKIP_SUFFIXES) {
            if (objectName.endsWith(suffix)) return true;
        }
        return false;
    }
}