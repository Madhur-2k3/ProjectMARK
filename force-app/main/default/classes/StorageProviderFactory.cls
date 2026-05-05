/**
 * Factory for instantiating IExternalStorageProvider implementations
 * based on Storage_Provider__mdt custom metadata configuration.
 */
public class StorageProviderFactory {

    /**
     * Get a specific provider by its Custom Metadata DeveloperName.
     * Throws StorageProviderException if not found or inactive.
     */
    public static IExternalStorageProvider getProvider(String providerDevName) {
        Storage_Provider__mdt config = Storage_Provider__mdt.getInstance(providerDevName);
        if (config == null || !config.Is_Active__c) {
            throw new StorageProviderException(
                'Storage provider not found or inactive: ' + providerDevName
            );
        }
        return buildProvider(config);
    }

    /**
     * Get the org-wide default provider (Is_Default__c = true).
     * Throws StorageProviderException with a clear message if none is configured.
     */
    public static IExternalStorageProvider getDefaultProvider() {
        List<Storage_Provider__mdt> defaults = [
            SELECT DeveloperName, Named_Credential__c, Provider_Type__c,
                   Is_Active__c, Is_Default__c, Base_Path__c
            FROM Storage_Provider__mdt
            WHERE Is_Active__c = true AND Is_Default__c = true
            LIMIT 1
        ];
        if (defaults.isEmpty()) {
            throw new StorageProviderException(
                'No default storage provider configured. '
                + 'Please set Is_Default__c = true on a Storage_Provider__mdt record.'
            );
        }
        return buildProvider(defaults[0]);
    }

    /**
     * Returns all active CMDT records (used by ExternalStorageService.getAvailableProviders).
     */
    public static List<Storage_Provider__mdt> getActiveProviders() {
        return [
            SELECT DeveloperName, MasterLabel, Named_Credential__c, Provider_Type__c,
                   Is_Active__c, Is_Default__c, Icon_Name__c, Base_Path__c, Max_File_Size_MB__c
            FROM Storage_Provider__mdt
            WHERE Is_Active__c = true
            ORDER BY MasterLabel ASC
        ];
    }

    // ── Private ──────────────────────────────────────────────────────────────

    private static IExternalStorageProvider buildProvider(Storage_Provider__mdt config) {
        switch on config.Provider_Type__c {
            when 'S3' {
                return new S3StorageProvider(config.Named_Credential__c, config.Base_Path__c);
            }
            when 'Google_Drive' {
                return new GoogleDriveStorageProvider(config.Named_Credential__c, config.Base_Path__c);
            }
            when else {
                throw new StorageProviderException(
                    'Unsupported provider type: ' + config.Provider_Type__c
                );
            }
        }
    }
}
