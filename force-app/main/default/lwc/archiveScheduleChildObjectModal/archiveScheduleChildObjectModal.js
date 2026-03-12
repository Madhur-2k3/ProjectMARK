import { LightningElement, api } from 'lwc';

export default class ArchiveScheduleChildObjectModal extends LightningElement {

    @api selectedObject;

    _selectedChildObjects = [];

    /* =====================================================
     * HANDLERS
     * ===================================================== */

    handleSelectionChange(event) {
        this._selectedChildObjects = event.detail.selectedObjects || [];
    }

    handleNext() {
        // Get selections directly from the child component
        const treeSelector = this.template.querySelector('c-child-object-tree-selector');
        const selected = treeSelector
            ? treeSelector.getSelectedObjects()
            : this._selectedChildObjects;

        this.dispatchEvent(new CustomEvent('childobjectsselected', {
            detail: { selectedChildObjects: selected }
        }));
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
