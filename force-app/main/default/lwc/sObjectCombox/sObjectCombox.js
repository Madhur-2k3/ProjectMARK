import { LightningElement, api, track, wire } from 'lwc';
import getAllSObjectNames from '@salesforce/apex/sObjectsController.getAllSObjectNames';

export default class SObjectCombox extends LightningElement {

    @api hideFilter = false;

    sobjectOptions = [];
    filteredOptions;
    selectedSObject = '';
    @track datatablecolumns=[];
    @track allFieldsForFilter = [];
    @track selectedFields = [];      
    @track requiredFields = [];
    @track finalFieldsForApex = [];  
    @track whereClause = '';
    @track objectLabel = '';
    changed=false;

    searchTerm = '';

    @wire(getAllSObjectNames)
    wiredSObjects({ error, data }) {
        if (data) {
            this.sobjectOptions = data.map(item => ({
                label: item.label,
                value: item.apiName
            }));
            this.filteredOptions = this.sobjectOptions;
        }
    }

    handleSearch(event) {
        this.changed=true;
        
        const key = event.target.value.toLowerCase();
        this.searchTerm = key;

        this.filteredOptions = this.sobjectOptions.filter(opt =>
            opt.label.toLowerCase().includes(key) ||
            opt.value.toLowerCase().includes(key)
        );
        
        
    }

    handleSelect(event) {
        this.selectedSObject = event.currentTarget.dataset.value;
        this.objectLabel=event.currentTarget.dataset.label;
        
        this.objectLabel = event.currentTarget.dataset.label;
        
        this.filteredOptions = null;

        // reset state
        this.selectedFields = [];
        this.finalFieldsForApex = [];
        this.whereClause = '';
        this.searchTerm=this.objectLabel;

        this.dispatchEvent(
    new CustomEvent('objectselected', {
        detail: this.selectedSObject
    })
);

    }

    // RECEIVE FIELDS FROM FIELD SELECTOR
    handleFieldChange(event) {
    const { finalFields, allFields,userSelectedField } = event.detail;

    this.finalFieldsForApex = finalFields;  // SELECT fields
    this.allFieldsForFilter = allFields;
    this.datatablecolumns=userSelectedField.map(field => ({
        label: field.label,
        fieldName: field.value
    })); // User selected fields for datatable
    console.log('All Fields for Filter:', (JSON.stringify(this.allFieldsForFilter))); 
    console.log('SELECT Fields:', (JSON.stringify(this.finalFieldsForApex)));
    console.log('User Selected Fields:', (JSON.stringify(this.datatablecolumns)));
}


    get showFilter() {
        return !this.hideFilter;
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

    const fieldList = this.finalFieldsForApex.map(f => f.apiName).join(', ');

    let q = `SELECT ${fieldList} FROM ${this.selectedSObject}`;

    if (this.whereClause && this.whereClause.trim() !== '') {
        q += ` WHERE ${this.whereClause}`;
    }

    return q;
}



}