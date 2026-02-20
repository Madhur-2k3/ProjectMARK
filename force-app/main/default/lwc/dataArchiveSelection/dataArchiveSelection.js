import { LightningElement } from 'lwc';
import scheduleArchive
    from '@salesforce/apex/DataArchiveScheduleController.scheduleArchive';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';

export default class DataArchiveSelection extends LightningElement {

    booleanFlag = true;     // Archive default ON
    unArchiveFlag = false;


    // Modal Flags
    showScheduleModal = false;
    showCriteriaModal = false;
    showObjectModal = false;

    // Store selections
    selectedFrequency;
    selectedCriteria;
    selectedObject;

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

    // Criteria selected → open Frequency modal
    handleCriteriaSelected(event) {
        this.selectedCriteria = event.detail;
        this.showCriteriaModal = false;
        this.showScheduleModal = true;
    }

    // Previous from Criteria → back to Object modal
    handleCriteriaPrevious() {
        this.showCriteriaModal = false;
        this.showObjectModal = true;
    }

    // Previous from Frequency → back to Criteria modal
    handleFrequencyPrevious() {
        this.showScheduleModal = false;
        this.showCriteriaModal = true;
    }

    // Frequency selected and scheduling complete
    handleScheduleComplete(event) {

        const scheduleData = event.detail;

        scheduleArchive({
            objectName:    scheduleData.object,
            frequency:     scheduleData.frequency,
            dateField:     scheduleData.criteria.whereClause || 'FilterCriteria',
            days:          0,
            filterValue:   scheduleData.criteria.whereClause,
            preferredTime: scheduleData.preferredTime,
            dayOfWeek:     scheduleData.dayOfWeek
        })
            .then(result => {

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: result,
                        variant: 'success'
                    })
                );

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
    }

}