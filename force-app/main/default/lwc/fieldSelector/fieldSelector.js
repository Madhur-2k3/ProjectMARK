import { LightningElement, api, track, wire } from 'lwc';
import getFieldsBySObject from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class FieldSelector extends LightningElement {
    @api selectedObject;
    @track userSelectedFields=[]
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
                this.fieldTypeMap[f.apiName] = {
    type: f.fieldType,
    label: f.label
};


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
    this.userSelectedFields = userSelected.map(apiName => ({
        label: this.fieldTypeMap[apiName].label,
        value: apiName
    }));

    console.log('🎯 User Selected Only:',(JSON.stringify(this.userSelectedFields)));

    this.sendUpdatedFields();
}


    sendUpdatedFields() {
    // Fields selected (including required ones)
    const finalFields = this.selectedValues.map(apiName => ({
        apiName,
        label: this.fieldTypeMap[apiName].label,
        type: this.fieldTypeMap[apiName].type,
        required: this.requiredFields.includes(apiName)
    }));

    // ALL fields (required + optional)
    const allFields = [
        ...this.fieldOptions.map(opt => ({
            apiName: opt.value,
            label: this.fieldTypeMap[opt.value].label,
            type: this.fieldTypeMap[opt.value].type,
            required: false
        })),
        ...this.requiredFields.map(apiName => ({
            apiName,
            label: this.fieldTypeMap[apiName].label,
            type: this.fieldTypeMap[apiName].type,
            required: true
        }))
    ];

    // Debug
    console.log('📌 All Fields:', JSON.parse(JSON.stringify(allFields)));
    console.log('📌 Selected/Final Fields:', JSON.parse(JSON.stringify(finalFields)));

    // Send to parent
    this.dispatchEvent(
        new CustomEvent('fieldchange', {
            detail: {
                finalFields,
                allFields,
                userSelectedField: this.userSelectedFields 
            }
        })
    );
    }

}