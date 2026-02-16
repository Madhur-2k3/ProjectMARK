import { LightningElement, api } from 'lwc';

export default class ArchiveScheduleCriteriaModal extends LightningElement {

    @api selectedFrequency;

    selectedField = 'CreatedDate';
    days = 30;
    filterValue = '';

    // Date-type fields use "Older Than (Days)" input
    // Text-type fields use a free-text input
    dateFields = new Set(['CreatedDate', 'LastModifiedDate']);

    dateFieldOptions = [
        { label: 'Created Date', value: 'CreatedDate' },
        { label: 'Last Modified Date', value: 'LastModifiedDate' },
        { label: 'Customer Name', value: 'Customer_Name__c' }
    ];

    get isDateField() {
        return this.dateFields.has(this.selectedField);
    }

    get isTextField() {
        return !this.isDateField;
    }

    handleFieldChange(event) {
        this.selectedField = event.detail.value;
    }

    handleDaysChange(event) {
        this.days = event.detail.value;
    }

    handleFilterValueChange(event) {
        this.filterValue = event.detail.value;
    }

    handleNext() {
        this.dispatchEvent(
            new CustomEvent('criteriaselected', {
                detail: {
                    field: this.selectedField,
                    days: this.isDateField ? this.days : null,
                    filterValue: this.isTextField ? this.filterValue : null
                }
            })
        );
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}