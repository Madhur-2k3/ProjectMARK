import { LightningElement, api, wire, track } from 'lwc';
import getFieldsBySObject
    from '@salesforce/apex/sObjectsController.getFieldsBySObject';

export default class ArchiveScheduleCriteriaModal extends LightningElement {

    @api selectedObject;

    isLoading = true;
    @track fieldsData = [];
    @track currentWhereClause = '';

    // ── Wire: load fields ──
    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
        this.isLoading = true;
        if (data) {
            this.fieldsData = data.map(f => ({
                apiName: f.apiName,
                label:   f.label,
                type:    f.fieldType
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
        return !this.currentWhereClause || this.currentWhereClause.trim() === '';
    }

    // ── Event Handlers ──

    handleWhereClauseChange(event) {
        this.currentWhereClause = event.detail;
    }

    handleNext() {
        this.dispatchEvent(
            new CustomEvent('criteriaselected', {
                detail: {
                    whereClause: this.currentWhereClause
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