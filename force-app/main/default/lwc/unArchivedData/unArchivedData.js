// // import { LightningElement, track, wire } from 'lwc';
// // import getArchivedObjectPaginated from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';
// // import insertArchivedRecordsBulk from '@salesforce/apex/DataArchiveObjectController.insertArchivedRecordsBulk';
// // import getArchiveCsvDownloadUrl from '@salesforce/apex/DataArchiveObjectController.getArchiveCsvDownloadUrl';
// // import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// // import { refreshApex } from '@salesforce/apex';

// // export default class UnArchivedData extends LightningElement {

// //     @track archiveRecords = [];
// //     @track archiveColumns = [];
// //     selectedRows = [];

// //     pageSizeOptions = [
// //         { label: '5/page', value: '5' },
// //         { label: '10/page', value: '10' },
// //         { label: '20/page', value: '20' },
// //         { label: '50/page', value: '50' },
// //         { label: '100/page', value: '100' }
// //     ];

// //     @track pageSize = '5';
// //     @track currentPage = 1;
// //     totalPages = 1;
// //     totalRecords = 0;

// //     @track isLoading = false;      // 🔄 Spinner flag
// //     isButtonDisabled = true;
// //     wiredResult;

// //     /* ================== DATA LOAD ================== */
// //     @wire(getArchivedObjectPaginated, {
// //         pageNumber: '$currentPage',
// //         pageSize: '$pageSize'
// //     })
// //     wiredArchivedData(result) {
// //         this.wiredResult = result;

// //         if (result.data) {
// //             this.archiveColumns = result.data.columns;
// //             this.archiveRecords = result.data.data;
// //             this.totalRecords = result.data.totalRecords;
// //             this.totalPages = Math.ceil(this.totalRecords / Number(this.pageSize));
// //         }
// //     }

// //     /* ================== ROW SELECTION ================== */
// //     handleSelection(event) {
// //         this.selectedRows = event.detail;
// //         this.isButtonDisabled = this.selectedRows.length !== 1;
// //     }

// //     /* ================== CSV DOWNLOAD ================== */
// //     async handleRowAction(event) {
// //         const { action, row } = event.detail;
// //         if (!action || action.name !== 'downloadCsv') return;

// //         try {
// //             const url = await getArchiveCsvDownloadUrl({ archiveId: row.Id });

// //             if (!url) {
// //                 this.showToast('No File', 'No CSV found', 'warning');
// //                 return;
// //             }

// //             const link = document.createElement('a');
// //             link.href = url;
// //             link.target = '_blank';
// //             document.body.appendChild(link);
// //             link.click();
// //             document.body.removeChild(link);

// //             this.showToast('Download Started', 'Your CSV is downloading...', 'success');
// //         } catch (e) {
// //             this.showToast('Error', 'Download failed', 'error');
// //         }
// //     }

// //     /* ================== UN-ARCHIVE ================== */
// //     handleUnarchive() {
// //         const ids = this.selectedRows.map(r => r.Id);

// //         this.isLoading = true;
// //         this.isButtonDisabled = true;

// //         insertArchivedRecordsBulk({ archiveRecordIds: ids })
// //             .then(result => {
// //                 this.showToast('Success', result, 'success');
// //                 this.selectedRows = [];
// //                 return refreshApex(this.wiredResult);
// //             })
// //             .catch(error => {
// //                 this.showToast(
// //                     'Error',
// //                     error.body?.message || 'Un-archive failed',
// //                     'error'
// //                 );
// //                 console.error('Unarchive error:', JSON.stringify(error));
// //             })
// //             .finally(() => {
// //                 this.isLoading = false;
// //             });
// //     }

// //     /* ================== PAGINATION ================== */
// //     handleNext() {
// //         if (this.currentPage < this.totalPages && !this.isLoading) {
// //             this.currentPage++;
// //         }
// //     }

// //     handlePrevious() {
// //         if (this.currentPage > 1 && !this.isLoading) {
// //             this.currentPage--;
// //         }
// //     }

// //     handlePageSizeChange(event) {
// //         this.pageSize = event.detail.value;
// //         this.currentPage = 1;
// //         refreshApex(this.wiredResult);
// //     }

