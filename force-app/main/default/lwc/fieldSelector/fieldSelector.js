import { LightningElement, api, track, wire } from 'lwc';
import getFieldsBySObject from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class FieldSelector extends LightningElement {
    @api selectedObject;

    @track fieldOptions = [];   // ONLY non-required visible in UI
    @track selectedValues = []; // user + required hidden fields included

    fieldTypeMap = {};
    requiredFields = [];

    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
        if (data) {

            this.fieldOptions = [];
            this.requiredFields = [];
            this.fieldTypeMap = {};

            data.forEach(f => {
                const isRequired = f.isRequired;

                // Always store type
                this.fieldTypeMap[f.apiName] = f.fieldType;

                if (isRequired) {
                    // Collect required but DO NOT show in UI
                    this.requiredFields.push(f.apiName);
                } else {
                    // Only show optional fields in UI
                    this.fieldOptions.push({
                        label: f.label,
                        value: f.apiName
                    });
                }
            });

            // Auto include required fields in selection
            this.selectedValues = [
                ...this.requiredFields
            ];

            this.sendUpdatedFields();
        } 
        else if (error) {
            console.error('Error fetching fields:', error);
        }
    }

    handleChange(event) {
        const userSelected = event.detail.value;

        // Combine user-selected visible fields + hidden required fields
        this.selectedValues = [
            ...this.requiredFields,
            ...userSelected
        ];

        this.sendUpdatedFields();
    }

    sendUpdatedFields() {
        const finalFields = this.selectedValues.map(apiName => ({
            apiName,
            type: this.fieldTypeMap[apiName],
            required: this.requiredFields.includes(apiName)
        }));

        console.log('🔥 Final Fields Sent to Parent:', JSON.stringify(finalFields));

        this.dispatchEvent(
            new CustomEvent('fieldchange', {
                detail: finalFields
            })
        );
    }
}