import { LightningElement } from 'lwc';

export default class ArchiveScheduleFrequencyModal extends LightningElement {

    selectedValue;

    frequencyOptions = [
        { label: 'Daily', value: 'DAILY' },
        { label: 'Weekly Once', value: 'WEEKLY_ONCE' },
        { label: 'Weekly', value: 'WEEKLY' },
        { label: 'Monthly', value: 'MONTHLY' },
        { label: 'Yearly', value: 'YEARLY' }
    ];

    get isDisabled(){
        return !this.selectedValue;
    }

    handleChange(event){
        this.selectedValue = event.detail.value;
    }

    handleNext(){
        this.dispatchEvent(
            new CustomEvent('frequencyselected', {
                detail: this.selectedValue
            })
        );
    }

    handleClose(){
    this.dispatchEvent(new CustomEvent('close'));
}

}