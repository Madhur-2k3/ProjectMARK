import { LightningElement } from 'lwc';

export default class DataArchiveSelection extends LightningElement {

    booleanFlag = true;     // Archive default ON
    unArchiveFlag = false;

    get archiveClass() {
        return this.booleanFlag
            ? 'toggle-btn active'
            : 'toggle-btn';
    }

    get unArchiveClass() {
        return this.unArchiveFlag
            ? 'toggle-btn active'
            : 'toggle-btn';
    }

    activateArchive() {
        this.booleanFlag = true;
        this.unArchiveFlag = false;
    }

    activateUnArchive() {
        this.booleanFlag = false;
        this.unArchiveFlag = true;
    }
}