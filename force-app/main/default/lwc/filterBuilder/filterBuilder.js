import { LightningElement, api, track } from 'lwc';
import getFilteredAccounts from '@salesforce/apex/objectDataHandler.getFilteredAccounts';
import { refreshApex } from '@salesforce/apex';

export default class FilterBuilder extends LightningElement {
    masterSelectedIds = new Set();
    archiveSelectedRows = [];

    @api fields = [];
    @api selectobject;
    @api query;
    @api conditions;
    @api objectname;
    @api tablecolumnsname=[];
    @track filteredAccounts;
    // Pagination
    @track pageSize = '1';
    @track allRecords=true;
    @track selectedRows=[];
    pageSizeOptions = [
        { label: '1 / page', value: '1' },
        { label: '2 / page', value: '2' },
        { label: '15 / page', value: '15' },
        { label: '20 / page', value: '20' }
    ];
    // @api archiveColumns;

     @track currentPage = 1;
    totalPages = 1;
    totalRecords = 0;
    
    @track filters = [];
    isFilterMode = false;
    get isButtonDisabled() {
        return this.tablecolumnsname.length === 0;
    }

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

    addFilter() {
    this.filters = [
        ...this.filters,
        {
            id: Date.now(),
            joinType: "AND",
            showJoin: this.filters.length === 0 ? 'filter-box-first' : 'filter-box',
            field: null,
            operator: "=",
            operatorOptions: [],
            value: "",
            isDate: false
        }
    ];

    this.notifyWhereClauseChange();   // 🔥
}


    removeFilter(event) {
    const id = Number(event.currentTarget.dataset.id);
    this.filters = this.filters.filter(f => f.id !== id);
    console.log("Filterss Array length:",this.filters.length);
    if(this.filters.length>0){
        this.filters[0].showJoin = 'filter-box-first';
        this.filters = [...this.filters];
    }

    // 🔥 If NO filters left → switch to All Records mode
    if (this.filters.length === 0) {
        this.showAllRecords();

    }

    this.notifyWhereClauseChange();   // update parent
}



    handleJoinChange(e) { this.updateFilter(e, "joinType"); }
    handleOperatorChange(e) { this.updateFilter(e, "operator"); }
    handleValueChange(e) { this.updateFilter(e, "value"); }

    
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
                isDate: fieldMeta.type === "DATE" || fieldMeta.type === "DATETIME"
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

    const validParts = [];

    this.filters.forEach((f, index) => {
        // ❌ Skip filter if field/operator/value empty
        if (!f.field || !f.operator || f.value === '' || f.value === null || f.value === undefined) {
            return;
        }

        const join = index > 0 ? ` ${f.joinType} ` : '';
        const val = this.formatValue(f);

        validParts.push(`${join}${f.field} ${f.operator} ${val}`);
    });

    return validParts.join('');
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
notifyWhereClauseChange() {
    this.dispatchEvent(
        new CustomEvent("wherechange", {
            detail: this.whereClause
        })
    );
}


}