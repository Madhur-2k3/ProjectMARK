import { LightningElement, api } from 'lwc';

export default class PicklistCell extends LightningElement {
    @api value;
    @api options;
    @api context; // row id

    handleChange(event) {
        this.dispatchEvent(new CustomEvent('picklistchanged', {
            composed: true,
            bubbles: true,
            detail: {
                rowId: this.context,
                value: event.detail.value
            }
        }));
    }
}