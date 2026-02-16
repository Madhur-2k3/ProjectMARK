public with sharing class DataArchiveScheduler implements Schedulable {

    private String objectName;
    private String fieldsCsv;
    private String soqlQuery;

    public DataArchiveScheduler(
        String objectName,
        String fieldsCsv,
        String soqlQuery
    ){
        this.objectName = objectName;
        this.fieldsCsv = fieldsCsv;
        this.soqlQuery = soqlQuery;
    }

    public void execute(SchedulableContext sc) {

        DataArchiveBatch batch =
            new DataArchiveBatch(objectName, fieldsCsv, soqlQuery);

        Database.executeBatch(batch, 200);
    }
}