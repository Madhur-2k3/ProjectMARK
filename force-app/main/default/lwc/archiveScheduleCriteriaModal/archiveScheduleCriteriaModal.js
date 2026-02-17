import { LightningElement, api } from 'lwc';

export default class ArchiveScheduleCriteriaModal extends LightningElement {

    @api selectedObject;

    selectedField = 'CreatedDate';
    days = 30;


    // Date-type fields use "Older Than (Days)" input
    // Text-type fields use a free-text input
    dateFields = new Set(['CreatedDate', 'LastModifiedDate']);

    dateFieldOptions = [
        { label: 'Created Date', value: 'CreatedDate' },
        { label: 'Last Modified Date', value: 'LastModifiedDate' }
    ];

    get isDateField() {
        return this.dateFields.has(this.selectedField);
    }


    handleFieldChange(event) {
        this.selectedField = event.detail.value;
    }

    handleDaysChange(event) {
        this.days = event.detail.value;
    }



    handleNext() {
        this.dispatchEvent(
            new CustomEvent('criteriaselected', {
                detail: {
                    field: this.selectedField,
                    days: this.days
                }
            })
        );
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}