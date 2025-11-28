import { LightningElement, api } from 'lwc';

export default class DynamicDatatable extends LightningElement {
    @api data = [];       // data passed from parent
    @api columns = [];    // columns passed from parent
}