// //     /* ================== TOAST ================== */
// //     showToast(title, message, variant) {
// //         this.dispatchEvent(
// //             new ShowToastEvent({ title, message, variant })
// //         );
// //     }

// //     /* ================== UI STATES ================== */
// //     get isPreviousDisabled() {
// //         return this.isLoading || this.currentPage === 1;
// //     }

// //     get isNextDisabled() {
// //         return this.isLoading || this.currentPage === this.totalPages;
// //     }
// // }
// import { LightningElement, track, wire } from 'lwc';
// import getArchivedObjectPaginated
//     from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';
// import unarchiveAsync
//     from '@salesforce/apex/DataArchiveObjectController.unarchiveAsync';
// import getArchiveCsvDownloadUrl
//     from '@salesforce/apex/DataArchiveObjectController.getArchiveCsvDownloadUrl';
// import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// export default class UnArchivedData extends LightningElement {

//     /* ================= DATA ================= */
//     @track archiveRecords = [];
//     @track archiveColumns = [];
//     selectedRows = [];

//     pageSizeOptions = [
//         { label: '5/page', value: '5' },
//         { label: '10/page', value: '10' },
//         { label: '20/page', value: '20' },
//         { label: '50/page', value: '50' }
//     ];

//     @track pageSize = '5';
//     @track currentPage = 1;
//     @track totalPages = 1;
//     totalRecords = 0;

//     isButtonDisabled = true;

//     /* ================= LOAD DATA ================= */
//     @wire(getArchivedObjectPaginated, {
//         pageNumber: '$currentPage',
//         pageSize: '$pageSize'
//     })
//     wiredData({ data, error }) {
//         if (data) {
//             this.archiveColumns = data.columns;
//             this.archiveRecords = data.data;
//             this.totalRecords = data.totalRecords;
//             this.totalPages = Math.ceil(
//                 this.totalRecords / Number(this.pageSize)
//             );
//         } else if (error) {
//             this.showToast(
//                 'Error',
//                 error.body?.message || 'Failed to load data',
//                 'error'
//             );
//         }
//     }

//     /* ================= ROW SELECTION ================= */
//     handleSelection(event) {
//         this.selectedRows = event.detail;
//         this.isButtonDisabled = this.selectedRows.length !== 1;
//     }

//     /* ================= CSV DOWNLOAD ================= */
//     handleRowAction(event) {
//         const { action, row } = event.detail;
//         if (!action || action.name !== 'downloadCsv') return;

//         getArchiveCsvDownloadUrl({ archiveId: row.Id })
//             .then(url => {
//                 if (url) {
//                     window.open(url, '_blank');
//                 } else {
//                     this.showToast('No File', 'CSV not found', 'warning');
//                 }
//             })
//             .catch(() => {
//                 this.showToast('Error', 'Download failed', 'error');
//             });
//     }

//     /* ================= UN-ARCHIVE ================= */
//     handleUnarchive() {
//         const ids = this.selectedRows.map(r => r.Id);
//         this.isButtonDisabled = true;

//         unarchiveAsync({ archiveRecordIds: ids })
//             .then(message => {
//                 this.showToast('Success', message, 'success');

//                 /* 🔁 RESET UI STATE */
//                 this.selectedRows = [];
//                 this.currentPage = 1;   // force reload page 1
//             })
//             .catch(error => {
//                 this.showToast(
//                     'Error',
//                     error.body?.message || 'Un-archive failed',
//                     'error'
//                 );
//             });
//     }

//     /* ================= PAGINATION ================= */
//     handleNext() {
//         if (this.currentPage < this.totalPages) {
//             this.currentPage++;
//         }
//     }

//     handlePrevious() {
//         if (this.currentPage > 1) {
//             this.currentPage--;
//         }
//     }

//     handlePageSizeChange(event) {
//         this.pageSize = event.detail.value;
//         this.currentPage = 1;
//     }

//     /* ================= UI HELPERS ================= */
//     get isPreviousDisabled() {
//         return this.currentPage === 1;
//     }

//     get isNextDisabled() {
//         return this.currentPage === this.totalPages;
//     }

//     showToast(title, message, variant) {
//         this.dispatchEvent(
//             new ShowToastEvent({ title, message, variant })
//         );
//     }
// }

