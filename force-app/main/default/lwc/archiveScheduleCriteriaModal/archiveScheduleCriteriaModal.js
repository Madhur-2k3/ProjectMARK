import { LightningElement, api, wire, track } from 'lwc';
import getFieldsBySObject
    from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class ArchiveScheduleCriteriaModal extends LightningElement {

    @api selectedObject;

    isLoading = true;
    @track fieldsData = [];
    @track filters = [];
    @track selectedCondition = 'AND';
    customLogic = '';

    // ── Operator Maps (same as filterBuilder) ──
    operatorMap = {
        STRING: [
            { label: 'equals', value: '=' },
            { label: 'not equals', value: '!=' },
            { label: 'contains', value: 'LIKE' }
        ],
        PICKLIST: [
            { label: 'equals', value: '=' },
            { label: 'not equals', value: '!=' },
            { label: 'contains', value: 'LIKE' }
        ],
        BOOLEAN: [
            { label: 'equals', value: '=' },
            { label: 'not equals', value: '!=' }
        ],
        DOUBLE: [
            { label: 'equals', value: '=' },
            { label: 'not equals', value: '!=' },
            { label: 'greater than', value: '>' },
            { label: 'greater than or equals', value: '>=' },
            { label: 'less than or equals', value: '<=' },
            { label: 'less than', value: '<' }
        ],
        INTEGER: [
            { label: 'equals', value: '=' },
            { label: 'greater than', value: '>' },
            { label: 'less than', value: '<' },
            { label: 'greater than or equals', value: '>=' },
            { label: 'less than or equals', value: '<=' },
            { label: 'not equals', value: '!=' }
        ],
        DATE: [
            { label: 'equals', value: '=' },
            { label: 'not equals', value: '!=' },
            { label: 'greater than', value: '>' },
            { label: 'greater than or equals', value: '>=' },
            { label: 'less than or equals', value: '<=' },
            { label: 'less than', value: '<' }
        ],
        DATETIME: [
            { label: 'equals', value: '=' },
            { label: 'not equals', value: '!=' },
            { label: 'greater than', value: '>' },
            { label: 'greater than or equals', value: '>=' },
            { label: 'less than or equals', value: '<=' },
            { label: 'less than', value: '<' }
        ],
        CURRENCY: [
            { label: 'equals', value: '=' },
            { label: 'greater than', value: '>' },
            { label: 'less than', value: '<' },
            { label: 'greater than or equals', value: '>=' },
            { label: 'less than or equals', value: '<=' },
            { label: 'not equals', value: '!=' }
        ]
    };

    conditionOptions = [
        { label: 'All Conditions Met (AND)', value: 'AND' },
        { label: 'Any Condition Met (OR)', value: 'OR' },
        { label: 'Custom Condition Logic', value: 'CUSTOM' }
    ];

    // ── Wire: load fields ──
    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
        this.isLoading = true;
        if (data) {
            this.fieldsData = data.map(f => ({
                apiName: f.apiName,
                label:   f.label,
                type:    f.fieldType
            }));
            // Add first empty filter row
            if (this.filters.length === 0) {
                this.addFilter();
            }
            this.isLoading = false;
        } else if (error) {
            console.error('Error loading fields:', error);
            this.fieldsData = [];
            this.isLoading = false;
        }
    }

    // ── Getters ──

    get fieldOptions() {
        return this.fieldsData.map(f => ({
            label: f.label,
            value: f.apiName
        }));
    }

    get isCustom() {
        return this.selectedCondition === 'CUSTOM';
    }

    get isNextDisabled() {
        return !this.whereClause || this.whereClause.trim() === '';
    }

    get whereClause() {
        if (!this.filters.length) return '';

        const valid = [];
        this.filters.forEach(f => {
            if (!f.field || !f.operator || f.value === '' || f.value === undefined) return;
            valid.push(`${f.field} ${f.operator} ${this.formatValue(f)}`);
        });

        if (!valid.length) return '';

        if (this.selectedCondition === 'AND') return valid.join(' AND ');
        if (this.selectedCondition === 'OR')  return valid.join(' OR ');

        return this.customWhereLogic(valid);
    }

    // ── Actions ──

    handleConditionChange(event) {
        this.selectedCondition = event.detail.value;
    }

    handleCustomLogic(event) {
        this.customLogic = event.detail.value;
        const textarea = event.target;

        if (!this.isValidCustomLogic(this.customLogic)) {
            textarea.setCustomValidity('Invalid logic: Check your parentheses or filter numbers.');
        } else {
            textarea.setCustomValidity('');
        }
        textarea.reportValidity();
    }

    addFilter() {
        this.filters = [
            ...this.filters,
            {
                id: Date.now() + Math.random(),
                field: null,
                operator: '=',
                operatorOptions: [],
                value: '',
                isDate: false,
                isDateTime: false,
                showTextInput: true,
                fieldType: 'STRING',
                showJoin: this.filters.length === 0 ? 'filter-box-first' : 'filter-box',
                displayIndex: this.filters.length + 1
            }
        ];
    }

    removeFilter(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.filters = this.filters.filter(f => f.id !== id);

        if (this.filters.length > 0) {
            this.filters[0].showJoin = 'filter-box-first';
            this.filters = [...this.filters];
        }

        this.filters = this.filters.map((f, index) => ({
            ...f,
            displayIndex: index + 1
        }));
    }

    handleFieldChange(event) {
        const id = Number(event.target.dataset.id);
        const selectedField = event.detail.value;
        const fieldMeta = this.fieldsData.find(f => f.apiName === selectedField);
        const ops = this.operatorMap[fieldMeta.type] || this.operatorMap.STRING;

        this.filters = this.filters.map(f => {
            if (f.id === id) {
                return {
                    ...f,
                    field: selectedField,
                    operatorOptions: ops,
                    operator: ops[0].value,
                    isDate: fieldMeta.type === 'DATE',
                    isDateTime: fieldMeta.type === 'DATETIME',
                    fieldType: fieldMeta.type,
                    showTextInput: !(fieldMeta.type === 'DATE' || fieldMeta.type === 'DATETIME')
                };
            }
            return f;
        });
    }

    handleOperatorChange(event) {
        this.updateFilter(event, 'operator');
    }

    handleValueChange(event) {
        this.updateFilter(event, 'value');
    }

    updateFilter(event, prop) {
        const id = Number(event.target.dataset.id);
        const value = event.detail.value;
        this.filters = this.filters.map(f =>
            f.id === id ? { ...f, [prop]: value } : f
        );
    }

    // ── Value Formatting (same as filterBuilder) ──

    formatValue(filter) {
        const fieldMeta = this.fieldsData.find(f => f.apiName === filter.field);
        const type = fieldMeta?.type || 'STRING';
        let val = filter.value;

        if (type === 'DATE' || type === 'DATETIME') {
            return `${val}`;
        }

        if (type === 'STRING' || type === 'PICKLIST' || type === 'ID') {
            if (filter.operator === 'LIKE') {
                return `'%${val}%'`;
            }
            return `'${val}'`;
        }

        return val;
    }

    // ── Custom Logic Helpers ──

    customWhereLogic(validParts) {
        let formattedInput = this.formatLogicString(this.customLogic);
        if (!formattedInput) return validParts.join(' AND ');

        return formattedInput.replace(/\b(\d+)\b/g, (match) => {
            const idx = parseInt(match, 10) - 1;
            return validParts[idx] !== undefined ? validParts[idx] : '';
        });
    }

    isValidCustomLogic(logic) {
        if (!logic || logic.trim() === '') return true;

        const sanitized = logic.replace(/\d+/g, '')
                               .replace(/AND/gi, '')
                               .replace(/OR/gi, '')
                               .replace(/[\(\)\s]/g, '');

        if (sanitized.length > 0) return false;

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

    // ── Navigation ──

    handleNext() {
        this.dispatchEvent(
            new CustomEvent('criteriaselected', {
                detail: {
                    whereClause: this.whereClause
                }
            })
        );
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}