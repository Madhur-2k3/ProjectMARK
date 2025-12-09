import { LightningElement, api } from 'lwc';

export default class DynamicDataTable extends LightningElement {
    // ---------------- UNARCHIVE TABLE (DO NOT CHANGE THESE) ----------------
    @api data = [];                 // Records for unarchive
    @api columns = [];              // Columns for unarchive
    @api keyField = 'Id';
    @api selectedRows = [];         // Selected rows for unarchive
    @api maxRowSelection;           // LIMIT selection for unarchive ONLY
    @api unarchivemode = false;    // Enable multi-row selection for unarchive ONLY
    // ---------------- ARCHIVE TABLE (SEPARATE VARIABLES) -------------------
    @api archivedata = [];          // Records for archive
    @api archivecolumns = [];       // Columns for archive
    @api archiveSelectedRows = [];  // Selected rows for archive

    // ---------------- SWITCH CONTROL -------------------
    @api showArchiveTable = false;  // Boolean to pick which table shows

    // ---------------- EVENTS -------------------
    handleRowSelection(event) {
        const selected = event.detail.selectedRows || [];
        this.dispatchEvent(new CustomEvent('rowselection', { detail: selected }));
    }

    handleArchiveSelection(event) {
        this.archiveSelectedRows = event.detail.selectedRows || [];
        this.dispatchEvent(new CustomEvent('archiverowselection', {
    detail: { selectedRows: this.archiveSelectedRows }
}));

    }
    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        this.dispatchEvent(new CustomEvent('rowaction', {
            detail: { action, row }
        }));
    }
}