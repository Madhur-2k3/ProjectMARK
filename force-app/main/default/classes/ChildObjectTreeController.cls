/**
 * @description Controller that discovers child object relationships recursively
 *              for a given parent SObject. Used to build a tree of related child
 *              objects in the UI for archive configuration.
 */
public with sharing class ChildObjectTreeController {

    /**
     * @description Wrapper class representing a node in the child object tree.
     */
    public class ChildNode {

        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String relationshipName;
        @AuraEnabled public String lookupField;
        @AuraEnabled public String relationshipType;
        @AuraEnabled public List<ChildNode> children;

        /**
         * @description Constructs a new ChildNode.
         * @param objectApiNameStr API name of the child object.
         * @param objectLabelStr Display label of the child object.
         * @param relationshipNameStr The relationship name.
         * @param lookupFieldStr The lookup field API name.
         */
        public ChildNode(String objectApiNameStr, String objectLabelStr, String relationshipNameStr, String lookupFieldStr, String relationshipTypeStr) {

            this.objectApiName = objectApiNameStr;
            this.objectLabel = objectLabelStr;
            this.relationshipName = relationshipNameStr;
            this.lookupField = lookupFieldStr;
            this.relationshipType = relationshipTypeStr;
            this.children = new List<ChildNode>();
        }
    }

    /**
     * @description Retrieves the child object tree for a parent SObject up to
     *              the specified depth.
     * @param parentObjectStr The API name of the parent SObject.
     * @param maxDepthInt The maximum recursion depth for child discovery.
     * @return A list of ChildNode trees representing child relationships.
     */
    @AuraEnabled(cacheable=true)
    public static List<ChildNode> getChildObjectTree(String parentObjectStr, Integer maxDepthInt) {

        if (maxDepthInt == null || maxDepthInt <= 0) {
            maxDepthInt = 2;
        }

        Set<String> visitedSet = new Set<String>();
        return buildTree(parentObjectStr, maxDepthInt, 0, visitedSet);
    }

    /**
     * @description Recursively builds the child object tree.
     * @param objectNameStr The API name of the current object.
     * @param maxDepthInt Maximum recursion depth.
     * @param currentDepthInt Current recursion depth.
     * @param visitedSet Set of already-visited object names to prevent cycles.
     * @return A list of ChildNode objects for the current level.
     */
    private static List<ChildNode> buildTree(
        String objectNameStr,
        Integer maxDepthInt,
        Integer currentDepthInt,
        Set<String> visitedSet
    ) {

        List<ChildNode> nodesList = new List<ChildNode>();

        if (currentDepthInt >= maxDepthInt) return nodesList;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectNameStr);
        if (objType == null) return nodesList;

        visitedSet.add(objectNameStr);

        for (Schema.ChildRelationship childRel : objType.getDescribe().getChildRelationships()) {

            if (childRel.getRelationshipName() == null) continue;

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            String childApiNameStr = childDescribe.getName();

            if (visitedSet.contains(childApiNameStr)) continue;

            if (!childDescribe.isQueryable() || !childDescribe.isAccessible()) continue;

            if (!sObjectsController.isRelevantChildObject(childApiNameStr)) continue;

            String childLabelStr = childDescribe.getLabel();
            String relNameStr = childRel.getRelationshipName();
            String lookupFieldStr = childRel.getField().getDescribe().getName();
            String relTypeStr = childRel.isCascadeDelete() ? 'Master-Detail' : 'Lookup';

            ChildNode node = new ChildNode(childApiNameStr, childLabelStr, relNameStr, lookupFieldStr, relTypeStr);

            node.children = buildTree(childApiNameStr, maxDepthInt, currentDepthInt + 1, visitedSet);

            nodesList.add(node);
        }

        visitedSet.remove(objectNameStr);

        return nodesList;
    }
}