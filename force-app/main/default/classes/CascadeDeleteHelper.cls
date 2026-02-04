// public with sharing class CascadeDeleteHelper {

//     public static void deleteParentWithRelations(
//         String parentObjectApi,
//         List<Id> parentIds
//     ) {
//         if (parentIds == null || parentIds.isEmpty()) return;

//         Schema.SObjectType parentType =
//             Schema.getGlobalDescribe().get(parentObjectApi);

//         if (parentType == null) return;

//         // 🔥 DELETE CHILDREN FIRST (INCLUDING CASES, OPPS, ETC.)
//         deleteChildrenRecursive(
//             parentType.getDescribe(),
//             parentIds,
//             new Set<String>()
//         );

//         // 🔥 DELETE PARENT LAST
//         delete Database.query(
//             'SELECT Id FROM ' + parentObjectApi +
//             ' WHERE Id IN (' + buildInClause(parentIds) + ')'
//         );
//     }

//     // ===================================================
//     // RECURSIVE CHILD DELETE (AUTO MODE)
//     // ===================================================
//     private static void deleteChildrenRecursive(
//         Schema.DescribeSObjectResult parentDescribe,
//         List<Id> parentIds,
//         Set<String> visited
//     ) {
//         for (Schema.ChildRelationship cr :
//              parentDescribe.getChildRelationships()) {

//             if (cr.isCascadeDelete()) continue;
//             if (cr.getChildSObject() == null ||
//                 cr.getField() == null ||
//                 cr.getRelationshipName() == null) continue;

//             Schema.DescribeSObjectResult childDescribe =
//                 cr.getChildSObject().getDescribe();

//             String childObject = childDescribe.getName();

//             if (visited.contains(childObject)) continue;
//             visited.add(childObject);

//             if (!childDescribe.isQueryable() ||
//                 !childDescribe.isDeletable()) continue;

//             String fk = cr.getField().getDescribe().getName();

//             String soql =
//                 'SELECT Id FROM ' + childObject +
//                 ' WHERE ' + fk +
//                 ' IN (' + buildInClause(parentIds) + ')';

//             List<SObject> children;
//             try {
//                 children = Database.query(soql);
//             } catch (Exception e) {
//                 continue;
//             }

//             if (children.isEmpty()) continue;

//             List<Id> childIds = new List<Id>();
//             for (SObject s : children) childIds.add(s.Id);

//             // 🔁 DELETE DEEPER LEVELS FIRST
//             deleteChildrenRecursive(
//                 childDescribe,
//                 childIds,
//                 visited
//             );

//             delete children;
//             // Database.delete(children,false);
//         }
//     }

//     private static String buildInClause(List<Id> ids) {
//         List<String> q = new List<String>();
//         for (Id i : ids) {
//             q.add('\'' + String.escapeSingleQuotes(i) + '\'');
//         }
//         return String.join(q, ',');
//     }
// }

public with sharing class CascadeDeleteHelper {

    public static void deleteParentWithRelations(
        String parentObjectApi,
        List<Id> parentIds
    ) {
        if (parentIds == null || parentIds.isEmpty()) return;

        Schema.SObjectType parentType =
            Schema.getGlobalDescribe().get(parentObjectApi);

        if (parentType == null) return;

        deleteChildrenRecursive(
            parentType.getDescribe(),
            parentIds,
            new Set<String>()
        );

        delete Database.query(
            'SELECT Id FROM ' + parentObjectApi +
            ' WHERE Id IN (' + buildInClause(parentIds) + ')'
        );
    }

    // ===================================================
    // RECURSIVE CHILD DELETE (AUTO MODE)
    // ===================================================
    private static void deleteChildrenRecursive(
        Schema.DescribeSObjectResult parentDescribe,
        List<Id> parentIds,
        Set<String> visited
    ) {
        for (Schema.ChildRelationship cr :
             parentDescribe.getChildRelationships()) {

            if (cr.isCascadeDelete()) continue;
            if (cr.getChildSObject() == null ||
                cr.getField() == null ||
                cr.getRelationshipName() == null) continue;

            Schema.DescribeSObjectResult childDescribe =
                cr.getChildSObject().getDescribe();

            String childObject = childDescribe.getName();
            if (visited.contains(childObject)) continue;
            visited.add(childObject);

            if (!childDescribe.isQueryable() ||
                !childDescribe.isDeletable()) continue;

            String fk = cr.getField().getDescribe().getName();

            List<SObject> children;
            try {
                children = Database.query(
                    'SELECT Id FROM ' + childObject +
                    ' WHERE ' + fk +
                    ' IN (' + buildInClause(parentIds) + ')'
                );
            } catch (Exception e) {
                continue;
            }

            if (children.isEmpty()) continue;

            List<Id> childIds = new List<Id>();
            for (SObject s : children) childIds.add(s.Id);

            // 🔁 DELETE DEEPER LEVELS FIRST
            deleteChildrenRecursive(
                childDescribe,
                childIds,
                visited
            );

            delete children;
        }
    }

    private static String buildInClause(List<Id> ids) {
        List<String> q = new List<String>();
        for (Id i : ids)
            q.add('\'' + String.escapeSingleQuotes(i) + '\'');
        return String.join(q, ',');
    }
}