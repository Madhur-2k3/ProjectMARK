import { LightningElement, wire } from 'lwc';
import getAllSObjectNames from '@salesforce/apex/sObjectsController.getAllSObjectNames';

export default class SObjectCombox extends LightningElement {
    sobjectOptions = [];
    selectedSObject = '';

    @wire(getAllSObjectNames)
    wiredSObjects({ error, data }) {
        if (data) {
            this.sobjectOptions = data.map(item => ({
                label: item.label,
                value: item.apiName
            }));
        } else if (error) {
            console.error(error);
        }
    }

    handleSObjectChange(event) {
        this.selectedSObject = event.detail.value;
        console.log('Selected SObject API Name:', this.selectedSObject);
    }
}