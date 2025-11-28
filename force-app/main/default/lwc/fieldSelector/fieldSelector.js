import { LightningElement, api, track, wire } from 'lwc';
import getFieldsBySObject from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class FieldSelector extends LightningElement {

    @api selectedObject;

    @track fieldOptions = [];
    @track selectedFieldOptions = [];
    leftSelected = [];
    rightSelected = [];

    // Wire with dynamic parameter
    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
        if (data) {
            this.fieldOptions = data.map(f => ({
                label: f.label,
                value: f.apiName,
                type:f.fieldType
            }));
            this.selectedFieldOptions = []; // Reset when object changes
        } 
        else if (error) {
            console.error('Error loading fields:', error);
        }
    }

    handleLeftSelection(event) {
        this.leftSelected = event.target.value;
    }

    handleRightSelection(event) {
        this.rightSelected = event.target.value;
    }

    moveRight() {
        if (!this.leftSelected.length) return;

        let moved = this.fieldOptions.filter(f => this.leftSelected.includes(f.value));
        this.selectedFieldOptions = [...this.selectedFieldOptions, ...moved];
        console.log(JSON.stringify(this.selectedFieldOptions));
        this.fieldOptions = this.fieldOptions.filter(
            f => !this.leftSelected.includes(f.value)
        );

        this.leftSelected = [];
    }

    moveLeft() {
        if (!this.rightSelected.length) return;

        let moved = this.selectedFieldOptions.filter(f => this.rightSelected.includes(f.value));
        this.fieldOptions = [...this.fieldOptions, ...moved];

        this.selectedFieldOptions = this.selectedFieldOptions.filter(
            f => !this.rightSelected.includes(f.value)
        );

        this.rightSelected = [];
    }
}