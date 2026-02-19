import { LightningElement, track } from 'lwc';
import getActiveSchedules
    from '@salesforce/apex/DataArchiveScheduleController.getActiveSchedules';
import getSchedulesForObject
    from '@salesforce/apex/DataArchiveScheduleController.getSchedulesForObject';
import deactivateSchedule
    from '@salesforce/apex/DataArchiveScheduleController.deactivateSchedule';

export default class ArchiveScheduleObjectModal extends LightningElement {

    selectedObject;

    // ── All schedules panel ──
    @track allSchedules = [];
    showAllSchedulesPanel = false;

    // ── Object-specific schedules ──
    @track objectSchedules = [];
    hasExistingSchedule = false;
    showObjectScheduleTable = false;

    // ── Load all active schedules (imperative — method does DML) ──
    connectedCallback() {
        this.loadActiveSchedules();
    }

    loadActiveSchedules() {
        getActiveSchedules()
            .then(data => {
                this.allSchedules = data;
            })
            .catch(error => {
                console.error('Error loading schedules:', error);
            });
    }

    // ───────────────────────────────────
    //  GETTERS
    // ───────────────────────────────────

    get isDisabled() {
        return !this.selectedObject;
    }

    get hasAllSchedules() {
        return this.allSchedules && this.allSchedules.length > 0;
    }

    get allSchedulesCount() {
        return this.allSchedules ? String(this.allSchedules.length) : '0';
    }

    get allSchedulesToggleLabel() {
        return this.showAllSchedulesPanel
            ? 'Hide All Schedules'
            : 'View All Schedules';
    }

    get objectScheduleCount() {
        return this.objectSchedules ? String(this.objectSchedules.length) : '0';
    }

    get objectScheduleToggleLabel() {
        return this.showObjectScheduleTable ? 'Hide Details' : 'View Details';
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

    handleObjectSelected(event) {
        this.selectedObject = event.detail;
        this.showObjectScheduleTable = false;
        this.checkObjectSchedules();
    }

    checkObjectSchedules() {
        if (!this.selectedObject) {
            this.objectSchedules = [];
            this.hasExistingSchedule = false;
            return;
        }

        getSchedulesForObject({ objectName: this.selectedObject })
            .then(result => {
                this.objectSchedules = result;
                this.hasExistingSchedule = result && result.length > 0;
            })
            .catch(error => {
                console.error('Error checking object schedules:', error);
                this.objectSchedules = [];
                this.hasExistingSchedule = false;
            });
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