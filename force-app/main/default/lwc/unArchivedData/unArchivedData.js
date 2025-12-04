import { LightningElement, track } from 'lwc';
import getArchivedObjectPaginated from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';
import insertArchivedRecordsBulk from '@salesforce/apex/DataArchiveObjectController.insertArchivedRecordsBulk';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class UnArchivedData extends LightningElement {

    @track archiveRecords = [];
    @track archiveColumns = [];
    selectedRows = [];

    // Pagination
    @track pageSize = '1';
    pageSizeOptions = [
        { label: '1', value: '1' },
        { label: '2', value: '2' },
        { label: '15', value: '15' },
        { label: '20', value: '20' }
    ];

    @track currentPage = 1;
    totalPages = 1;
    totalRecords = 0;

    isButtonDisabled = true;

    connectedCallback() {
        this.loadRecords();
    }

    loadRecords() {
        getArchivedObjectPaginated({
            pageNumber: this.currentPage,
            pageSize: Number(this.pageSize)
        })
        .then(result => {
            this.archiveColumns = result.columns;
            this.archiveRecords = result.data;
            this.totalRecords = result.totalRecords;
            this.totalPages = Math.ceil(this.totalRecords / Number(this.pageSize));
        })
        .catch(error => {
            console.error('Error fetching data:', error);
        });
    }

    handleSelection(event) {
        this.selectedRows = event.detail;
        this.isButtonDisabled = this.selectedRows.length !== 1;
    }

    handleUnarchive() {
        const ids = this.selectedRows.map(r => r.Id);

        insertArchivedRecordsBulk({ archiveRecordIds: ids })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.isButtonDisabled = true;
                this.loadRecords();
            })
            .catch(error => {
                this.showToast('Error', error.body?.message, 'error');
            });
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.loadRecords();
        }
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadRecords();
        }
    }

    handlePageSizeChange(event) {
        this.pageSize = event.detail.value;
        this.currentPage = 1;
        this.loadRecords();
    }

    get isPreviousDisabled() {
        return this.currentPage === 1;
    }

    get isNextDisabled() {
        return this.currentPage === this.totalPages;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}