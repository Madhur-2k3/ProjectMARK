import { LightningElement, api, track } from 'lwc';
import getFilteredAccounts from '@salesforce/apex/objectDataHandler.getFilteredAccounts';
import { refreshApex } from '@salesforce/apex';
import archiveSelectedRecords from '@salesforce/apex/DataArchiveController.archiveSelectedRecords';
import archiveAllRecords from '@salesforce/apex/DataArchiveController.archiveAllRecords';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';


export default class FilterBuilder extends LightningElement {
    masterSelectedIds = new Set();
    archiveSelectedRows = [];
    @api selectfields=[];
    @api fields = [];
    @api selectobject;
    @api query;
    @api conditions;
    @api objectname;
    @api tablecolumnsname=[];
    @track filteredAccounts;
    // Pagination
    @track pageSize = '5';
    @track allRecords=true;
    @track selectedRows=[];
    @track selectedCondition='AND';
    pageSizeOptions = [
        { label: '5 / page', value: '5' },
        { label: '10 / page', value: '10' },
        { label: '15 / page', value: '15' },
        { label: '20 / page', value: '20' }
    ];
    conditionOptions=[
        { label: 'All Conditions Met (AND)', value: 'AND' },
        { label: 'Any Condition Met (OR)', value: 'OR' },
        { label: 'Custom Condition Logic', value: 'CUSTOM' }
    ]
    // @api archiveColumns;

     @track currentPage = 1;
    totalPages = 1;
    totalRecords = 0;
    
    @track filters = [];
    isFilterMode = false;
    get isButtonDisabled() {
        return this.tablecolumnsname.length === 0;
    }
    showModal = false;
    customLogic = '';
    modalMessage=''

    // Toggle Buttons
    get allRecordsVariant() { return this.isFilterMode ? "neutral" : "brand"; }
    get filterRecordsVariant() { return this.isFilterMode ? "brand" : "neutral"; }

    showAllRecords() {
    this.isFilterMode = false;     // switch toggle button
    this.allRecords = true;
    this.filters = [];             // clear filters
    this.filteredAccounts = null;
    
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
            { label: "not equals", value: "!=" }
        ],
        BOOLEAN: [
            { label: "equals", value: "=" }
        ],
        DOUBLE: [
            { label: "equals", value: "=" },
            { label: "greater than", value: ">" },
            { label: "less than", value: "<" }
        ],
        INTEGER: [
            { label: "equals", value: "=" },
            { label: "greater than", value: ">" },
            { label: "less than", value: "<" }
        ],
        DATE: [
            { label: "equals", value: "=" },
            { label: "greater than", value: ">" },
            { label: "less than", value: "<" }
        ],
        DATETIME: [
            { label: "equals", value: "=" },
            { label: "greater than", value: ">" },
            { label: "less than", value: "<" }
        ],
        CURRENCY: [
    { label: "equals", value: "=" },
    { label: "greater than", value: ">" },
    { label: "less than", value: "<" }
]

    };

    get fieldOptions() {
        return this.fields.map(f => ({
            label: f.label,
            value: f.apiName
        }));
    }
    handleConditionChange(event){
        this.selectedCondition = event.detail.value;
        this.notifyWhereClauseChange();
    }

addFilter() {
    this.filters = [
        ...this.filters,
        {
            id: Date.now(),
            field: null,
            operator: "=",
            operatorOptions: [],
            value: "",
            isDate: false,
            fieldType: "STRING",
            showJoin: this.filters.length === 0 ? 'filter-box-first' : 'filter-box',
            displayIndex: this.filters.length + 1
        }
    ];
    this.notifyWhereClauseChange();
}



    removeFilter(event) {
    const id = Number(event.currentTarget.dataset.id);
    this.filters = this.filters.filter(f => f.id !== id);
    console.log("Filterss Array length:",this.filters.length);
    if(this.filters.length>0){
        this.filters[0].showJoin = 'filter-box-first';
        this.filters = [...this.filters];
    }
    this.filters=this.filters.map((f, index) => {
        return {
            ...f,
            displayIndex: index + 1
        };
    })

    // 🔥 If NO filters left → switch to All Records mode
    if (this.filters.length === 0) {
        this.showAllRecords();

    }

    this.notifyWhereClauseChange();   // update parent
}



    handleJoinChange(e) { this.updateFilter(e, "joinType"); }
    handleOperatorChange(e) { this.updateFilter(e, "operator"); }
    handleValueChange(e) { this.updateFilter(e, "value"); }
    // handleConditionChange(e) { this.updateFilter(e, "condition"); }

    
    handleFieldChange(event) {
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
                isDate: fieldMeta.type === "DATE" || fieldMeta.type === "DATETIME",
                fieldType: fieldMeta.type
                
            };
        }
        return f;
    });

    this.notifyWhereClauseChange();   // 🔥
}

    updateFilter(event, prop) {
    const id = Number(event.target.dataset.id);
    const value = event.detail.value;

    this.filters = this.filters.map(f =>
        f.id === id ? { ...f, [prop]: value } : f
    );

    this.notifyWhereClauseChange();   // 🔥
}

