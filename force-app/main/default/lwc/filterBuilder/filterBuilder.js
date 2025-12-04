import { LightningElement, api, track } from 'lwc';

export default class FilterBuilder extends LightningElement {
    @api fields = [];

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
        ]
    };

    get fieldOptions() {
        return this.fields.map(f => ({
            label: f.apiName,
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
}