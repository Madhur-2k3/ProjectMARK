import { LightningElement, track, wire } from 'lwc';
import getArchivedObjectPaginated from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';
import insertArchivedRecordsBulk from '@salesforce/apex/DataArchiveObjectController.insertArchivedRecordsBulk';
import getArchiveCsvDownloadUrl from '@salesforce/apex/DataArchiveObjectController.getArchiveCsvDownloadUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class UnArchivedData extends LightningElement {

    @track archiveRecords = [];
    @track archiveColumns = [];
    selectedRows = [];

    pageSizeOptions = [
        { label: '5/page', value: '5' },
        { label: '10/page', value: '10' },
        { label: '20/page', value: '20' },
        { label: '50/page', value: '50' },
        { label: '100/page', value: '100' }
    ];

    @track pageSize = '5';
    @track currentPage = 1;
    totalPages = 1;
    totalRecords = 0;

    isButtonDisabled = true;
    wiredResult;

    @wire(getArchivedObjectPaginated, {
        pageNumber: '$currentPage',
        pageSize: '$pageSize'
    })
    wiredArchivedData(result) {
        this.wiredResult = result;

        if (result.data) {
            this.archiveColumns = result.data.columns;
            this.archiveRecords = result.data.data;
            this.totalRecords = result.data.totalRecords;
            this.totalPages = Math.ceil(this.totalRecords / Number(this.pageSize));
        }
    }

    handleSelection(event) {
        this.selectedRows = event.detail;
        this.isButtonDisabled = this.selectedRows.length !== 1;
    }

    /** ⭐⭐ DOWNLOAD + TOAST ⭐⭐ */
    async handleRowAction(event) {
        const { action, row } = event.detail;

        if (!action || action.name !== 'downloadCsv') {
            return;
        }

        try {
            const url = await getArchiveCsvDownloadUrl({ archiveId: row.Id });

            if (!url) {
                this.showToast('No File', 'No CSV found', 'warning');
                return;
            }

            // ⭐ SAFE DOWNLOAD (no popup block)
            const link = document.createElement('a');
            link.href = url;
            link.target = '_blank';
            link.download = '';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);

            // ⭐ Toast notification
            this.showToast('Download Started', 'Your CSV is downloading...', 'success');

        } catch (e) {
            this.showToast('Error', 'Download failed', 'error');
        }
    }

    handleUnarchive() {
        const ids = this.selectedRows.map(r => r.Id);

        insertArchivedRecordsBulk({ archiveRecordIds: ids })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.isButtonDisabled = true;
                refreshApex(this.wiredResult);
            })
            .catch(error => {
                this.showToast('Error', error.body?.message, 'error');
            });
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handlePageSizeChange(event) {
        this.pageSize = event.detail.value;
        this.currentPage = 1;
        refreshApex(this.wiredResult);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    get isPreviousDisabled() {
        return this.currentPage === 1;
    }

    get isNextDisabled() {
        return this.currentPage === this.totalPages;
    }
}