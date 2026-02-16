public with sharing class CascadeDeleteHelper {

    public static void deleteParentWithRelations(
        String parentObjectApi,
        List<Id> parentIds
    ) {
        if (parentIds == null || parentIds.isEmpty()) return;

        if (!Schema.getGlobalDescribe().containsKey(parentObjectApi)) return;

        // ONLY delete parents
        // Master-Detail children will auto-delete
        Database.delete(Database.query(
            'SELECT Id FROM ' + parentObjectApi +
            ' WHERE Id IN (' + buildInClause(parentIds) + ')'
        ), false);
    }

    private static String buildInClause(List<Id> ids) {
        List<String> q = new List<String>();
        for (Id i : ids) {
            q.add('\'' + String.escapeSingleQuotes(i) + '\'');
        }
        return String.join(q, ',');
    }
}