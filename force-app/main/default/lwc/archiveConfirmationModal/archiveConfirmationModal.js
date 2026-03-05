import { LightningElement, api, track } from 'lwc';

export default class ArchiveConfirmationModal extends LightningElement {

    @api parentObjectName = '';
    @api parentRecordCount = 0;
    @api selectedChildSummary = [];   // [{ objectName, objectLabel, count }]
    @api unselectedChildSummary = []; // [{ objectName, objectLabel, count }]

    @track confirmText = '';

    /* =====================================================
     * COMPUTED PROPERTIES
     * ===================================================== */
    get hasSelectedChildren() {
        return this.selectedChildSummary && this.selectedChildSummary.length > 0;
    }

    get hasUnselectedChildren() {
        return this.unselectedChildSummary && this.unselectedChildSummary.length > 0;
    }

    get isConfirmDisabled() {
        return this.confirmText.trim().toUpperCase() !== 'CONFIRM';
    }

    /* =====================================================
     * EVENT HANDLERS
     * ===================================================== */
    handleConfirmTextChange(event) {
        this.confirmText = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleConfirm() {
        if (!this.isConfirmDisabled) {
            this.dispatchEvent(new CustomEvent('confirm'));
        }
    }
}