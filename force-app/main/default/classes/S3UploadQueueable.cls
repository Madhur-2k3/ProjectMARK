public class S3UploadQueueable implements Queueable, Database.AllowsCallouts {
    private List<String> docPairs;

    public S3UploadQueueable(List<String> docPairs) {
        this.docPairs = docPairs == null ? new List<String>() : docPairs;
    }

    public void execute(QueueableContext context) {
        if (docPairs.isEmpty()) return;

        Map<Id, Id> docToParent = new Map<Id, Id>();
        Set<Id> docIds = new Set<Id>();
        for (String p : docPairs) {
            if (String.isBlank(p)) continue;
            Integer sep = p.indexOf('|');
            if (sep > 0 && sep < p.length() - 1) {
                try {
                    String docIdStr = p.substring(0, sep);
                    String parentIdStr = p.substring(sep + 1);
                    Id docId = (Id)docIdStr;
                    Id parentId = (Id)parentIdStr;
                    docToParent.put(docId, parentId);
                    docIds.add(docId);
                } catch (Exception ex) {
                    System.debug('S3UploadQueueable: could not parse pair: ' + p + ' error: ' + ex.getMessage());
                }
            }
        }
        if (docIds.isEmpty()) return;

        List<ContentVersion> cvs = [
            SELECT Id, ContentDocumentId, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
        ];

        for (ContentVersion cv : cvs) {
            try {
                Id parentId = docToParent.get(cv.ContentDocumentId);
                if (parentId == null) continue;
                String fileName = String.valueOf(parentId) + '/' + cv.Title;
                if (cv.FileExtension != null && cv.FileExtension.trim().length() > 0) {
                    fileName += '.' + cv.FileExtension;
                }
                String base64Body = '';
                if (cv.VersionData != null) {
                    base64Body = EncodingUtil.base64Encode(cv.VersionData);
                }
                String contentType = 'application/octet-stream';

                try {
                    String resp = S3Controller.putObjectToS3(fileName, base64Body, contentType);
                    System.debug('S3 upload result for ' + fileName + ': ' + resp);
                } catch (Exception e) {
                    System.debug('S3Controller.putObjectToS3 failed for ' + fileName + ': ' + e.getMessage());
                }
            } catch (Exception ex) {
                System.debug('Error processing ContentVersion ' + cv.Id + ': ' + ex.getMessage());
            }
        }
    }
}