import { LightningElement, wire, track } from 'lwc';
import getDataArchive from '@salesforce/apex/DataArchiveObjectController.getArchivedObject';
import insertArchivedRecordsBulk from '@salesforce/apex/DataArchiveObjectController.insertArchivedRecordsBulk';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class ParentComponent extends LightningElement {
    @track archiveRecords = [];
    @track archiveColumns = [];
    selectedRows = [];
    wiredResult;
    isButtonDisabled = true;   // Initially disabled

    // Load archive data
    @wire(getDataArchive)
    wiredArchive(result) {
        this.wiredResult = result;

        if (result.data) {
            this.archiveRecords = result.data.data;
            this.archiveColumns = result.data.columns;
        } else if (result.error) {
            console.error(result.error);
        }
    }

    // Capture selected rows
    handleSelection(event) {
        this.selectedRows = event.detail;

        // Enable button only if exactly one row selected
        this.isButtonDisabled = this.selectedRows.length === 1 ? false : true;
    }

    // Unarchive logic
    handleUnarchive() {
        const archiveIds = this.selectedRows.map(r => r.Id);

        insertArchivedRecordsBulk({ archiveRecordIds: archiveIds })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.isButtonDisabled = true; // Disable again after action
                return refreshApex(this.wiredResult);
            })
            .catch(error => {
                console.error(error);
                this.showToast('Error', error.body?.message, 'error');
            });
    }

    // Toast utility
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}