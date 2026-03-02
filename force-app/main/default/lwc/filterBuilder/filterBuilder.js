import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getFilteredAccounts from '@salesforce/apex/objectDataHandler.getFilteredAccounts';
import archiveSelectedRecords from '@salesforce/apex/DataArchiveController.archiveSelectedRecords';
import archiveAllRecords from '@salesforce/apex/DataArchiveController.archiveAllRecords';
import getBatchStatus from '@salesforce/apex/DataArchiveController.getBatchStatus';
import getArchiveRecordId from '@salesforce/apex/DataArchiveController.getArchiveRecordId';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class FilterBuilder extends LightningElement {
    isLoading = false;
    masterSelectedIds = new Set();
    archiveSelectedRows = [];
    
    // Batch job tracking
    batchJobId = null;
    archiveRecordId = null;
    batchPollingInterval = null;
    
    @api selectfields=[];
    @api fields = [];
    @api selectobject;
    @api query;
    @api conditions;
    @api objectname;
    @api objectlabel;
    @api tablecolumnsname=[];
    @api changed;
    @api criteriaOnly = false;
    @track showNoRecords=false;
    @track showTable=false;
    @track filteredAccounts;
    @track pageSize = '20';
    @track allRecords=true;
    @track selectedRows=[];
    @track selectedCondition='AND';
    @track currentPage = 1;
    totalPages = 1;
    totalRecords = 0;
    @track filters = [];
    @track objectLabel = '';
    isFilterMode = false;
    showModal = false;
    customLogic = '';
    modalMessage='';
    note='';

    closeTable(){
        this.showTable=false;
        this.showNoRecords=false;
    }

    pageSizeOptions = [
        { label: '20 / page', value: '20' },
        { label: '40 / page', value: '40' },
        { label: '60 / page', value: '60' },
        { label: '80 / page', value: '80' },
        { label: '100 / page', value: '100' },
        { label: '200 / page', value: '200' },
        { label: '300 / page', value: '300' },
        { label: '400 / page', value: '400' },
        {label: '500 / page', value: '500' },
        {label: '2000 / page', value: '2000' },
        {label: '3000 / page', value: '3000' },
    ];

    conditionOptions=[
        { label: 'All Conditions Met (AND)', value: 'AND' },
        { label: 'Any Condition Met (OR)', value: 'OR' },
        { label: 'Custom Condition Logic', value: 'CUSTOM' }
    ];

    connectedCallback(){
        if(this.changed){
            this.filteredAccounts=null;
        }
        if(this.criteriaOnly){
            this.isFilterMode = true;
            this.allRecords = false;
            if(!this.filters.length){
                this.addFilter();
            }
        }
    }

    disconnectedCallback() {
        this.stopBatchPolling();
    }

    get isButtonDisabled() {
        return this.tablecolumnsname.length === 0;
    }

    get allRecordsVariant() { return this.isFilterMode ? "neutral" : "brand"; }
    get filterRecordsVariant() { return this.isFilterMode ? "brand" : "neutral"; }

    get showToggle() { return !this.criteriaOnly; }
    get showFilters() { return this.isFilterMode || this.criteriaOnly; }

    showAllRecords() {
        this.isFilterMode = false;
        this.allRecords = true;
        this.filters = [];
        this.filteredAccounts = null;
        this.showNoRecords=false;
        this.notifyWhereClauseChange();
    }

    showFilterRecords() {
        this.isFilterMode = true;
        this.allRecords = false;
        if (!this.filters.length) {
            this.addFilter();
        }
    }

    joinOptions = [
        { label: "AND", value: "AND" },
        { label: "OR", value: "OR" }
    ];

    operatorMap = {
        STRING: [
            { label: "equals", value: "=" },
            { label: "not equals", value: "!=" },
            { label: "contains", value: "LIKE" }
        ],
        PICKLIST: [
            { label: "equals", value: "=" },
            { label: "not equals", value: "!=" },
            { label: "contains", value: "LIKE" }
        ],
        BOOLEAN: [
            { label: "equals", value: "=" },
            { label: "not equals", value: "!=" }
        ],
        DOUBLE: [
            { label: "equals", value: "=" },
            { label: "not equals", value: "!=" },
            { label: "greater than", value: ">" },
            { label: "greater than or equals", value: ">=" },
            { label: "less than or equals", value: "<=" },
            { label: "less than", value: "<" }
        ],
        INTEGER: [
            { label: "equals", value: "=" },
            { label: "greater than", value: ">" },
            { label: "less than", value: "<" },
            { label: "greater than or equals", value: ">=" },
            { label: "less than or equals", value: "<=" },
            { label: "not equals", value: "!=" }
        ],
        DATE: [
            { label: "equals", value: "=" },
            { label: "not equals", value: "!=" },
            { label: "greater than", value: ">" },
            { label: "greater than or equals", value: ">=" },
            { label: "less than or equals", value: "<=" },
            { label: "less than", value: "<" }
        ],
        DATETIME: [
            { label: "equals", value: "=" },
            { label: "not equals", value: "!=" },
            { label: "greater than", value: ">" },
            { label: "greater than or equals", value: ">=" },
            { label: "less than or equals", value: "<=" },
            { label: "less than", value: "<" }
        ],
        CURRENCY: [
            { label: "equals", value: "=" },
            { label: "greater than", value: ">" },
            { label: "less than", value: "<" },
            { label: "greater than or equals", value: ">=" },
            { label: "less than or equals", value: "<=" },
            { label: "not equals", value: "!=" }
        ]
    };

    get fieldOptions() {
        return this.fields.map(f => ({
            label: f.label,
            value: f.apiName
        }));
    }

    handleConditionChange(event){
        this.closeTable();
        this.selectedCondition = event.detail.value;
        this.notifyWhereClauseChange();
    }

    addFilter() {
        this.closeTable();
        this.filters = [
            ...this.filters,
            {
                id: Date.now(),
                field: null,
                operator: "=",
                operatorOptions: [],
                value: "",
                isDate: false,
                isDateTime: false,
                showTextInput:true,
                fieldType: "STRING",
                showJoin: this.filters.length === 0 ? 'filter-box-first' : 'filter-box',
                displayIndex: this.filters.length + 1
            }
        ];
        this.notifyWhereClauseChange();
    }

    get isSubmitDisabled() {
        if (this.tablecolumnsname.length === 0) return true;
        if (!this.filters.length) return true;

        const basicFiltersInvalid = this.filters.some(f =>
            !f.field || !f.operator || f.value === "" || f.value === null
        );

        const customLogicInvalid = this.isCustom && !this.isValidCustomLogic(this.customLogic);
        return basicFiltersInvalid || customLogicInvalid;
    }

    removeFilter(event) {
        this.closeTable();
        const id = Number(event.currentTarget.dataset.id);
        this.filters = this.filters.filter(f => f.id !== id);
        
        if(this.filters.length>0){
            this.filters[0].showJoin = 'filter-box-first';
            this.filters = [...this.filters];
        }
        
        this.filters=this.filters.map((f, index) => {
            return {
                ...f,
                displayIndex: index + 1
            };
        });

        if (this.filters.length === 0 && !this.criteriaOnly) {
            this.showAllRecords();
        }

        this.notifyWhereClauseChange();
    }

    handleJoinChange(e) { this.updateFilter(e, "joinType"); }
    handleOperatorChange(e) { 
        this.closeTable();
        this.updateFilter(e, "operator"); 
    }
    handleValueChange(e) {
        this.closeTable();
        this.updateFilter(e, "value"); 
    }

    handleFieldChange(event) {
        this.closeTable();
        const id = Number(event.target.dataset.id);
        const selectedField = event.detail.value;
        const fieldMeta = this.fields.find(f => f.apiName === selectedField);
        const ops = this.operatorMap[fieldMeta.type] || this.operatorMap.STRING;
        
        this.filters = this.filters.map(f => {
            if (f.id === id) {
                return {
                    ...f,
                    field: selectedField,
                    operatorOptions: ops,
                    operator: ops[0].value,
                    isDate: fieldMeta.type === "DATE",
                    isDateTime: fieldMeta.type === "DATETIME",
                    fieldType: fieldMeta.type,
                    showTextInput:!(fieldMeta.type === "DATE" || fieldMeta.type === "DATETIME")
                };
            }
            return f;
        });

        this.notifyWhereClauseChange();
    }

    updateFilter(event, prop) {
        const id = Number(event.target.dataset.id);
        const value = event.detail.value;

        this.filters = this.filters.map(f =>
            f.id === id ? { ...f, [prop]: value } : f
        );

        this.notifyWhereClauseChange();
    }

    get whereClause() {
        if ((!this.isFilterMode && !this.criteriaOnly) || !this.filters.length) {
            return '';
        }

        const valid = [];

        this.filters.forEach((f, i) => {
            if (!f.field || !f.operator || f.value === ''  || f.value === undefined) {
                return;
            }

            valid.push(`${f.field} ${f.operator} ${this.formatValue(f)}`);
        });

        if (!valid.length) return '';

        if (this.selectedCondition === "AND") {
            return valid.join(" AND ");
        }
        if (this.selectedCondition === "OR") {
            return valid.join(" OR ");
        }

        return this.customWhereLogic(valid);
    }

    customWhereLogic(validParts) {
        let formattedInput = this.formatLogicString(this.customLogic);
        if (!formattedInput) return validParts.join(" AND ");

        const finalQuery = formattedInput.replace(/\b(\d+)\b/g, (match) => {
            const idx = parseInt(match, 10) - 1;
            return validParts[idx] !== undefined ? validParts[idx] : '';
        });

        return finalQuery;
    }

    handleCustomLogic(event) {
        this.closeTable();
        this.customLogic = event.detail.value;
        const textarea = event.target;
        
        if (!this.isValidCustomLogic(this.customLogic)) {
            textarea.setCustomValidity("Invalid logic: Check your parentheses or filter numbers.");
        } else {
            textarea.setCustomValidity("");
        }
        textarea.reportValidity();
        this.notifyWhereClauseChange();
    }

    get isCustom() {
        return this.selectedCondition === "CUSTOM";
    }

    get selectedFieldApiList() {
        return this.selectfields.map(f => f.apiName);
    }


    @wire(getObjectInfo, { objectApiName: '$objectname' })
    wiredObjectInfo({ data, error }) {
        // If parent passed a friendly label, use it
        if (this.objectlabel) {
            this.objectLabel = this.objectlabel;
            return;
        }
        if (data) {
            this.objectLabel = data?.label || this.objectname;
        } else if (error) {
            this.objectLabel = this.objectname;
        }
    }

    formatValue(filter) {
        const fieldMeta = this.fields.find(f => f.apiName === filter.field);
        const type = fieldMeta?.type || "STRING";
        let val = filter.value;

        if (type === "DATE" || type === "DATETIME") {
            return `${val}`;
        }

        if (type === "STRING" || type === "PICKLIST" || type === "ID") {
            if (filter.operator === "LIKE") {
                return `'%${val}%'`;
            }
            return `'${val}'`;
        }

        return val;
    }

    handleFilterAccounts() {
        const validators = [...this.template.querySelectorAll('c-field-validator')];
        let allValid = true;

        validators.forEach(v => {
            if (!v.validate()) {
                allValid = false;
            }
        });

        if (!allValid) {
            this.showToast('Error', 'Please fix validation errors before filtering.', 'error');
            return;
        }
        
        this.filteredAccounts=null;
        this.currentPage = 1;
        this.showTable=true;
        this.showNoRecords=false;
        this.loadRecords();
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

    get isPreviousDisabled() {
        return this.currentPage === 1;
    }

    get isNextDisabled() {
        return this.currentPage === this.totalPages;
    }

    async loadRecords() {
        try {
            const offsetValue = (this.currentPage - 1) * Number(this.pageSize);

            const result = await getFilteredAccounts({
                query: this.query,
                offsetSize: offsetValue,
                pageSize: this.pageSize,
                objectName: this.objectname      
            });

            this.filteredAccounts = result.records;
            console.log("Filtered Accounts",JSON.stringify(this.filteredAccounts))
            this.showNoRecords = result.records.length === 0;
            this.showTable = !this.showNoRecords;
            
            this.totalRecords = result.totalCount;
            this.totalPages = Math.ceil(this.totalRecords / Number(this.pageSize));

            this.archiveSelectedRows = [...this.masterSelectedIds];
        } catch (error) {
            console.error("Error Loading Records:", error);
            this.showNoRecords = true;
        }
    }

    handlePageSizeChange(event) {
        this.pageSize = event.detail.value;
        this.currentPage = 1;
        this.loadRecords();
    }

    handleArchiveRowSelections(event) {
        const rows = event.detail.selectedRows;

        rows.forEach(r => this.masterSelectedIds.add(r.Id));

        this.filteredAccounts.forEach(r => {    
            if (!rows.find(x => x.Id === r.Id)) {
                this.masterSelectedIds.delete(r.Id);
            }
        });

        this.archiveSelectedRows = [...this.masterSelectedIds];
    }

    get archiveButtonLabel() {
        return this.masterSelectedIds.size > 0 ? 'Archive Selected' : 'Archive All';
    }

    notifyWhereClauseChange() {
        this.dispatchEvent(
            new CustomEvent("wherechange", {
                detail: this.whereClause
            })
        );
    }

    handlearchive() {
        if (this.masterSelectedIds.size > 0) {
            this.showModal = true;
            this.modalMessage = `Are you sure you want to archive the selected ${this.masterSelectedIds.size} records?`;
            this.note = 'Selected records will be archived. This process runs in the background.';
        } else {
            this.showModal = true;
            this.modalMessage = `Are you sure you want to archive all records?`;
            this.note = 'All records will be archived. This process runs in the background.';
        }
    }

    closeModal(){
        this.showModal = false;
    }

    confirmArchive(){
        if(this.masterSelectedIds.size>0){
            this.showModal = false;
            this.archiveSelected();
        }
        else{
            this.showModal = false;
            this.archiveAll();
        }    
    }

    // =====================================================
    // ARCHIVE SELECTED (BATCH)
    // =====================================================
    archiveSelected() {
        const ids = [...this.masterSelectedIds];

        if (ids.length === 0) {
            return this.showToast('Error', 'Select at least one row.', 'error');
        }
        
        this.isLoading = true;

        archiveSelectedRecords({
            objectName: this.objectname,
            recordIds: ids,
            fieldsCsv: this.selectedFieldApiList.join(',')
        })
            .then((batchJobId) => {
                this.batchJobId = batchJobId;
                this.showToast('Success', 'Archive batch job started. Monitoring progress...', 'success');
                this.startBatchPolling();
                this.masterSelectedIds.clear();
            })
            .catch(err => this.showError(JSON.stringify(err)))
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =====================================================
    // ARCHIVE ALL (BATCH)
    // =====================================================
    archiveAll() {
        if (!this.query) {
            return this.showToast('Error', 'Full query missing.', 'error');
        }
        
        this.isLoading = true;

        archiveAllRecords({
            objectName: this.objectname,
            fieldsCsv: this.selectedFieldApiList.join(','),
            fullQuery: this.query
        })
            .then((batchJobId) => {
                this.batchJobId = batchJobId;
                this.showToast('Success', 'Archive batch job started. Monitoring progress...', 'success');
                this.startBatchPolling();
            })
            .catch(err => this.showError(err))
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =====================================================
    // BATCH STATUS POLLING
    // =====================================================
    startBatchPolling() {
        this.stopBatchPolling();
        
        this.batchPollingInterval = setInterval(() => {
            this.checkBatchStatus();
        }, 3000); // Poll every 3 seconds
    }

    stopBatchPolling() {
        if (this.batchPollingInterval) {
            clearInterval(this.batchPollingInterval);
            this.batchPollingInterval = null;
        }
    }

    async checkBatchStatus() {
        if (!this.batchJobId) return;

        try {
            const status = await getBatchStatus({ batchJobId: this.batchJobId });
            
            console.log('Batch Status:', status.status);
            
            if (status.status === 'Completed') {
                this.stopBatchPolling();
                this.handleBatchCompletion();
            } else if (status.status === 'Failed' || status.status === 'Aborted') {
                this.stopBatchPolling();
                this.showToast('Error', 'Archive batch job failed.', 'error');
                this.isLoading = false;
            }
        } catch (error) {
            console.error('Error checking batch status:', error);
            this.stopBatchPolling();
        }
    }

    async handleBatchCompletion() {
        try {
            const archiveId = await getArchiveRecordId({ batchJobId: this.batchJobId });
            
            if (archiveId) {
                this.archiveRecordId = archiveId;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: '{0}',
                        messageData: [
                            {
                                url: '/' + archiveId,
                                label: 'Archive Completed! Click here to view Data Archive Record'
                            }
                        ],
                        variant: 'success',
                    })
                );
                
                this.dispatchEvent(new CustomEvent('refreshdata'));
                this.loadRecords();
            }
        } catch (error) {
            console.error('Error getting archive record:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // =====================================================
    // UTILITIES
    // =====================================================
    showError(error) {
        const msg = error?.body?.message || 'Unknown error';
        this.showToast('Error', msg, 'error');
        console.error(error);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    isValidCustomLogic(logic) {
        if (!logic || logic.trim() === '') return true;

        const sanitizedLogic = logic.replace(/\d+/g, '')
                                    .replace(/AND/gi, '')
                                    .replace(/OR/gi, '')
                                    .replace(/[\(\)\s]/g, '');
        
        if (sanitizedLogic.length > 0) {
            return false;
        }

        let stack = [];
        for (let char of logic) {
            if (char === '(') stack.push(char);
            else if (char === ')') {
                if (stack.length === 0) return false;
                stack.pop();
            }
        }
        if (stack.length !== 0) return false;

        const usedIndices = logic.match(/\b\d+\b/g);
        if (usedIndices) {
            const maxIndex = this.filters.length;
            for (let num of usedIndices) {
                const val = parseInt(num, 10);
                if (val > maxIndex || val <= 0) return false;
            }
        }

        return true;
    }

    formatLogicString(logic) {
        if (!logic) return '';

        return logic
            .replace(/\(/g, ' ( ')
            .replace(/\)/g, ' ) ')
            .replace(/(\d+)/g, ' $1 ')
            .replace(/AND/gi, ' AND ')
            .replace(/OR/gi, ' OR ')
            .replace(/\s+/g, ' ')
            .trim();
    }
}