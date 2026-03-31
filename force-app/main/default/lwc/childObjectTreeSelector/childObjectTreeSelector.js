import { LightningElement, api, track, wire } from 'lwc';
import getChildObjectTree
    from '@salesforce/apex/ChildObjectTreeController.getChildObjectTree';

export default class ChildObjectTreeSelector extends LightningElement {

    @api objectName;

    @track flatNodes = [];   // flattened for template iteration
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    _rawTree = [];

    /* =====================================================
     * WIRE — fetch child tree from Apex
     * ===================================================== */
    @wire(getChildObjectTree, { parentObjectStr: '$objectName' })
    wiredTree({ data, error }) {
        if (data) {
            this.isLoading = false;
            this._rawTree = JSON.parse(JSON.stringify(data));
            this.flatNodes = this._flatten(this._rawTree, 0, null, '');
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

    /* =====================================================
     * PUBLIC API — get selected child object info
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
     *   Each node gets a unique `key` built from its path
     *   in the tree so duplicates across branches work.
     * ===================================================== */
    _flatten(nodes, depth, parentObjectName, parentKey) {
        let flat = [];
        if (!nodes) return flat;

        nodes.forEach((node, idx) => {
            const isLast = idx === nodes.length - 1;
            const relType = node.relationshipType || 'Lookup';

            // Build a unique key using the parent's key + this object's name
            // This ensures the same object under different parents has a distinct identity
            const uniqueKey = parentKey
                ? `${parentKey}__${node.objectApiName}`
                : node.objectApiName;

            flat.push({
                key: uniqueKey,
                parentKey: parentKey || null,
                objectName: node.objectApiName,
                objectLabel: node.objectLabel,
                relationshipField: node.lookupField,
                relationshipName: node.relationshipName,
                parentObjectName: parentObjectName,
                depth: depth,
                isSelected: node.isSelected !== false,
                isMasterDetail: relType === 'Master-Detail',
                isLast: isLast,
                hasChildren: node.children && node.children.length > 0,
                indentStyle: `padding-left: ${depth * 28}px`,
                connector: isLast ? '└── ' : '├── ',
                depthClass: `depth-${depth}`,
                relationshipType: relType,
                relationshipTypeBadgeClass: relType === 'Master-Detail'
                    ? 'tree-rel-badge tree-rel-master-detail'
                    : 'tree-rel-badge tree-rel-lookup'
            });

            if (node.children && node.children.length > 0) {
                flat = flat.concat(
                    this._flatten(node.children, depth + 1, node.objectApiName, uniqueKey)
                );
            }
        });
        return flat;
    }

    /* =====================================================
     * EVENT HANDLERS
     * ===================================================== */
    handleToggle(event) {
        const nodeKey = event.currentTarget.dataset.key;
        const checked = event.target.checked;

        // Find the toggled node
        const toggledNode = this.flatNodes.find(n => n.key === nodeKey);
        if (!toggledNode) return;

        // Update this node
        this.flatNodes = this.flatNodes.map(n => {
            if (n.key === nodeKey) {
                return { ...n, isSelected: checked };
            }
            return n;
        });

        if (!checked) {
            // Unchecked → uncheck all descendants of this node
            this._uncheckDescendants(nodeKey);
        }

        if (checked) {
            // Checked → ensure all ancestors are checked
            this._checkAncestors(nodeKey);
            // For Master-Detail children of this node, auto-select them
            this._autoSelectMasterDetailChildren(nodeKey);
        }

        this._fireSelectionChange();
    }

    handleSelectAll() {
        this.flatNodes = this.flatNodes.map(n => ({ ...n, isSelected: true }));
        this._fireSelectionChange();
    }

    handleDeselectAll() {
        // Cannot deselect Master-Detail children whose parent is selected,
        // so just deselect all for simplicity (parent unchecked = children unchecked)
        this.flatNodes = this.flatNodes.map(n => ({ ...n, isSelected: false }));
        this._fireSelectionChange();
    }

    /* =====================================================
     * HELPERS — cascading check/uncheck using unique keys
     * ===================================================== */

    /**
     * Uncheck all descendants of the node identified by parentKey.
     */
    _uncheckDescendants(parentKey) {
        const toUncheck = new Set();
        const queue = [parentKey];

        while (queue.length > 0) {
            const currentKey = queue.shift();
            this.flatNodes.forEach(n => {
                if (n.parentKey === currentKey && !toUncheck.has(n.key)) {
                    toUncheck.add(n.key);
                    queue.push(n.key);
                }
            });
        }

        this.flatNodes = this.flatNodes.map(n => {
            if (toUncheck.has(n.key)) {
                return { ...n, isSelected: false };
            }
            return n;
        });
    }

    /**
     * Walk up the tree and check all ancestors so the path to root is selected.
     */
    _checkAncestors(nodeKey) {
        const node = this.flatNodes.find(n => n.key === nodeKey);
        if (!node || !node.parentKey) return;

        let currentParentKey = node.parentKey;
        while (currentParentKey) {
            const parentNode = this.flatNodes.find(n => n.key === currentParentKey);
            if (parentNode && !parentNode.isSelected) {
                this.flatNodes = this.flatNodes.map(n => {
                    if (n.key === currentParentKey) {
                        return { ...n, isSelected: true };
                    }
                    return n;
                });
            }
            currentParentKey = parentNode ? parentNode.parentKey : null;
        }
    }

    /**
     * When a parent is checked, auto-select its Master-Detail children
     * (they must be included because they cascade-delete).
     */
    _autoSelectMasterDetailChildren(parentKey) {
        this.flatNodes = this.flatNodes.map(n => {
            if (n.parentKey === parentKey && n.isMasterDetail && !n.isSelected) {
                return { ...n, isSelected: true };
            }
            return n;
        });
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