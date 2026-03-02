/**
 * RichTextImageHandler
 * Utility class for extracting images from Rich Text HTML,
 * uploading them to S3, and rewriting HTML with S3 URLs.
 */
public class RichTextImageHandler {

    /**
     * Returns the set of field names (from the given list) that are Rich Text Area type
     * for the specified object.
     */
    public static Set<String> getRichTextFieldNames(String objectName, List<String> fields) {
        Set<String> richTextFields = new Set<String>();

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) return richTextFields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String fieldName : fields) {
            // Skip relationship fields (e.g. Account.Name)
            if (fieldName.contains('.')) continue;

            Schema.SObjectField sField = fieldMap.get(fieldName.toLowerCase());
            if (sField != null) {
                Schema.DisplayType fieldType = sField.getDescribe().getType();
                if (fieldType == Schema.DisplayType.TextArea) {
                    // TextArea covers both plain and rich text; check isHtmlFormatted
                    if (sField.getDescribe().isHtmlFormatted()) {
                        richTextFields.add(fieldName);
                    }
                }
            }
        }

        System.debug('RichTextImageHandler: Rich Text fields for ' + objectName + ': ' + richTextFields);
        return richTextFields;
    }

    /**
     * Processes a Rich Text HTML value:
     * - Finds all <img src="..."> tags
     * - For Salesforce internal URLs (/servlet/rtaImage, /file-asset/, etc.),
     *   downloads the image and uploads to S3
     * - Replaces src URLs with S3 public URLs
     * - Returns the modified HTML
     *
     * @param html       The Rich Text HTML string
     * @param s3Prefix   S3 key prefix, e.g. "archives/DA-00001/images"
     * @param recordId   The record ID (used for unique S3 key naming)
     * @param fieldName  The field name (used for unique S3 key naming)
     * @return Modified HTML with S3 URLs, or original HTML if no images found
     */
    public static String processRichTextValue(String html, String s3Prefix, String recordId, String fieldName) {
        if (String.isBlank(html) || !html.containsIgnoreCase('<img')) {
            return html;
        }

        String modifiedHtml = html;
        Integer imgIndex = 0;

        // Find all img src attributes using simple string parsing
        // Pattern: src="..." or src='...'
        String searchStr = modifiedHtml;
        Integer startPos = 0;

        while (true) {
            // Check callout limits before each image
            if (Limits.getCallouts() + 2 > Limits.getLimitCallouts()) {
                System.debug('RichTextImageHandler: Approaching callout limit (' 
                    + Limits.getCallouts() + '/' + Limits.getLimitCallouts() 
                    + '), stopping image processing');
                break;
            }

            Integer imgTagStart = searchStr.indexOfIgnoreCase('<img', startPos);
            if (imgTagStart == -1) break;

            Integer srcStart = searchStr.indexOfIgnoreCase('src=', imgTagStart);
            if (srcStart == -1) break;

            // Determine quote character (double or single)
            Integer quoteStart = srcStart + 4; // after 'src='
            if (quoteStart >= searchStr.length()) break;

            String quoteChar = searchStr.substring(quoteStart, quoteStart + 1);
            if (quoteChar != '"' && quoteChar != '\'') {
                startPos = quoteStart;
                continue;
            }

            Integer urlStart = quoteStart + 1;
            Integer urlEnd = searchStr.indexOf(quoteChar, urlStart);
            if (urlEnd == -1) break;

            String imageUrl = searchStr.substring(urlStart, urlEnd);

            // Only process Salesforce internal URLs
            if (isSalesforceInternalUrl(imageUrl)) {
                System.debug('RichTextImageHandler: Processing SF image: ' + imageUrl);

                try {
                    // Download image from Salesforce
                    Blob imageBlob = downloadImageFromSalesforce(imageUrl);

                    if (imageBlob != null) {
                        // Determine file extension from URL or default to png
                        String extension = guessExtensionFromUrl(imageUrl);

                        // Build S3 key
                        String s3Key = s3Prefix + '/' + fieldName + '_' + recordId + '_' + imgIndex + '.' + extension;

                        // Upload to S3
                        String base64Body = EncodingUtil.base64Encode(imageBlob);
                        String contentType = 'image/' + extension;

                        S3Controller.putObjectToS3(s3Key, base64Body, contentType);
                        System.debug('RichTextImageHandler: Uploaded to S3: ' + s3Key);

                        // Build S3 URL - using the named credential endpoint pattern
                        // The URL format depends on your S3 bucket setup
                        String s3Url = getS3PublicUrl(s3Key);

                        // Replace the original URL with S3 URL in the HTML
                        modifiedHtml = modifiedHtml.replace(imageUrl, s3Url);
                        // Update searchStr too since we modified modifiedHtml
                        searchStr = modifiedHtml;

                        imgIndex++;
                    }
                } catch (Exception e) {
                    System.debug('RichTextImageHandler: Error processing image: ' + e.getMessage());
                    System.debug('Stack: ' + e.getStackTraceString());
                    // Continue with next image, don't break the entire process
                }
            }

            startPos = urlEnd + 1;
            // Prevent infinite loop if searchStr changed
            if (startPos >= searchStr.length()) break;
        }

        return modifiedHtml;
    }

    /**
     * Checks if a URL is a Salesforce internal image URL that will break after record deletion.
     */
    private static Boolean isSalesforceInternalUrl(String url) {
        if (String.isBlank(url)) return false;

        // Salesforce Rich Text internal image patterns
        return url.containsIgnoreCase('/servlet/rtaImage') ||
               url.containsIgnoreCase('/file-asset/') ||
               url.containsIgnoreCase('/sfc/servlet.shepherd') ||
               url.containsIgnoreCase('content/id/') ||
               url.containsIgnoreCase('.force.com/') ||
               url.containsIgnoreCase('.salesforce.com/') ||
               url.startsWith('/');
    }

    /**
     * Downloads an image from Salesforce using an HTTP callout.
     * Handles both absolute and relative URLs.
     */
    private static Blob downloadImageFromSalesforce(String imageUrl) {
        String fullUrl = imageUrl;

        // If relative URL, prepend the Salesforce instance URL
        if (imageUrl.startsWith('/')) {
            fullUrl = URL.getOrgDomainUrl().toExternalForm() + imageUrl;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(fullUrl);
        req.setMethod('GET');

        // Use session ID for authentication
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Accept', '*/*');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            return res.getBodyAsBlob();
        } else if (res.getStatusCode() == 301 || res.getStatusCode() == 302) {
            // Follow redirect
            String redirectUrl = res.getHeader('Location');
            if (String.isNotBlank(redirectUrl)) {
                return downloadImageFromSalesforce(redirectUrl);
            }
        }

        System.debug('RichTextImageHandler: Failed to download image. Status: ' 
            + res.getStatusCode() + ' URL: ' + fullUrl);
        return null;
    }

    /**
     * Constructs a public S3 URL for a given S3 key.
     * Uses the Named Credential endpoint to derive the bucket URL.
     */
    private static String getS3PublicUrl(String s3Key) {
        // Build the S3 URL by extracting bucket info from Named Credential
        // The named credential 'aws_s3' points to the bucket
        // We need to construct a public-accessible URL
        //
        // Common S3 URL formats:
        // https://bucket-name.s3.region.amazonaws.com/key
        // https://s3.region.amazonaws.com/bucket-name/key
        //
        // Since we're using named credentials 'callout:aws_s3',
        // we'll store just the S3 key path and reconstruct later.
        // For now, use a relative S3 reference that the unarchive can resolve.
        //
        // For Option B (keep S3 URLs), we need a publicly accessible URL.
        // This requires the S3 bucket to have public read or a CloudFront distribution.
        //
        // We'll use the S3 key as-is and let the admin configure the bucket URL
        // via a Custom Metadata Type or Custom Setting. For now, hardcode pattern.

        // Try to get bucket URL from custom metadata/label, fallback to key reference
        String bucketUrl = getBucketBaseUrl();
        if (String.isNotBlank(bucketUrl)) {
            if (!bucketUrl.endsWith('/')) bucketUrl += '/';
            return bucketUrl + s3Key;
        }

        // Fallback: store as S3 key reference (will need bucket URL configured later)
        return 's3://' + s3Key;
    }

    /**
     * Gets the S3 bucket base URL.
     * Override this to use Custom Metadata or Custom Settings.
     */
    private static String getBucketBaseUrl() {
        // TODO: Make this configurable via Custom Metadata Type
        // For now, try to read from a Custom Label if it exists
        try {
            return System.Label.S3_Bucket_URL;
        } catch (Exception e) {
            System.debug('RichTextImageHandler: S3_Bucket_URL label not found. Using s3:// prefix.');
            return null;
        }
    }

    /**
     * Guesses file extension from URL. Defaults to 'png'.
     */
    private static String guessExtensionFromUrl(String url) {
        if (String.isBlank(url)) return 'png';

        // Check common image extensions in URL
        String lower = url.toLowerCase();
        if (lower.contains('.jpg') || lower.contains('.jpeg')) return 'jpg';
        if (lower.contains('.png')) return 'png';
        if (lower.contains('.gif')) return 'gif';
        if (lower.contains('.webp')) return 'webp';
        if (lower.contains('.svg')) return 'svg';
        if (lower.contains('.bmp')) return 'bmp';

        // Default
        return 'png';
    }
}