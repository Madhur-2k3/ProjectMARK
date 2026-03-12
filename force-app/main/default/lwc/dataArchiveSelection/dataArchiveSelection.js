import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import scheduleArchive
    from '@salesforce/apex/DataArchiveScheduleController.scheduleArchive';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';

export default class DataArchiveSelection extends NavigationMixin(LightningElement) {

    booleanFlag = true;     // Archive default ON
    unArchiveFlag = false;


    // Modal Flags
    showScheduleModal = false;
    showCriteriaModal = false;
    showObjectModal = false;
    showChildObjectModal = false;

    // Store selections
    selectedFrequency;
    selectedCriteria;
    selectedObject;
    scheduleName;
    selectedChildObjects;

    get archiveClass() {
        return this.booleanFlag
            ? 'toggle-btn active'
            : 'toggle-btn';
    }

    get unArchiveClass() {
        return this.unArchiveFlag
            ? 'toggle-btn active'
            : 'toggle-btn';
    }
    get instructionTitle() {
        return this.booleanFlag ? 'How to Archive Data?' : 'How to Un-Archive Data?'
    }
    get instructions() {
        return this.booleanFlag
            ? [
                '1. Select the Salesforce object you want to archive.',
                '2. Choose the fields that should be included in the archive.',
                '3. Apply filters to narrow down records, or select All Records.',
                '4. Preview the records to verify the data before proceeding.',
                '5. Click Confirm Archive to start the process.',
                '6. The selected records are exported into an Excel file.',
                '7. The Excel file is securely stored and linked to a Data Archive record.',
                '8. Once the archive is successful, the original Salesforce records are deleted.',
                '9. Archived data remains recoverable and can be restored at any time.'
            ]
            : [
                '1. Open Un-Archive mode from the Data Archive Console.',
                '2. View the list of archived data sets available for restoration.',
                '3. Select the archived record you want to restore.',
                '4. Click Un-Archive to initiate the restore process.',
                '5. The archive status changes from Ready for Un-Archive to In Progress.',
                '6. The linked Excel file is downloaded and read automatically.',
                '7. Salesforce records are recreated using the archived data.',
                '8. All restored records are inserted back into Salesforce.',
                '9. After successful restoration, the archive record status is updated to Completed.'
            ];
    }

    activateArchive() {
        this.booleanFlag = true;
        this.unArchiveFlag = false;
    }

    activateUnArchive() {
        this.booleanFlag = false;
        this.unArchiveFlag = true;
    }


    // Open first modal (Object selection)
    openScheduleModal() {
        this.showObjectModal = true;
    }

    // Object selected → open Criteria modal
    handleObjectSelected(event) {
        this.selectedObject = event.detail;
        this.showObjectModal = false;
        this.showCriteriaModal = true;
    }

    // Criteria selected → open Child Object selection modal
    handleCriteriaSelected(event) {
        this.selectedCriteria = event.detail;
        this.scheduleName = event.detail.scheduleName;
        this.showCriteriaModal = false;
        this.showChildObjectModal = true;
    }

    // Child objects selected → open Frequency modal
    handleChildObjectsSelected(event) {
        this.selectedChildObjects = event.detail.selectedChildObjects;
        this.showChildObjectModal = false;
        this.showScheduleModal = true;
    }

    // Previous from Child Object → back to Criteria modal
    handleChildObjectPrevious() {
        this.showChildObjectModal = false;
        this.showCriteriaModal = true;
    }

    // Previous from Criteria → back to Object modal
    handleCriteriaPrevious() {
        this.showCriteriaModal = false;
        this.showObjectModal = true;
    }

    // Previous from Frequency → back to Child Object modal
    handleFrequencyPrevious() {
        this.showScheduleModal = false;
        this.showChildObjectModal = true;
    }

    // Frequency selected and scheduling complete
    handleScheduleComplete(event) {

        const scheduleData = event.detail;

        scheduleArchive({
            objectName: scheduleData.object,
            frequency: scheduleData.frequency,
            dateField: scheduleData.criteria.whereClause || 'FilterCriteria',
            days: 0,
            filterValue: scheduleData.criteria.whereClause,
            preferredTime: scheduleData.preferredTime,
            dayOfWeek: scheduleData.dayOfWeek,
            scheduleName: scheduleData.scheduleName,
            selectedChildObjects: scheduleData.selectedChildObjects
        })
            .then(recordId => {

                // Build the record page URL
                this[NavigationMixin.GenerateUrl]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        objectApiName: 'Data_Archive_Schedule__c',
                        actionName: 'view'
                    }
                }).then(url => {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Schedule Created Successfully! {0}',
                            messageData: [
                                {
                                    url: url,
                                    label: 'View Data Archive Schedule Record'
                                }
                            ],
                            variant: 'success'
                        })
                    );
                });

                this.closeAllModals();
            })
            .catch(error => {

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }


    closeAllModals() {
        this.showScheduleModal = false;
        this.showCriteriaModal = false;
        this.showObjectModal = false;
        this.showChildObjectModal = false;
    }

}