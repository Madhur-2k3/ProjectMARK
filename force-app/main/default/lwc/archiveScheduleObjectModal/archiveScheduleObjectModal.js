import { LightningElement, api } from 'lwc';

export default class ArchiveScheduleObjectModal extends LightningElement {

    @api selectedFrequency;
    @api selectedCriteria;

    selectedObject;

    handleObjectSelected(event){
        this.selectedObject = event.detail;
    }

    get isDisabled(){
        return !this.selectedObject;
    }

    handleConfirm(){
        this.dispatchEvent(
            new CustomEvent('schedulecomplete', {
                detail: {
                    frequency: this.selectedFrequency,
                    criteria: this.selectedCriteria,
                    object: this.selectedObject
                }
            })
        );
    }

    handleClose(){
    this.dispatchEvent(new CustomEvent('close'));
}

}