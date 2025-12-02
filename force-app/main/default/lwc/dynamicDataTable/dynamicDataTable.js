import { LightningElement, api } from 'lwc';

export default class DynamicDataTable extends LightningElement {
    @api data;
    @api columns;

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.dispatchEvent(new CustomEvent('rowselection', { detail: selectedRows }));
    }
}