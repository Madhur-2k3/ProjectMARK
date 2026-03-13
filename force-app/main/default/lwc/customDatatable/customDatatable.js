import LightningDatatable from 'lightning/datatable';
import picklistTemplate from './picklistTemplate.html';

export default class CustomDatatable extends LightningDatatable {
    static customTypes = {
        picklist: {
            template: picklistTemplate,
            standardCellLayout: false,
            typeAttributes: ['options', 'value', 'context']
        }
    };

    connectedCallback() {
        super.connectedCallback();
        this.template.addEventListener('picklistchanged', this.handlePicklistChanged.bind(this));
    }

    handlePicklistChanged(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('picklistchange', {
            composed: true,
            bubbles: true,
            detail: {
                rowId: event.detail.rowId,
                value: event.detail.value
            }
        }));
    }
}