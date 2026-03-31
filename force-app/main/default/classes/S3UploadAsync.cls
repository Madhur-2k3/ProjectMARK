/**
 * @description Asynchronous (@future) utility class for uploading ContentVersion
 *              files to AWS S3 via callouts. Used as a fallback when Queueable
 *              cannot be enqueued (e.g., already in an async context).
 */
public class S3UploadAsync {

    /**
     * @description Uploads ContentVersion files to S3 using the provided document-parent pairs.
     *              Each pair is a pipe-delimited string: "ContentDocumentId|ParentRecordId".
     * @param docPairsList List of pipe-delimited ContentDocumentId|ParentRecordId strings.
     */
    @future(callout=true)
    public static void upload(List<String> docPairsList) {

        if (docPairsList == null || docPairsList.isEmpty()) return;

        Map<Id, Id> docToParentMap = new Map<Id, Id>();
        Set<Id> docIdSet = new Set<Id>();

        for (String currentPairStr : docPairsList) {

            if (String.isBlank(currentPairStr)) continue;

            Integer separatorInt = currentPairStr.indexOf('|');

            if (separatorInt > 0 && separatorInt < currentPairStr.length() - 1) {
                try {
                    String docIdStr = currentPairStr.substring(0, separatorInt);
                    String parentIdStr = currentPairStr.substring(separatorInt + 1);
                    Id docId = (Id) docIdStr;
                    Id parentId = (Id) parentIdStr;
                    docToParentMap.put(docId, parentId);
                    docIdSet.add(docId);
                } catch (Exception ex) {
                    System.debug('S3UploadAsync: could not parse pair: ' + currentPairStr + ' error: ' + ex.getMessage());
                }
            }
        }

        if (docIdSet.isEmpty()) return;

        List<ContentVersion> contentVersionsList = [
            SELECT Id, ContentDocumentId, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIdSet AND IsLatest = true
        ];

        for (ContentVersion currentVersion : contentVersionsList) {

            try {
                Id parentId = docToParentMap.get(currentVersion.ContentDocumentId);
                if (parentId == null) continue;

                String fileNameStr = String.valueOf(parentId) + '/' + currentVersion.Title;

                if (currentVersion.FileExtension != null && currentVersion.FileExtension.trim().length() > 0) {
                    fileNameStr += '.' + currentVersion.FileExtension;
                }

                String base64BodyStr = '';

                if (currentVersion.VersionData != null) {
                    base64BodyStr = EncodingUtil.base64Encode(currentVersion.VersionData);
                }

                String contentTypeStr = 'application/octet-stream';

                try {
                    String responseStr = S3Controller.putObjectToS3(fileNameStr, base64BodyStr, contentTypeStr);
                    System.debug('S3 upload result for ' + fileNameStr + ': ' + responseStr);
                } catch (Exception uploadException) {
                    System.debug('S3Controller.putObjectToS3 failed for ' + fileNameStr + ': ' + uploadException.getMessage());
                }
            } catch (Exception outerException) {
                System.debug('Error processing ContentVersion ' + currentVersion.Id + ': ' + outerException.getMessage());
            }
        }
    }
}