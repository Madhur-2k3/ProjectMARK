import { LightningElement, api, track } from 'lwc';
import getFilteredAccounts from '@salesforce/apex/objectDataHandler.getFilteredAccounts';
import getRecordCount from '@salesforce/apex/objectDataHandler.getRecordCount';

export default class RecordListWrapper extends LightningElement {
    @api objectName;
    @api fields = [];
    @api conditions = '';

    @track records = [];
    @track columns = [];
    @track isLoading = false;

    selectedRowIds = [];
    pageSize = 10;
    offsetSize = 0;
    totalRecords = 0;
    totalPages = 1;
    currentPage = 1;

    connectedCallback() {
        this.buildColumns();
        this.fetchCount();
    }

    get pageSizeOptions() {
        return [{label:'5',value:5},{label:'10',value:10},{label:'20',value:20},{label:'50',value:50}];
    }
    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }

    fetchCount() {
        getRecordCount({ objectName: this.objectName, conditions: this.conditions || '' })
        .then(total => {
            this.totalRecords = total;
            this.totalPages = Math.ceil(total / this.pageSize);
            this.currentPage = 1;
            this.fetchPage();
        });
    }

    fetchPage() {
        this.isLoading = true;
        getFilteredAccounts({
            objectName: this.objectName,
            fields: this.fields.map(f => f.apiName).join(','),
            conditions: this.conditions || '',
            offsetSize: this.offsetSize,
            pageSize: this.pageSize
        })
        .then(res => {
            this.records = res;
            this.selectedRowIds = [];
        })
        .finally(() => this.isLoading = false);
    }

    nextPage() {
        if (this.currentPage < this.totalPages) {
            this.offsetSize += this.pageSize;
            this.currentPage++;
            this.fetchPage();
        }
    }

    previousPage() {
        if (this.currentPage > 1) {
            this.offsetSize -= this.pageSize;
            this.currentPage--;
            this.fetchPage();
        }
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.detail.value, 10);
        this.offsetSize = 0;
        this.fetchCount();
    }

    handleRowSelect(event) {
        this.selectedRowIds = event.detail.map(r => r.Id);
        this.dispatchEvent(new CustomEvent('rowselection', { detail: this.selectedRowIds }));
    }

    buildColumns() {
        this.columns = this.fields.map(f => ({
            label: f.label,
            fieldName: f.apiName,
            type: f.type.toLowerCase()
        }));
    }
}