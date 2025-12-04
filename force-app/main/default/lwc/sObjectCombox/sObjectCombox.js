import { LightningElement, track, wire } from 'lwc';
import getAllSObjectNames from '@salesforce/apex/sObjectsController.getAllSObjectNames';

export default class SObjectCombox extends LightningElement {

    sobjectOptions = [];
    filteredOptions;
    selectedSObject = '';

    @track selectedFields = [];      
    @track requiredFields = [];
    @track finalFieldsForApex = [];  
    @track whereClause = '';

    searchTerm = '';

    @wire(getAllSObjectNames)
    wiredSObjects({ error, data }) {
        if (data) {
            this.sobjectOptions = data.map(item => ({
                label: item.label,
                value: item.apiName
            }));
        }
    }

    handleSearch(event) {
        const key = event.target.value.toLowerCase();
        this.searchTerm = key;

        this.filteredOptions = this.sobjectOptions.filter(opt =>
            opt.label.toLowerCase().includes(key) ||
            opt.value.toLowerCase().includes(key)
        );
    }

    handleSelect(event) {
        this.selectedSObject = event.currentTarget.dataset.value;
        this.filteredOptions = null;

        // reset state
        this.selectedFields = [];
        this.finalFieldsForApex = [];
        this.whereClause = '';
    }

    // RECEIVE FIELDS FROM FIELD SELECTOR
    handleFieldChange(event) {
        const fromChild = event.detail;

        this.selectedFields = fromChild;

        this.requiredFields = fromChild
            .filter(f => f.required)
            .map(f => f.apiName);

        this.finalFieldsForApex = [...fromChild];
    }

    // RECEIVE WHERE CLAUSE FROM FILTER BUILDER
    handleWhereClauseChange(event) {
        this.whereClause = event.detail;
    }

    // BUILD FINAL SOQL QUERY
    get finalQuery() {
        if (!this.selectedSObject || !this.finalFieldsForApex.length) {
            return '';
        }

        const fieldList = this.finalFieldsForApex
            .map(f => f.apiName)
            .join(', ');

        let q = `SELECT ${fieldList} FROM ${this.selectedSObject}`;

        if (this.whereClause) {
            q += ` WHERE ${this.whereClause}`;
        }

        return q;
    }
}