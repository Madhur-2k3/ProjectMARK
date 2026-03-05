import { LightningElement, api, track } from 'lwc';
import getChildRecordsByParentIds from '@salesforce/apex/sObjectsController.getChildRecordsByParentIds';

export default class ChildObjectSelectionModal extends LightningElement {

    @api parentObjectName = '';
    @api selectedParentRecordIds = [];

    @track childObjectSections = [];
    @track isLoading = true;

    // Track selected IDs per child object
    _selectedMap = {}; // { childObjectName: Set<Id> }

    get selectedParentRecordCount() {
        return this.selectedParentRecordIds ? this.selectedParentRecordIds.length : 0;
    }

    get hasNoChildRecords() {
        return !this.isLoading && this.childObjectSections.length === 0;
    }

    get totalSelectedChildRecords() {
        let total = 0;
        for (const key of Object.keys(this._selectedMap)) {
            total += this._selectedMap[key].size;
        }
        return total;
    }

    get totalUnselectedChildRecords() {
        let total = 0;
        this.childObjectSections.forEach(section => {
            const selected = this._selectedMap[section.childObjectName]
                ? this._selectedMap[section.childObjectName].size : 0;
            total += section.recordCount - selected;
        });
        return total;
    }

    get hasUnselectedRecords() {
        return this.totalUnselectedChildRecords > 0;
    }

    connectedCallback() {
        this.fetchChildRecords();
    }

    async fetchChildRecords() {
        this.isLoading = true;
        try {
            const result = await getChildRecordsByParentIds({
                parentObjectApiName: this.parentObjectName,
                parentRecordIds: this.selectedParentRecordIds
            });

            this._selectedMap = {};
            this.childObjectSections = result.map(wrapper => {
                // By default, select ALL child records
                const allIds = wrapper.records.map(r => r.Id);
                this._selectedMap[wrapper.childObjectName] = new Set(allIds);

                // Build columns dynamically
                const columns = [{ label: 'Record ID', fieldName: 'Id', type: 'text' }];
                if (wrapper.records.length > 0 && wrapper.records[0].Name !== undefined) {
                    columns.unshift({ label: 'Name', fieldName: 'Name', type: 'text' });
                }

                return {
                    childObjectName: wrapper.childObjectName,
                    childObjectLabel: wrapper.childObjectLabel || wrapper.childObjectName,
                    relationshipField: wrapper.relationshipField,
                    recordCount: wrapper.recordCount,
                    records: wrapper.records,
                    columns: columns,
                    selectedRowIds: [...allIds],
                    selectedCount: allIds.length,
                    isExpanded: true,
                    expandIcon: 'utility:chevrondown'
                };
            });
        } catch (error) {
            console.error('Error fetching child records:', error);
            this.childObjectSections = [];
        } finally {
            this.isLoading = false;
        }
    }

    /* =====================================================
     * SECTION EXPAND / COLLAPSE
     * ===================================================== */
    toggleSection(event) {
        const objectName = event.currentTarget.dataset.object;
        this.childObjectSections = this.childObjectSections.map(section => {
            if (section.childObjectName === objectName) {
                const expanded = !section.isExpanded;
                return {
                    ...section,
                    isExpanded: expanded,
                    expandIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return section;
        });
    }

    /* =====================================================
     * ROW SELECTION
     * ===================================================== */
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        // Find which section this datatable belongs to
        const tableEl = event.target;
        const objectName = tableEl.dataset.object;

        if (!objectName) return;

        const selectedIds = new Set(selectedRows.map(r => r.Id));
        this._selectedMap[objectName] = selectedIds;

        this.childObjectSections = this.childObjectSections.map(section => {
            if (section.childObjectName === objectName) {
                return {
                    ...section,
                    selectedRowIds: [...selectedIds],
                    selectedCount: selectedIds.size
                };
            }
            return section;
        });
    }

    /* =====================================================
     * SELECT ALL / DESELECT ALL
     * ===================================================== */
    handleSelectAll(event) {
        const objectName = event.currentTarget.dataset.object;
        const section = this.childObjectSections.find(s => s.childObjectName === objectName);
        if (!section) return;

        const allIds = section.records.map(r => r.Id);
        this._selectedMap[objectName] = new Set(allIds);

        this.childObjectSections = this.childObjectSections.map(s => {
            if (s.childObjectName === objectName) {
                return {
                    ...s,
                    selectedRowIds: [...allIds],
                    selectedCount: allIds.length
                };
            }
            return s;
        });
    }

    handleDeselectAll(event) {
        const objectName = event.currentTarget.dataset.object;
        this._selectedMap[objectName] = new Set();

        this.childObjectSections = this.childObjectSections.map(s => {
            if (s.childObjectName === objectName) {
                return {
                    ...s,
                    selectedRowIds: [],
                    selectedCount: 0
                };
            }
            return s;
        });
    }

    /* =====================================================
     * MODAL ACTIONS
     * ===================================================== */
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleProceed() {
        // Build summary of selected and unselected child records
        const selectedChildRecords = {};
        const unselectedChildRecords = {};
        const selectedChildSummary = [];
        const unselectedChildSummary = [];

        this.childObjectSections.forEach(section => {
            const selectedIds = this._selectedMap[section.childObjectName]
                ? [...this._selectedMap[section.childObjectName]]
                : [];
            const allIds = section.records.map(r => r.Id);
            const unselectedIds = allIds.filter(id => !selectedIds.includes(id));

            if (selectedIds.length > 0) {
                selectedChildRecords[section.childObjectName] = selectedIds;
                selectedChildSummary.push({
                    objectName: section.childObjectName,
                    objectLabel: section.childObjectLabel,
                    count: selectedIds.length
                });
            }

            if (unselectedIds.length > 0) {
                unselectedChildRecords[section.childObjectName] = unselectedIds;
                unselectedChildSummary.push({
                    objectName: section.childObjectName,
                    objectLabel: section.childObjectLabel,
                    count: unselectedIds.length
                });
            }
        });

        this.dispatchEvent(new CustomEvent('proceed', {
            detail: {
                selectedChildRecords,
                unselectedChildRecords,
                selectedChildSummary,
                unselectedChildSummary
            }
        }));
    }
}