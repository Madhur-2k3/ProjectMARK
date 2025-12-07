import { LightningElement, api, track } from 'lwc';

export default class CapsuleDropdown extends LightningElement {

    @api options = [];
    @api value = null;

    @track isOpen = false;
    @track selectedLabel = "Select";

    connectedCallback() {
        const selected = this.options.find(o => o.value === this.value);
        if (selected) {
            this.selectedLabel = selected.label;
        }
    }

    toggleDropdown() {
        this.isOpen = !this.isOpen;
    }

    handleSelect(event) {
        const value = event.currentTarget.dataset.value;
        const option = this.options.find(o => o.value === value);

        this.selectedLabel = option.label;
        this.value = value;
        this.isOpen = false;

        this.dispatchEvent(new CustomEvent("change", {
            detail: { value }
        }));
    }
}