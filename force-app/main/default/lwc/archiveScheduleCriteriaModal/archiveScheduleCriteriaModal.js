import { LightningElement, api, wire, track } from 'lwc';
import getFieldsBySObject
    from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class ArchiveScheduleCriteriaModal extends LightningElement {

    @api selectedObject;

    isLoading = true;
    @track fieldsData = [];
    @track currentWhereClause = '';
    @track scheduleName = '';

    // ── Criteria mode toggle ──
    @track criteriaMode = 'days'; // 'days' | 'advanced'
    @track selectedDateField = '';
    @track daysValue = null;

    // Auto-populate schedule name with object + today's date
    connectedCallback() {
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        const dateStr = `${yyyy}-${mm}-${dd}`;
        this.scheduleName = `${this.selectedObject || 'Archive'} - ${dateStr}`;
    }

    // ── Mode options ──
    get criteriaModeOptions() {
        return [
            { label: 'Days-based Filter', value: 'days' },
            { label: 'Advanced Filter', value: 'advanced' }
        ];
    }

    get isDaysMode() {
        return this.criteriaMode === 'days';
    }

    get isAdvancedMode() {
        return this.criteriaMode === 'advanced';
    }

    // ── Wire: load fields ──
    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
        this.isLoading = true;
        if (data) {
            this.fieldsData = data.map(f => ({
                apiName: f.apiName,
                label: f.label,
                type: f.fieldType
            }));
            this.isLoading = false;
        } else if (error) {
            console.error('Error loading fields:', error);
            this.fieldsData = [];
            this.isLoading = false;
        }
    }

    // ── Filtered date/datetime fields for combobox ──
    get dateFieldOptions() {
        return this.fieldsData
            .filter(f => {
                const t = (f.type || '').toUpperCase();
                return t === 'DATE' || t === 'DATETIME';
            })
            .map(f => ({
                label: `${f.label} (${f.apiName})`,
                value: f.apiName
            }));
    }

    // ── Summary preview for days mode ──
    get daysSummary() {
        if (!this.selectedDateField || !this.daysValue || this.daysValue <= 0) {
            return '';
        }
        const fieldLabel = this.dateFieldOptions.find(
            f => f.value === this.selectedDateField
        );
        const displayName = fieldLabel ? fieldLabel.label : this.selectedDateField;
        return `Records where ${displayName} is older than ${this.daysValue} day${this.daysValue > 1 ? 's' : ''} will be archived.`;
    }

    get hasDaysSummary() {
        return this.daysSummary !== '';
    }

    // ── Getters ──

    get isNextDisabled() {
        if (!this.scheduleName || this.scheduleName.trim() === '') {
            return true;
        }

        if (this.criteriaMode === 'days') {
            return !this.selectedDateField || !this.daysValue || this.daysValue <= 0;
        }

        // Advanced mode
        return !this.currentWhereClause || this.currentWhereClause.trim() === '';
    }

    // ── Event Handlers ──

    handleModeChange(event) {
        this.criteriaMode = event.detail.value;
    }

    handleDateFieldChange(event) {
        this.selectedDateField = event.detail.value;
    }

    handleDaysChange(event) {
        this.daysValue = parseInt(event.detail.value, 10);
    }

    handleWhereClauseChange(event) {
        this.currentWhereClause = event.detail;
    }

    handleNameChange(event) {
        this.scheduleName = event.detail.value;
    }

    handleNext() {
        if (this.criteriaMode === 'days') {
            this.dispatchEvent(
                new CustomEvent('criteriaselected', {
                    detail: {
                        criteriaMode: 'days',
                        dateField: this.selectedDateField,
                        days: this.daysValue,
                        scheduleName: this.scheduleName
                    }
                })
            );
        } else {
            this.dispatchEvent(
                new CustomEvent('criteriaselected', {
                    detail: {
                        criteriaMode: 'advanced',
                        whereClause: this.currentWhereClause,
                        scheduleName: this.scheduleName
                    }
                })
            );
        }
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}