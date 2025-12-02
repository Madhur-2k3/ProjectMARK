import { LightningElement, track, wire } from 'lwc';
import getAllSObjectNames from '@salesforce/apex/sObjectsController.getAllSObjectNames';
import ModeOptionsLabel from '@salesforce/label/c.ModeOptions';

export default class ObjectAndFieldComboboxSelection extends LightningElement {
    @track objectOptions = [];
    @track selectedSObject = '';
    @track selectedMode = '';
    @track modeOptions = [];

    objectBooleanFlag = false;

    connectedCallback() {
        this.loadMode();
    }

    // ---------------------------
    //   WIRE USING YOUR CLASS
    // ---------------------------
    @wire(getAllSObjectNames)
    wiredSObjects({ error, data }) {
        if (data) {
            this.objectOptions = data.map(obj => ({
                label: obj.label,      // wrapper label
                value: obj.apiName     // wrapper apiName
            }));
            console.log(JSON.stringify(this.objectOptions));
            
        } else if (error) {
            console.error('Error fetching SObject names:', error);
        }
    }

    handleObjectChange(event) {
        this.selectedSObject = event.detail.value;
        this.objectBooleanFlag = !!this.selectedSObject;
        console.log(JSON.stringify(this.selectedSObject));
        
    }

    loadMode() {
        this.modeOptions = ModeOptionsLabel.split(',')
            .map(opt => ({
                label: opt.trim(),
                value: opt.trim()
            }));
    }

    handleModeChange(event) {
        this.selectedMode = event.detail.value;
    }
}