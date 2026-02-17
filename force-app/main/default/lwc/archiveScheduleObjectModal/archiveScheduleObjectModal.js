import { LightningElement } from 'lwc';

export default class ArchiveScheduleObjectModal extends LightningElement {

    selectedObject;

    handleObjectSelected(event) {
        this.selectedObject = event.detail;
    }

    get isDisabled() {
        return !this.selectedObject;
    }

    handleConfirm() {
        this.dispatchEvent(
            new CustomEvent('objectselected', {
                detail: this.selectedObject
            })
        );
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

}