get whereClause() {
    if (!this.isFilterMode || !this.filters.length) {
        return '';
    }

    const valid = [];

    this.filters.forEach((f, i) => {
        // skip incomplete filters
        if (!f.field || !f.operator || f.value === '' || f.value === null || f.value === undefined) {
            return;
        }

        valid.push(`${f.field} ${f.operator} ${this.formatValue(f)}`);
    });

    if (!valid.length) return '';

    // 🔥 GLOBAL CONDITION DROP-DOWN
    if (this.selectedCondition === "AND") {
        return valid.join(" AND ");
    }
    if (this.selectedCondition === "OR") {
        return valid.join(" OR ");
    }

    // 🔥 CUSTOM COMBINATION (user will define manually)
    return this.customWhereLogic(valid);
}
customWhereLogic(validParts) {
    // Ask user input, e.g: (1 AND 2) OR 3
    const input = this.customLogic || ""; // store separately
    if (!input) return validParts.join(" AND "); // fallback

    // Replace numbers with actual conditions
    return input.replace(/\b\d+\b/g, match => {
        const idx = parseInt(match, 10) - 1;
        return validParts[idx] || '';
    });
}
handleCustomLogic(event) {
    this.customLogic = event.detail.value;
    
    // this.filters=this.filters.map((f, index) => {
    //     return {
    //         ...f,
    //         displayIndex: index + 1
    //     };
    // })
    this.notifyWhereClauseChange();
}
get isCustom() {

    return this.selectedCondition === "CUSTOM";
}


get selectedFieldApiList() {
    // return this.tablecolumnsname.map(c => c.fieldName);
    return this.selectfields.map(f => f.apiName);
    
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
    this.currentPage = 1;
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
            // conditions: this.whereClause === "/* No WHERE clause */" ? "" : " WHERE " + this.whereClause,
            offsetSize: offsetValue,
            pageSize: this.pageSize,
            objectName: this.objectname      // <==== IMPORTANT
        });

        this.filteredAccounts = result.records;
        console.log("Filtered Accounts:",JSON.stringify(this.filteredAccounts));
        this.totalRecords = result.totalCount;
        this.totalPages = Math.ceil(this.totalRecords / Number(this.pageSize));

// 🔥 VERY IMPORTANT — restore selection after page change
        this.archiveSelectedRows = [...this.masterSelectedIds];
    } catch (error) {
        console.error("Error Loading Records:", error);
    }
}
handlePageSizeChange(event) {
        this.pageSize = event.detail.value;
        this.currentPage = 1;

        // 🔄 Refresh on page size update
        this.loadRecords();
    }
    handleArchiveRowSelections(event) {
    const rows = event.detail.selectedRows;   // correct property

    // 1. Add newly selected rows
    rows.forEach(r => this.masterSelectedIds.add(r.Id));

    // 2. Remove deselected rows from current page
    this.filteredAccounts.forEach(r => {    
        if (!rows.find(x => x.Id === r.Id)) {
            this.masterSelectedIds.delete(r.Id);
        }
    });

    // 3. Convert master set to array
    this.archiveSelectedRows = [...this.masterSelectedIds];

    console.log("MASTER Selected IDs:", JSON.stringify(this.archiveSelectedRows));
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
            //show modal for selected
            this.showModal = true;
            this.modalMessage = `Are you sure you want to archive the selected ${this.masterSelectedIds.size} records?`;
            console.log("Modal status",this.showModal);
            // this.archiveSelected();
        } else {
             this.showModal = true;
            this.modalMessage = `Are you sure you want to archive all records?`;
            // this.archiveAll();
        }
    }
    closeModal(){
        this.showModal = false;
        console.log("modal status",this.showModal);
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

    // ---------------------------
    // ARCHIVE SELECTED
    // ---------------------------
    archiveSelected() {
        const ids = [...this.masterSelectedIds];

        if (ids.length === 0) {
            return this.showToast('Error', 'Select at least one row.', 'error');
        }

        archiveSelectedRecords({
            objectName: this.objectname,
            recordIds: ids,
            fieldsCsv: this.selectedFieldApiList.join(',')
        })
            .then(() => {
                this.showToast('Success', 'Selected records archived.', 'success');
                this.masterSelectedIds.clear();
                this.dispatchEvent(new CustomEvent('refreshdata'));
                this.loadRecords();
            })
            .catch(err => this.showError(err));
    }

    // ---------------------------
    // ARCHIVE ALL
    // ---------------------------
    archiveAll() {
        if (!this.query) {
            return this.showToast('Error', 'Full query missing.', 'error');
        }

        archiveAllRecords({
            objectName: this.objectname,
            fieldsCsv: this.selectedFieldApiList.join(','),
            fullQuery: this.query
        })
            .then(() => {
                this.showToast('Success', 'All records archived.', 'success');
                this.dispatchEvent(new CustomEvent('refreshdata'));
                this.loadRecords();
            })
            .catch(err => this.showError(err));
    }

    // ---------------------------
    // TOOLS
    // ---------------------------
    showError(error) {
        const msg = error?.body?.message || 'Unknown error';
        this.showToast('Error', msg, 'error');
        console.error(error);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}