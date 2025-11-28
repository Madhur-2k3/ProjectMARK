import { LightningElement, track } from 'lwc';
import radioOptionsLabel from '@salesforce/label/c.Radio_Button_options';

export default class DataArchiveSelection extends LightningElement {
    value = '';
    booleanFlag =false;
    unArchiveFlag = false;
    @track options = [];

    connectedCallback(){
        this.loadOptions();
    }

    loadOptions(){
        this.options = radioOptionsLabel.split(',').map(option => ({
            label: option.trim(),
            value: option.trim()
        }));
    }


    handleChange(event){
        this.value = event.detail.value;
        if(this.value === 'Archive'){
            this.booleanFlag = true;
            this.unArchiveFlag = false;
        }
        else if(this.value === 'Un-Archive'){
            this.unArchiveFlag = true;
            this.booleanFlag = false;
        }
    }
}