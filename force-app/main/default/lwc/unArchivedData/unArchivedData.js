import { LightningElement, track, wire } from 'lwc';
import getDataArchive from '@salesforce/apex/DataArchiveObjectController.getArchivedObject';
import insertArchivedRecordsBulk from '@salesforce/apex/DataArchiveObjectController.insertArchivedRecordsBulk';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ParentComponent extends LightningElement {
    @track archiveRecords = [];
    @track archiveColumns = [];
    selectedRows = [];

    @wire(getDataArchive)
    wiredArchiveData({ error, data }) {
        if (data) {
            // Deep clone to avoid LWC proxy errors
            this.archiveRecords = data.data ? JSON.parse(JSON.stringify(data.data)) : [];
            this.archiveColumns = data.columns ? JSON.parse(JSON.stringify(data.columns)) : [];
        } else if (error) {
            console.error('Error loading archive data:', error);
        }
    }

    handleSelection(event) {
        this.selectedRows = event.detail;
    }

    handleSubmit() {
        // Validation: Ensure exactly ONE record is selected
        if (this.selectedRows.length === 0) {
            this.showToast('Error', 'Please select one record before submitting', 'error');
            return;
        }
        if (this.selectedRows.length > 1) {
            this.showToast('Error', 'You can select only one record at a time', 'error');
            return;
        }

        const archiveIds = this.selectedRows.map(row => row.Id);

        insertArchivedRecordsBulk({ archiveRecordIds: archiveIds })
            .then(result => {
                this.showToast('Success', result, 'success');
                console.log('Insert Result:', result);
            })
            .catch(error => {
                this.showToast('Error', error.body ? error.body.message : error.message, 'error');
                console.log('Insert Error:', JSON.stringify(error));
            });
    }

    showToast(title, message, variant){
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}