import { LightningElement, track, wire } from 'lwc';
// import getAllArchiveCsvDownloadUrls
//     from '@salesforce/apex/DataArchiveObjectController.getAllArchiveCsvDownloadUrls';

import getArchivedObjectPaginated
    from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';
import unarchiveAsync
    from '@salesforce/apex/DataArchiveObjectController.unarchiveAsync';
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
        { label: '50/page', value: '50' }
    ];

    @track pageSize = '5';
    @track currentPage = 1;
    @track totalPages = 1;
    totalRecords = 0;

    isButtonDisabled = true;
    wiredResult;

    /* ================= LOAD DATA ================= */
    @wire(getArchivedObjectPaginated, {
        pageNumber: '$currentPage',
        pageSize: '$pageSize'
    })
    wiredData(result) {
        this.wiredResult = result;

        if (result.data) {
            this.archiveColumns = result.data.columns;
            this.archiveRecords = result.data.data;
            this.totalRecords = result.data.totalRecords;
            this.totalPages = Math.ceil(
                this.totalRecords / Number(this.pageSize)
            );
        }
    }

    /* ================= ROW SELECTION ================= */
    handleSelection(event) {
        this.selectedRows = event.detail;
            // event.detail.filter(
            //     r => r.Status__c === 'Ready for Unarchive'
            // );

        this.isButtonDisabled = this.selectedRows.length !== 1;
    }

    /* ================= UNARCHIVE ================= */
    handleUnarchive() {
        const ids = this.selectedRows.map(r => r.Id);
        this.isButtonDisabled = true;

        unarchiveAsync({ archiveRecordIds: ids })
            .then(msg => {

                //  LONG ASYNC TOAST
                this.showToast(
                    'Un-archive Started',
                    msg + ' You may refresh safely.',
                    'info',
                    18000
                );

                this.selectedRows = [];

                //  IMMEDIATE STATUS REFRESH
                refreshApex(this.wiredResult);

                //  REFRESH AGAIN (queueable may still be running)
                setInterval(() => {
                    refreshApex(this.wiredResult);
                    // window.location.reload();
                }, 2000);
            })
            .catch(() => {
                this.showToast(
                    'Error',
                    'Un-archive failed',
                    'error',
                    8000
                );
            });
    }

    /* ================= PAGINATION ================= */
    handleNext() {
        if (this.currentPage < this.totalPages) this.currentPage++;
    }

    handlePrevious() {
        if (this.currentPage > 1) this.currentPage--;
    }

    handlePageSizeChange(event) {
        this.pageSize = event.detail.value;
        this.currentPage = 1;
        refreshApex(this.wiredResult);
    }

    get isPreviousDisabled() {
        return this.currentPage === 1;
    }

    get isNextDisabled() {
        return this.currentPage === this.totalPages;
    }

    showToast(title, message, variant, duration) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                duration
            })
        );
    }
    // handleRowAction(event) {
    // const { action, row } = event.detail;

    // if (!action || action.name !== 'downloadCsv') return;

    // getAllArchiveCsvDownloadUrls({ archiveId: row.Id })
    //     .then(urls => {
    //         if (!urls || urls.length === 0) {
    //             this.showToast(
    //                 'No Files',
    //                 'No CSV files found for this record',
    //                 'warning',
    //                 6000
    //             );
    //             return;
    //         }

    //         // Download all CSV files
    //         urls.forEach((url, index) => {
    //             setTimeout(() => {
    //                 window.open(url, '_blank');
    //             }, index * 500); // avoid popup block
    //         });

    //         this.showToast(
    //             'Download Started',
    //             `CSV file downloading`,
    //             'success',
    //             8000
    //         );
    //     })
    //     .catch(() => {
    //         this.showToast(
    //             'Error',
    //             'Failed to download CSV files',
    //             'error',
    //             8000
    //         );
    //     });
// }

}
// import { LightningElement, track, wire } from 'lwc';

// import getAllArchiveCsvDownloadUrls
//     from '@salesforce/apex/DataArchiveObjectController.getAllArchiveCsvDownloadUrls';

// import getArchivedObjectPaginated
//     from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';

// import unarchiveAsync
//     from '@salesforce/apex/DataArchiveObjectController.unarchiveAsync';

