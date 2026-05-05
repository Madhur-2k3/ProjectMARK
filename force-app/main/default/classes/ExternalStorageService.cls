/**
 * Unified Apex controller exposing @AuraEnabled methods for multi-provider external storage.
 * LWCs should call this instead of S3Controller directly.
 */
public with sharing class ExternalStorageService {

    /**
     * Returns all active storage providers for the UI picker.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailableProviders() {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Storage_Provider__mdt p : StorageProviderFactory.getActiveProviders()) {
            result.add(new Map<String, String>{
                'developerName' => p.DeveloperName,
                'label'         => p.MasterLabel,
                'providerType'  => p.Provider_Type__c,
                'iconName'      => String.isBlank(p.Icon_Name__c) ? 'utility:upload' : p.Icon_Name__c,
                'isDefault'     => String.valueOf(p.Is_Default__c)
            });
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static String putObject(String providerName, String filePath, String base64Body, String contentType) {
        return StorageProviderFactory.getProvider(providerName).putObject(filePath, base64Body, contentType);
    }

    @AuraEnabled(cacheable=false)
    public static String getObject(String providerName, String filePath) {
        return StorageProviderFactory.getProvider(providerName).getObject(filePath);
    }

    @AuraEnabled(cacheable=false)
    public static String getObjectAsBase64(String providerName, String filePath) {
        return StorageProviderFactory.getProvider(providerName).getObjectAsBase64(filePath);
    }

    @AuraEnabled(cacheable=false)
    public static String listObjects(String providerName) {
        return StorageProviderFactory.getProvider(providerName).listObjects();
    }

    @AuraEnabled(cacheable=false)
    public static String listObjectsByPrefix(String providerName, String prefix) {
        return StorageProviderFactory.getProvider(providerName).listObjectsByPrefix(prefix);
    }

    /**
     * Fetches a CSV from the given provider and applies FLS filtering based on the running user.
     */
    @AuraEnabled(cacheable=false)
    public static String getFilteredCsv(String providerName, String fileName) {
        String rawCsv = StorageProviderFactory.getProvider(providerName).getObject(fileName);
        if (String.isBlank(rawCsv)) return rawCsv;

        // Extract object name from filename (e.g. "archiveId/Account_Account_-_DA-0001.csv.zip.enc" → "Account")
        String objectName = extractObjectNameFromKey(fileName);
        if (String.isBlank(objectName)) return rawCsv;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) return rawCsv;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        List<String> lines = rawCsv.split('\n');
        if (lines.isEmpty()) return rawCsv;

        List<String> headers = parseCsvLine(lines[0]);
        List<Integer> accessibleIndices = new List<Integer>();
        List<String> accessibleHeaders = new List<String>();
        for (Integer i = 0; i < headers.size(); i++) {
            String fieldName = headers[i].trim();
            String baseField = fieldName.contains('.') ? fieldName.substringBefore('.') : fieldName;
            Schema.SObjectField sField = fieldMap.get(baseField.toLowerCase());
            if (sField == null || sField.getDescribe().isAccessible()) {
                accessibleIndices.add(i);
                accessibleHeaders.add(fieldName);
            }
        }
        if (accessibleIndices.size() == headers.size()) return rawCsv;

        List<String> filteredLines = new List<String>();
        filteredLines.add(String.join(accessibleHeaders, ','));
        for (Integer lineIdx = 1; lineIdx < lines.size(); lineIdx++) {
            String line = lines[lineIdx];
            if (String.isBlank(line)) continue;
            List<String> cells = parseCsvLine(line);
            List<String> filteredCells = new List<String>();
            for (Integer idx : accessibleIndices) {
                filteredCells.add(idx < cells.size() ? escapeCsvField(cells[idx]) : '');
            }
            filteredLines.add(String.join(filteredCells, ','));
        }
        return String.join(filteredLines, '\n');
    }

    // ── Private CSV helpers (mirrors S3Controller logic) ─────────────────────

    private static String extractObjectNameFromKey(String key) {
        if (String.isBlank(key)) return null;
        String fName = key.contains('/') ? key.substringAfterLast('/') : key;
        if (fName.endsWith('.enc')) fName = fName.substringBeforeLast('.');
        if (fName.endsWith('.zip')) fName = fName.substringBeforeLast('.');
        if (fName.contains('.'))    fName = fName.substringBeforeLast('.');
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Integer daIdx = fName.indexOf('_-_DA-');
        if (daIdx > 0) {
            String beforeDA = fName.substring(0, daIdx);
            if (gd.containsKey(beforeDA)) return beforeDA;
            for (String suffix : new List<String>{'__c','__mdt','__e','__b','__x'}) {
                Integer si = beforeDA.indexOf(suffix);
                if (si > 0) {
                    String candidate = beforeDA.substring(0, si + suffix.length());
                    if (gd.containsKey(candidate)) return candidate;
                }
            }
            List<String> segs = beforeDA.split('_');
            if (!segs.isEmpty() && gd.containsKey(segs[0])) return segs[0];
        }
        return gd.containsKey(fName) ? fName : null;
    }

    private static List<String> parseCsvLine(String line) {
        List<String> fields = new List<String>();
        if (String.isBlank(line)) return fields;
        String current = '';
        Boolean inQuotes = false;
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (inQuotes) {
                if (ch == '"') {
                    if (i + 1 < line.length() && line.substring(i+1,i+2) == '"') { current += '"'; i++; }
                    else { inQuotes = false; }
                } else { current += ch; }
            } else {
                if (ch == '"') { inQuotes = true; }
                else if (ch == ',') { fields.add(current.trim()); current = ''; }
                else if (ch != '\r') { current += ch; }
            }
        }
        fields.add(current.trim());
        return fields;
    }

    private static String escapeCsvField(String value) {
        if (String.isBlank(value)) return value;
        if (value.contains(',') || value.contains('"') || value.contains('\n')) {
            return '"' + value.replace('"', '""') + '"';
        }
        return value;
    }
}
