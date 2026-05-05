/**
 * Strategy interface for all external storage providers (S3, Google Drive, SharePoint, etc.)
 * Each provider implements this interface and is instantiated via StorageProviderFactory.
 */
public interface IExternalStorageProvider {

    /**
     * Upload a file to the storage provider.
     * @param filePath  Provider-relative path (e.g. "archiveId/filename.csv.zip.enc")
     * @param base64Body  Base64-encoded file content
     * @param contentType  MIME type (e.g. "application/octet-stream")
     * @return  Provider response / confirmation string
     */
    String putObject(String filePath, String base64Body, String contentType);

    /**
     * Download a file as a raw string.
     * @param filePath  Provider-relative path
     * @return  File content as String
     */
    String getObject(String filePath);

    /**
     * Download a file as a base64-encoded string.
     * @param filePath  Provider-relative path
     * @return  Base64-encoded file content
     */
    String getObjectAsBase64(String filePath);

    /**
     * List all objects at the root / configured folder.
     * @return  JSON array string of [{Key, Size, LastModified}]
     */
    String listObjects();

    /**
     * List objects under a specific path prefix (e.g. all files for one archive).
     * @param prefix  Folder prefix / archive record Id
     * @return  JSON array string of [{Key, Size, LastModified}]
     */
    String listObjectsByPrefix(String prefix);

    /**
     * Returns the provider type identifier matching Storage_Provider__mdt.Provider_Type__c
     * e.g. "S3", "Google_Drive", "SharePoint"
     */
    String getProviderType();
}