// import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import { refreshApex } from '@salesforce/apex';

// export default class UnArchivedData extends LightningElement {

//     @track archiveRecords = [];
//     @track archiveColumns = [];
//     selectedRows = [];

//     pageSizeOptions = [
//         { label: '5/page', value: '5' },
//         { label: '10/page', value: '10' },
//         { label: '20/page', value: '20' },
//         { label: '50/page', value: '50' }
//     ];

//     @track pageSize = '5';
//     @track currentPage = 1;
//     @track totalPages = 1;
//     totalRecords = 0;

//     isButtonDisabled = true;
//     wiredResult;

//     /* ================= LOAD DATA ================= */
//     @wire(getArchivedObjectPaginated, {
//         pageNumber: '$currentPage',
//         pageSize: '$pageSize'
//     })
//     wiredData(result) {
//         this.wiredResult = result;

//         if (result.data) {
//             this.archiveColumns = result.data.columns;
//             this.archiveRecords = result.data.data;
//             this.totalRecords = result.data.totalRecords;
//             this.totalPages = Math.ceil(
//                 this.totalRecords / Number(this.pageSize)
//             );
//         }
//     }

//     /* ================= ROW SELECTION ================= */
//     handleSelection(event) {
//         this.selectedRows = event.detail;
//         this.isButtonDisabled = this.selectedRows.length !== 1;
//     }

//     /* ================= UNARCHIVE ================= */
//     handleUnarchive() {
//         const ids = this.selectedRows.map(r => r.Id);
//         this.isButtonDisabled = true;

//         unarchiveAsync({ archiveRecordIds: ids })
//             .then(msg => {

//                 this.showToast(
//                     'Un-archive Started',
//                     msg + ' You may refresh safely.',
//                     'info',
//                     18000
//                 );

//                 this.selectedRows = [];

//                 refreshApex(this.wiredResult);

//                 setInterval(() => {
//                     refreshApex(this.wiredResult);
//                 }, 2000);
//             })
//             .catch(() => {
//                 this.showToast(
//                     'Error',
//                     'Un-archive failed',
//                     'error',
//                     8000
//                 );
//             });
//     }

//     /* ================= DOWNLOAD ALL CSV ONE BY ONE ================= */
//     wait(ms) {
//         return new Promise(resolve => setTimeout(resolve, ms));
//     }

//     async handleRowAction(event) {
//         const { action, row } = event.detail;

//         if (!action || action.name !== 'downloadCsv') return;

//         try {
//             const urls = await getAllArchiveCsvDownloadUrls({ archiveId: row.Id });

//             if (!urls || urls.length === 0) {
//                 this.showToast(
//                     'No Files',
//                     'No CSV files found for this record',
//                     'warning',
//                     6000
//                 );
//                 return;
//             }

//             this.showToast(
//                 'Download Started',
//                 `Downloading ${urls.length} CSV file(s) one by one...`,
//                 'success',
//                 6000
//             );

//             for (let i = 0; i < urls.length; i++) {
//                 const url = urls[i];

//                 const link = document.createElement('a');
//                 link.href = url;
//                 // link.target = '_blank';
//                 document.body.appendChild(link);
//                 link.click();
//                 document.body.removeChild(link);

//                 await this.wait(1200);
//             }

//         } catch (error) {
//             console.error(error);
//             this.showToast(
//                 'Error',
//                 error?.body?.message || 'Failed to download CSV files',
//                 'error',
//                 8000
//             );
//         }
//     }

//     /* ================= PAGINATION ================= */
//     handleNext() {
//         if (this.currentPage < this.totalPages) this.currentPage++;
//     }

//     handlePrevious() {
//         if (this.currentPage > 1) this.currentPage--;
//     }

//     handlePageSizeChange(event) {
//         this.pageSize = event.detail.value;
//         this.currentPage = 1;
//         refreshApex(this.wiredResult);
//     }

//     get isPreviousDisabled() {
//         return this.currentPage === 1;
//     }

//     get isNextDisabled() {
//         return this.currentPage === this.totalPages;
//     }

//     showToast(title, message, variant, duration) {
//         this.dispatchEvent(
//             new ShowToastEvent({
//                 title,
//                 message,
//                 variant,
//                 duration
//             })
//         );
//     }
// }