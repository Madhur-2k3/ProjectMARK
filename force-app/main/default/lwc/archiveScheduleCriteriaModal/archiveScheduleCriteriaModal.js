import { LightningElement, api, wire, track } from 'lwc';
import getFieldsBySObject
    from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class ArchiveScheduleCriteriaModal extends LightningElement {

    @api selectedObject;

    isLoading = true;
    @track fieldsData = [];
    @track currentWhereClause = '';
    @track scheduleName = '';

    // Auto-populate schedule name with object + today's date
    connectedCallback() {
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        const dateStr = `${yyyy}-${mm}-${dd}`;
        this.scheduleName = `${this.selectedObject || 'Archive'} - ${dateStr}`;
    }

    // ── Wire: load fields ──
    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
        this.isLoading = true;
        if (data) {
            this.fieldsData = data.map(f => ({
                apiName: f.apiName,
                label: f.label,
                type: f.fieldType
            }));
            this.isLoading = false;
        } else if (error) {
            console.error('Error loading fields:', error);
            this.fieldsData = [];
            this.isLoading = false;
        }
    }

    // ── Getters ──

    get isNextDisabled() {
        return !this.currentWhereClause || this.currentWhereClause.trim() === '' ||
            !this.scheduleName || this.scheduleName.trim() === '';
    }

    // ── Event Handlers ──

    handleWhereClauseChange(event) {
        this.currentWhereClause = event.detail;
    }

    handleNameChange(event) {
        this.scheduleName = event.detail.value;
    }

    handleNext() {
        this.dispatchEvent(
            new CustomEvent('criteriaselected', {
                detail: {
                    whereClause: this.currentWhereClause,
                    scheduleName: this.scheduleName
                }
            })
        );
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}