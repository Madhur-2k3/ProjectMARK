import { LightningElement, track } from 'lwc';
import getActiveSchedulesPaginated
    from '@salesforce/apex/DataArchiveScheduleController.getActiveSchedulesPaginated';
import getSchedulesForObjectPaginated
    from '@salesforce/apex/DataArchiveScheduleController.getSchedulesForObjectPaginated';
import deactivateSchedule
    from '@salesforce/apex/DataArchiveScheduleController.deactivateSchedule';

const PAGE_SIZE = 5;

export default class ArchiveScheduleObjectModal extends LightningElement {

    selectedObject;

    // ── All schedules panel ──
    @track allSchedules = [];
    showAllSchedulesPanel = false;
    allCurrentPage = 1;
    allTotalRecords = 0;

    // ── All-schedule datatable columns ──
    allScheduleColumns = [
        { label: 'Object', fieldName: 'objectName', type: 'text' },
        { label: 'Criteria', fieldName: 'dateField', type: 'text' },
        { 
            label: 'Frequency', 
            fieldName: 'frequency', 
            type: 'text',
            cellAttributes: { class: { fieldName: 'frequencyCssClass' } }
        },
        { label: 'Time', fieldName: 'preferredTime', type: 'text' },
        {
            label: 'Status',
            fieldName: 'statusDisplay',
            type: 'text',
            cellAttributes: { class: { fieldName: 'statusCssClass' } }
        }
    ];

    // ── Object-specific schedules ──
    @track objectSchedules = [];
    hasExistingSchedule = false;
    showObjectScheduleTable = false;
    objCurrentPage = 1;
    objTotalRecords = 0;

    // ── Object-schedule datatable columns ──
    objectScheduleColumns = [
        { label: 'Criteria', fieldName: 'dateField', type: 'text' },
        { 
            label: 'Frequency', 
            fieldName: 'frequency', 
            type: 'text',
            cellAttributes: { class: { fieldName: 'frequencyCssClass' } }
        },
        {
            label: 'Status',
            fieldName: 'statusDisplay',
            type: 'text',
            cellAttributes: { class: { fieldName: 'statusCssClass' } }
        }
    ];

    // ── Lifecycle ──
    connectedCallback() {
        this.loadActiveSchedules();
    }

    // ───────────────────────────────────
    //  DATA LOADING (server-side pages)
    // ───────────────────────────────────

    loadActiveSchedules() {
        getActiveSchedulesPaginated({
            pageSize: PAGE_SIZE,
            pageNumber: this.allCurrentPage
        })
            .then(result => {
                this.allSchedules = result.records.map(s => ({
                    ...s,
                    statusDisplay: s.status === 'Active' ? '● Active' : '● In Active',
                    statusCssClass: s.status === 'Active'
                        ? 'slds-text-color_success'
                        : 'slds-text-color_error',
                    frequencyCssClass: this.getFrequencyBadgeClass(s.frequency)
                }));
                this.allTotalRecords = result.totalRecords;
                console.log('All schedules page:', JSON.stringify(result));
            })
            .catch(error => {
                console.error('Error loading schedules:', error);
            });
    }

    loadObjectSchedules() {
        if (!this.selectedObject) {
            this.objectSchedules = [];
            this.hasExistingSchedule = false;
            this.objTotalRecords = 0;
            return;
        }

        getSchedulesForObjectPaginated({
            objectName: this.selectedObject,
            pageSize: PAGE_SIZE,
            pageNumber: this.objCurrentPage
        })
            .then(result => {
                this.objectSchedules = result.records.map(s => ({
                    ...s,
                    isActive: s.status === 'Active',
                    statusDisplay: s.status === 'Active' ? '● Active' : '● In Active',
                    statusCssClass: s.status === 'Active'
                        ? 'slds-text-color_success'
                        : 'slds-text-color_error',
                    frequencyCssClass: this.getFrequencyBadgeClass(s.frequency)
                }));
                this.objTotalRecords = result.totalRecords;
                this.hasExistingSchedule = result.totalRecords > 0;
                console.log('Object schedules page:', JSON.stringify(result));
            })
            .catch(error => {
                console.error('Error checking object schedules:', error);
                this.objectSchedules = [];
                this.hasExistingSchedule = false;
                this.objTotalRecords = 0;
            });
    }

