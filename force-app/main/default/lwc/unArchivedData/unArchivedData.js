import { LightningElement, track, wire } from 'lwc';
import getArchivedObjectPaginated from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';
import insertArchivedRecordsBulk from '@salesforce/apex/DataArchiveObjectController.insertArchivedRecordsBulk';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class UnArchivedData extends LightningElement {

    @track archiveRecords = [];
    @track archiveColumns = [];
    selectedRows = [];

    // Pagination
    @track pageSize = '1';

    pageSizeOptions = [
        { label: '1 / page', value: '1' },
        { label: '2 / page', value: '2' },
        { label: '15 / page', value: '15' },
        { label: '20 / page', value: '20' }
    ];

    @track currentPage = 1;
    totalPages = 1;
    totalRecords = 0;

    isButtonDisabled = true;

    // APEX refresh reference
    wiredResult;

    @wire(getArchivedObjectPaginated, {
        pageNumber: '$currentPage',
        pageSize: '$pageSize'
    })
    wiredArchivedData(result) {
        this.wiredResult = result; // store reference for refreshApex
        
        if (result.data) {
            this.archiveColumns = result.data.columns;
            this.archiveRecords = result.data.data;
            this.totalRecords = result.data.totalRecords;
            this.totalPages = Math.ceil(this.totalRecords / Number(this.pageSize));
        }
        else if (result.error) {
            console.error('Error fetching data:', result.error);
        }
    }

    // Row Selection
    handleSelection(event) {
        this.selectedRows = event.detail;
        this.isButtonDisabled = this.selectedRows.length !== 1;
    }

    // Unarchive
    handleUnarchive() {
        const ids = this.selectedRows.map(r => r.Id);

        insertArchivedRecordsBulk({ archiveRecordIds: ids })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.isButtonDisabled = true;

                // 🔄 Refresh Apex after unarchive
                refreshApex(this.wiredResult);
            })
            .catch(error => {
                this.showToast('Error', error.body?.message, 'error');
            });
    }

    // Pagination: Next
    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    // Pagination: Previous
    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    // Page Size Change
    handlePageSizeChange(event) {
        this.pageSize = event.detail.value;
        this.currentPage = 1;

        // 🔄 Refresh on page size update
        refreshApex(this.wiredResult);
    }

    // UI Helpers
    get isPreviousDisabled() {
        return this.currentPage === 1;
    }

    get isNextDisabled() {
        return this.currentPage === this.totalPages;
    }

    // Toast
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}