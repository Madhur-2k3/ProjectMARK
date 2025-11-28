import { LightningElement, track, wire } from 'lwc';
import getSOBjectNames from '@salesforce/apex/ObjectController.getSObjectNames';
import ModeOptionsLabel from '@salesforce/label/c.ModeOptions';

export default class ObjectAndFieldComboboxSelection extends LightningElement {
    @track objectOptions = [];
    @track selectedSObject = '';
    @track selectedMode = '';
    @track modeOptions =[];

    connectedCallback(){
        this.loadMode();
    }
    objectBooleanFlag = false;

    @wire(getSOBjectNames)
    wiredSObjectNames({ error, data }) {
        if (data) {
            this.objectOptions = data.map(objName => ({
                label: objName.label,
                value: objName.apiName
            }));
            
        }
        else if (error) {
            console.error('Error fetching SObject names:', error);
        }

    }

    handleObjectChange(event) {
        this.selectedSObject = event.detail.value;
        if(this.selectedSObject){
            this.objectBooleanFlag = true;
        }
    }  
    
    loadMode(){
        this.modeOptions = ModeOptionsLabel.split(',').map(option => ({
            label: option.trim(),
            value: option.trim()
        }));
    }
    handleModeChange(event) {
        this.selectedMode = event.detail.value;
    }
}