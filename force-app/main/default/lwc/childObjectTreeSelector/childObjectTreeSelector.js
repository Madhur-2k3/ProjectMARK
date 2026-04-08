import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getChildObjectTree
    from '@salesforce/apex/ChildObjectTreeController.getChildObjectTree';

export default class ChildObjectTreeSelector extends LightningElement {

    @api objectName;

    @track flatNodes = [];   // flattened for template iteration
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    // Root node (selected parent object) info
    @track rootObjectLabel = '';
    @track rootObjectApiName = '';

    _rawTree = [];

    /* =====================================================
     * WIRE — resolve the parent object label via getObjectInfo
     * ===================================================== */
    @wire(getObjectInfo, { objectApiName: '$objectName' })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.rootObjectLabel = data.label || this.objectName;
            this.rootObjectApiName = data.apiName || this.objectName;
        } else if (error) {
            this.rootObjectLabel = this.objectName;
            this.rootObjectApiName = this.objectName;
        }
    }

    /* =====================================================
     * WIRE — fetch child tree from Apex
     * ===================================================== */
    @wire(getChildObjectTree, { objectName: '$objectName' })
    wiredTree({ data, error }) {
        if (data) {
            this.isLoading = false;
            this._rawTree = JSON.parse(JSON.stringify(data));
            this.flatNodes = this._flatten(this._rawTree, 0);
            this.hasError = false;
            this._fireSelectionChange();
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            this.errorMessage = error?.body?.message || 'Failed to load child objects.';
            this._rawTree = [];
            this.flatNodes = [];
        }
        // When both data & error are undefined (initial wire call), keep isLoading = true
    }

    /* =====================================================
     * COMPUTED
     * ===================================================== */
    get hasChildren() {
        return this.flatNodes.length > 0;
    }

    get selectedCount() {
        return this.flatNodes.filter(n => n.isSelected).length;
    }

    get totalCount() {
        return this.flatNodes.length;
    }

    get selectionSummary() {
        return `${this.selectedCount} of ${this.totalCount} child objects selected`;
    }

    get showRootNode() {
        return this.rootObjectLabel && this.hasChildren;
    }

    get rootNodeLabel() {
        return this.rootObjectLabel || this.objectName;
    }

    get rootNodeApiName() {
        return this.rootObjectApiName || this.objectName;
    }

    /* =====================================================
     * PUBLIC API — get selected child object names
     * ===================================================== */
    @api
    getSelectedObjects() {
        return this.flatNodes
            .filter(n => n.isSelected)
            .map(n => n.objectName);
    }

    @api
    getUnselectedObjects() {
        return this.flatNodes
            .filter(n => !n.isSelected)
            .map(n => ({ objectName: n.objectName, objectLabel: n.objectLabel }));
    }

    /* =====================================================
     * FLATTEN — convert tree into flat list with depth info
     * ===================================================== */
    _flatten(nodes, depth) {
        let flat = [];
        if (!nodes) return flat;

        nodes.forEach((node, idx) => {
            const isLast = idx === nodes.length - 1;
            const relType = node.relationshipType || 'Lookup';
            flat.push({
                key: node.objectName,
                objectName: node.objectName,
                objectLabel: node.objectLabel,
                relationshipField: node.relationshipField,
                parentObjectName: node.parentObjectName,
                depth: depth,
                isSelected: node.isSelected !== false,
                isLast: isLast,
                hasChildren: node.children && node.children.length > 0,
                indentStyle: `padding-left: ${(depth + 1) * 28}px`,
                connector: isLast ? '└── ' : '├── ',
                depthClass: `depth-${depth}`,
                relationshipType: relType,
                relationshipTypeBadgeClass: relType === 'Master-Detail'
                    ? 'tree-rel-badge tree-rel-master-detail'
                    : 'tree-rel-badge tree-rel-lookup'
            });

            if (node.children && node.children.length > 0) {
                flat = flat.concat(this._flatten(node.children, depth + 1));
            }
        });
        return flat;
    }

    /* =====================================================
     * EVENT HANDLERS
     * ===================================================== */
    handleToggle(event) {
        const objectName = event.currentTarget.dataset.object;
        const checked = event.target.checked;

        // Update this node
        this.flatNodes = this.flatNodes.map(n => {
            if (n.objectName === objectName) {
                return { ...n, isSelected: checked };
            }
            return n;
        });

        // If unchecked → uncheck all descendants
        if (!checked) {
            this._uncheckDescendants(objectName);
        }

        // If checked → ensure all ancestors are checked
        if (checked) {
            this._checkAncestors(objectName);
        }

        this._fireSelectionChange();
    }

    handleSelectAll() {
        this.flatNodes = this.flatNodes.map(n => ({ ...n, isSelected: true }));
        this._fireSelectionChange();
    }

    handleDeselectAll() {
        this.flatNodes = this.flatNodes.map(n => ({ ...n, isSelected: false }));
        this._fireSelectionChange();
    }

    /* =====================================================
     * HELPERS — cascading check/uncheck
     * ===================================================== */
    _uncheckDescendants(parentObjectName) {
        // Find all objects whose parentObjectName traces back to the given parent
        const toUncheck = new Set();
        const queue = [parentObjectName];

        while (queue.length > 0) {
            const current = queue.shift();
            this.flatNodes.forEach(n => {
                if (n.parentObjectName === current && !toUncheck.has(n.objectName)) {
                    toUncheck.add(n.objectName);
                    queue.push(n.objectName);
                }
            });
        }

        this.flatNodes = this.flatNodes.map(n => {
            if (toUncheck.has(n.objectName)) {
                return { ...n, isSelected: false };
            }
            return n;
        });
    }

    _checkAncestors(objectName) {
        const node = this.flatNodes.find(n => n.objectName === objectName);
        if (!node || !node.parentObjectName) return;

        // Walk up the tree
        let currentParent = node.parentObjectName;
        while (currentParent && currentParent !== this.objectName) {
            const parentNode = this.flatNodes.find(n => n.objectName === currentParent);
            if (parentNode && !parentNode.isSelected) {
                this.flatNodes = this.flatNodes.map(n => {
                    if (n.objectName === currentParent) {
                        return { ...n, isSelected: true };
                    }
                    return n;
                });
            }
            currentParent = parentNode ? parentNode.parentObjectName : null;
        }
    }

    /* =====================================================
     * DISPATCH — notify parent of selection changes
     * ===================================================== */
    _fireSelectionChange() {
        const selected = this.getSelectedObjects();
        this.dispatchEvent(new CustomEvent('selectionchange', {
            detail: { selectedObjects: selected }
        }));
    }
}