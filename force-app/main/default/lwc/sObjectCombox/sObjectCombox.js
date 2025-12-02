import { LightningElement, track, wire } from 'lwc';
import getAllSObjectNames from '@salesforce/apex/sObjectsController.getAllSObjectNames';

export default class SObjectCombox extends LightningElement {
    sobjectOptions = [];
    @track filteredOptions;
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

    handleSearch(event) {

        const searchKey = event.target.value.toLowerCase();

        this.filteredOptions = this.sobjectOptions.filter(opt =>
            opt.label.toLowerCase().includes(searchKey) ||
            opt.value.toLowerCase().includes(searchKey)
        );
        console.log("Filtered options",JSON.stringify(this.filteredOptions));
    }

    handleSelect(event) {
        this.selectedSObject = event.currentTarget.dataset.value;
        console.log('Selected:', this.selectedSObject);
        this.searchTerm = this.selectedSObject;
        this.filteredOptions = null; // Clear the filtered options after selection
    }
}