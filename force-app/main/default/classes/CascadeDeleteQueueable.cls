public class CascadeDeleteQueueable implements Queueable {

    private String parentObjectApi;
    private List<Id> parentIds;

    public CascadeDeleteQueueable(
        String parentObjectApi,
        List<Id> parentIds
    ) {
        this.parentObjectApi = parentObjectApi;
        this.parentIds = parentIds;
    }

    public void execute(QueueableContext context) {
        CascadeDeleteHelper.deleteParentWithRelations(
            parentObjectApi,
            parentIds
        );
    }
}