import { LightningElement, api, track } from 'lwc';
import getFilteredAccounts from '@salesforce/apex/objectDataHandler.getFilteredAccounts';
import { refreshApex } from '@salesforce/apex';

export default class FilterBuilder extends LightningElement {
    @api fields = [];
    @api selectobject;
    @api query;
    @api conditions;
    @api objectname;
    @api tablecolumnsname=[];
    @track filteredAccounts;
    // Pagination
    @track pageSize = '1';

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

    // Toggle Buttons
    get allRecordsVariant() { return this.isFilterMode ? "neutral" : "brand"; }
    get filterRecordsVariant() { return this.isFilterMode ? "brand" : "neutral"; }

    showAllRecords() {
        this.isFilterMode = false;
        this.filters = [];
    }

    showFilterRecords() {
        this.isFilterMode = true;
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
                showJoin: this.filters.length > 0,
                field: null,
                operator: "=",
                operatorOptions: [],
                value: "",
                isDate: false  // NEW FLAG
            }
        ];
    }

    removeFilter(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.filters = this.filters.filter(f => f.id !== id);
        if (this.filters.length) this.filters[0].showJoin = false;
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
    }

    updateFilter(event, prop) {
        const id = Number(event.target.dataset.id);
        const value = event.detail.value;

        this.filters = this.filters.map(f =>
            f.id === id ? { ...f, [prop]: value } : f
        );
    }

    get whereClause() {
        if (!this.isFilterMode || this.filters.length === 0) {
            return "/* No WHERE clause */";
        }

        return this.filters
            .map((f, index) => {
                const join = index > 0 ? ` ${f.joinType} ` : "";
                const val = this.formatValue(f);
                return `${join}${f.field} ${f.operator} ${val}`;
            })
            .join("");
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

    // async handleFilterAccounts(){
    //     try{
            
    //        this.filteredAccounts = await getFilteredAccounts({query: this.query, conditions: this.conditions, offsetSize: 0, pageSize: 10});
    //           console.log('Filtered Accounts:', JSON.stringify(this.filteredAccounts));
    //           console.log("fields",JSON.stringify(this.fields));
    //           console.log("table columns", JSON.stringify(this.tablecolumnsname));
    //     }
    //     catch(error){
    //         console.error('Error fetching filtered accounts:', error);
    //     }
        
    // }
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
            conditions: this.whereClause === "/* No WHERE clause */" ? "" : " WHERE " + this.whereClause,
            offsetSize: offsetValue,
            pageSize: this.pageSize,
            objectName: this.objectname      // <==== IMPORTANT
        });

        this.filteredAccounts = result.records;
        this.totalRecords = result.totalCount;
        this.totalPages = Math.ceil(this.totalRecords / Number(this.pageSize));

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

    // get tableColumns(){
    //     return this.fields.map(f => ({label: f.label, fieldName: f.apiName}));
    // }

    // tableColumns = [
    //     { label: 'Name', fieldName: 'Name' },
    //     { label: 'Industry', fieldName: 'Industry' },
    //     { label: 'Annual Revenue', fieldName: 'AnnualRevenue' }
    // ];
}