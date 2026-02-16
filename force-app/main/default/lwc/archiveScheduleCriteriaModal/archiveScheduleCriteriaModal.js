import { LightningElement, api } from 'lwc';

export default class ArchiveScheduleCriteriaModal extends LightningElement {

    @api selectedFrequency;

    selectedField = 'CreatedDate';
    days = 30;

    dateFieldOptions = [
        { label: 'Created Date', value: 'CreatedDate' },
        { label: 'Last Modified Date', value: 'LastModifiedDate' }
    ];

    handleFieldChange(event){
        this.selectedField = event.detail.value;
    }

    handleDaysChange(event){
        this.days = event.detail.value;
    }

    handleNext(){
        this.dispatchEvent(
            new CustomEvent('criteriaselected', {
                detail: {
                    field: this.selectedField,
                    days: this.days
                }
            })
        );
    }

    handleClose(){
    this.dispatchEvent(new CustomEvent('close'));
}

}