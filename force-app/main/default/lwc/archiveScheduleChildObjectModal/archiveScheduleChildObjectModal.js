import { LightningElement, api, track } from 'lwc';

export default class ArchiveScheduleChildObjectModal extends LightningElement {

    @api selectedObject;

    _selectedChildObjects = [];

    // Warning popup state
    @track showWarningPopup = false;
    @track unselectedObjects = [];
    @track unselectedCount = 0;

    /* =====================================================
     * COMPUTED
     * ===================================================== */

    get warningMessage() {
        return `The following ${this.unselectedCount} child object(s) will NOT be archived. Their records will be permanently deleted and cannot be recovered.`;
    }

    get hasUnselectedObjects() {
        return this.unselectedCount > 0;
    }

    /* =====================================================
     * HANDLERS
     * ===================================================== */

    handleSelectionChange(event) {
        this._selectedChildObjects = event.detail.selectedObjects || [];
    }

    handleNext() {
        const treeSelector = this.template.querySelector('c-child-object-tree-selector');

        // Get selected objects
        const selected = treeSelector
            ? treeSelector.getSelectedObjects()
            : this._selectedChildObjects;

        // Get unselected objects
        const unselected = treeSelector
            ? treeSelector.getUnselectedObjects()
            : [];

        if (unselected.length > 0) {
            // Show warning popup with unselected objects
            this.unselectedObjects = unselected;
            this.unselectedCount = unselected.length;
            this._selectedChildObjects = selected;
            this.showWarningPopup = true;
        } else {
            // All selected — proceed directly
            this.dispatchEvent(new CustomEvent('childobjectsselected', {
                detail: { selectedChildObjects: selected }
            }));
        }
    }

    handleWarningConfirm() {
        // User acknowledged the warning — proceed
        this.showWarningPopup = false;
        this.dispatchEvent(new CustomEvent('childobjectsselected', {
            detail: { selectedChildObjects: this._selectedChildObjects }
        }));
    }

    handleWarningCancel() {
        // User wants to go back and change selection
        this.showWarningPopup = false;
    }

    handleSkip() {
        // Skip = pass null so the batch archives ALL cascade-delete children
        this.dispatchEvent(new CustomEvent('childobjectsselected', {
            detail: { selectedChildObjects: null }
        }));
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}