import { LightningElement, api, track, wire } from 'lwc';
import getFieldsBySObject from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class FieldSelector extends LightningElement {
    @api selectedObject;
    @track userSelectedFields=[]
    @track fieldOptions = [];   // ONLY non-required visible in UI
    @track selectedValues = []; // user + required hidden fields included

    fieldTypeMap = {};
    requiredFields = [];

//     @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
//     wiredFields({ data, error }) {
//         if (data) {

//             this.fieldOptions = [];
//             this.requiredFields = [];
//             this.fieldTypeMap = {};

//             data.forEach(f => {
//     // store type & label
//     this.fieldTypeMap[f.apiName] = {
//         type: f.fieldType,
//         label: f.label
//     };

//     // store required fields (but DO NOT auto select)
//     if (f.isRequired) {
//         this.requiredFields.push(f.apiName);
//     }

//     // ALL fields appear in UI (required + optional)
//     this.fieldOptions.push({
//         label: f.label, // show required with *
//         value: f.apiName
//     });
// });


            
//             this.selectedValues = [
                
//             ];

//             this.sendUpdatedFields();
//         } 
//         else if (error) {
//             console.error('Error fetching fields:', error);
//         }
//     }
    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
    if (data) {

        // Reset
        this.fieldOptions = [];
        this.requiredFields = [];
        this.fieldTypeMap = {};

        // ⭐ SORT fields by label
        let sortedData = [...data].sort((a, b) =>
            a.label.localeCompare(b.label)
        );

        sortedData.forEach(f => {
            // Store type & label
            this.fieldTypeMap[f.apiName] = {
                type: f.fieldType,
                label: f.label
            };

            // Required fields
            if (f.isRequired) {
                this.requiredFields.push(f.apiName);
            }

            // Fields for UI dropdown (sorted)
            this.fieldOptions.push({
                label: f.label,
                value: f.apiName
            });
        });

        this.selectedValues = [];
        this.sendUpdatedFields();
    } else if (error) {
        console.error('Error fetching fields:', error);
    }
}


    handleChange(event) {
    let selectedValues = event.detail.value;

    // Remove duplicates using Set
    this.selectedValues = [...new Set(selectedValues)];

    // Build user-readable selected fields
    this.userSelectedFields = this.selectedValues.map(apiName => ({
        label: this.fieldTypeMap[apiName].label,
        value: apiName,
        required: this.requiredFields.includes(apiName)
    }));

    console.log("Selected Fields:", JSON.stringify(this.userSelectedFields));

    this.sendUpdatedFields();
}



    sendUpdatedFields() {
    // 1️⃣ Combine required + user-selected fields
    const uniqueApiNames = Array.from(
        new Set([...this.requiredFields, ...this.selectedValues])
    );

    // 2️⃣ Build final fields list (sent to Apex)
    const finalFields = uniqueApiNames.map(apiName => ({
        apiName,
        label: this.fieldTypeMap[apiName].label,
        type: this.fieldTypeMap[apiName].type,
        required: this.requiredFields.includes(apiName)
    }));

    // 3️⃣ Build ALL fields list (NO duplicates)
    const allFields = Array.from(
        new Set(Object.keys(this.fieldTypeMap))
    ).map(apiName => ({
        apiName,
        label: this.fieldTypeMap[apiName].label,
        type: this.fieldTypeMap[apiName].type,
        required: this.requiredFields.includes(apiName)
    }));

    console.log("📌 Final Fields (sent to Apex):", JSON.parse(JSON.stringify(finalFields)));
    console.log("📌 All Fields:", JSON.parse(JSON.stringify(allFields)));

    // 4️⃣ Send to parent
    this.dispatchEvent(
        new CustomEvent('fieldchange', {
            detail: {
                finalFields,       // will be used for Apex SOQL
                allFields,         // full list for table generation
                userSelectedField: this.userSelectedFields
            }
        })
    );
}
    handleIncludeAllFieldsChange(event){
        this.includeAllFields = event.target.checked;
        if(this.includeAllFields){
            // Select all fields
            this.selectedValues = this.fieldOptions
                .filter(opt => opt.value !== '__ALL__')
                .map(opt => opt.value);
        } else {
            // Deselect all fields
            this.selectedValues = [];
        }
        // Update userSelectedFields accordingly
        this.userSelectedFields = this.selectedValues.map(apiName => ({
            label: this.fieldTypeMap[apiName]?.label,
            value: apiName,
            required: this.requiredFields.includes(apiName)
        }));
        this.sendUpdatedFields();
    }


}