    // ───────────────────────────────────
    //  GETTERS & HELPERS
    // ───────────────────────────────────
    
    getFrequencyBadgeClass(frequency) {
        if (!frequency) return 'slds-badge';
        const freq = frequency.toUpperCase();
        if (freq === 'DAILY') {
            return 'slds-badge slds-theme_success';
        } else if (freq === 'WEEKLY') {
            return 'slds-badge slds-theme_warning';
        } else if (freq === 'MONTHLY') {
            return 'slds-badge slds-theme_info';
        } else if (freq === 'YEARLY') {
            return 'slds-badge slds-theme_error';
        }
        return 'slds-badge';
    }

    get isDisabled() {
        return !this.selectedObject;
    }

    get hasAllSchedules() {
        return this.allSchedules && this.allSchedules.length > 0;
    }

    get allSchedulesCount() {
        return String(this.allTotalRecords);
    }

    get allSchedulesToggleLabel() {
        return this.showAllSchedulesPanel
            ? 'Hide All Schedules'
            : 'View All Schedules';
    }

    // ── All-schedules pagination getters ──

    get allTotalPages() {
        return Math.max(1, Math.ceil(this.allTotalRecords / PAGE_SIZE));
    }

    get allPageInfo() {
        return `Page ${this.allCurrentPage} of ${this.allTotalPages}`;
    }

    get isAllPreviousDisabled() {
        return this.allCurrentPage <= 1;
    }

    get isAllNextDisabled() {
        return this.allCurrentPage >= this.allTotalPages;
    }

    // ── Object-schedules getters ──

    get objectScheduleCount() {
        return String(this.objTotalRecords);
    }

    get objectScheduleToggleLabel() {
        return this.showObjectScheduleTable ? 'Hide Details' : 'View Details';
    }

    // ── Object-schedules pagination getters ──

    get objTotalPages() {
        return Math.max(1, Math.ceil(this.objTotalRecords / PAGE_SIZE));
    }

    get objPageInfo() {
        return `Page ${this.objCurrentPage} of ${this.objTotalPages}`;
    }

    get isObjPreviousDisabled() {
        return this.objCurrentPage <= 1;
    }

    get isObjNextDisabled() {
        return this.objCurrentPage >= this.objTotalPages;
    }

    // ───────────────────────────────────
    //  ACTIONS
    // ───────────────────────────────────

    toggleAllSchedulesPanel() {
        this.showAllSchedulesPanel = !this.showAllSchedulesPanel;
    }

    toggleObjectScheduleTable() {
        this.showObjectScheduleTable = !this.showObjectScheduleTable;
    }

    // ── All-schedules pagination ──

    handleAllPreviousPage() {
        if (this.allCurrentPage > 1) {
            this.allCurrentPage--;
            this.loadActiveSchedules();
        }
    }

    handleAllNextPage() {
        if (this.allCurrentPage < this.allTotalPages) {
            this.allCurrentPage++;
            this.loadActiveSchedules();
        }
    }

    // ── Object-schedules pagination ──

    handleObjPreviousPage() {
        if (this.objCurrentPage > 1) {
            this.objCurrentPage--;
            this.loadObjectSchedules();
        }
    }

    handleObjNextPage() {
        if (this.objCurrentPage < this.objTotalPages) {
            this.objCurrentPage++;
            this.loadObjectSchedules();
        }
    }

    // ── Object selection ──

    handleObjectSelected(event) {
        this.selectedObject = event.detail;
        this.showObjectScheduleTable = false;
        this.objCurrentPage = 1;
        this.loadObjectSchedules();
    }

    handleConfirm() {
        this.dispatchEvent(
            new CustomEvent('objectselected', {
                detail: this.selectedObject
            })
        );
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}