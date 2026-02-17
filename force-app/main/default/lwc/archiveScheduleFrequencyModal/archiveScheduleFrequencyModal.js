import { LightningElement, api } from 'lwc';

export default class ArchiveScheduleFrequencyModal extends LightningElement {

    @api selectedObject;
    @api selectedCriteria;

    selectedValue;

    frequencyOptions = [
        { label: 'Daily', value: 'DAILY' },
        { label: 'Weekly Once', value: 'WEEKLY_ONCE' },
        { label: 'Weekly', value: 'WEEKLY' },
        { label: 'Monthly', value: 'MONTHLY' },
        { label: 'Yearly', value: 'YEARLY' }
    ];

    get isDisabled() {
        return !this.selectedValue;
    }

    handleChange(event) {
        this.selectedValue = event.detail.value;
    }

    handleNext() {
        this.dispatchEvent(
            new CustomEvent('schedulecomplete', {
                detail: {
                    frequency: this.selectedValue,
                    criteria: this.selectedCriteria,
                    object: this.selectedObject
                }
            })
        );
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

}