import { LightningElement, api } from 'lwc';

/**
 * Reusable modal shell component.
 *
 * @slot default  – Body content (projected into modal content area)
 * @slot footer   – Footer buttons
 * @slot header-extra – Extra header content (step indicators, badges, etc.)
 *
 * Usage:
 * <c-generic-modal modal-title="My Title" size="large" header-variant="brand"
 *                  icon-name="utility:archive" subtitle="Step 1 of 3"
 *                  onclose={handleClose}>
 *     <!-- body content -->
 *     <div slot="footer">
 *         <lightning-button label="Cancel" onclick={handleCancel}></lightning-button>
 *         <lightning-button label="Save" variant="brand" onclick={handleSave}></lightning-button>
 *     </div>
 * </c-generic-modal>
 */
export default class GenericModal extends LightningElement {

    /** Modal heading text */
    @api modalTitle = '';

    /** Size: '' (default) | 'medium' | 'large' */
    @api size = '';

    /** Header theme: 'default' | 'brand' | 'warning' | 'inverse' */
    @api headerVariant = 'default';

    /** Optional SLDS icon name shown before title, e.g. 'utility:archive' */
    @api iconName = '';

    /** Optional subtitle text below the title */
    @api subtitle = '';

    /** If true, hides the close (X) button */
    @api hideClose = false;

    /** Footer direction: '' (default right-aligned) | 'directional' (space-between) */
    @api footerDirectional = false;

    // ───────────────────────────────────
    //  Computed CSS classes
    // ───────────────────────────────────

    get modalSectionClass() {
        let cls = 'slds-modal slds-fade-in-open';
        if (this.size === 'large') cls += ' slds-modal_large';
        if (this.size === 'medium') cls += ' slds-modal_medium';
        return cls;
    }

    get modalContainerClass() {
        let cls = 'slds-modal__container';
        if (this.size === 'large') cls += ' slds-modal__container_large';
        return cls;
    }

    get headerClass() {
        const variant = this.headerVariant;
        let cls = 'slds-modal__header';
        if (variant === 'brand') cls += ' gm-header-brand';
        else if (variant === 'warning') cls += ' gm-header-warning';
        else if (variant === 'inverse') cls += ' gm-header-inverse';
        return cls;
    }

    get headerContentClass() {
        return this.iconName ? 'gm-header-content' : 'gm-header-content gm-no-icon';
    }

    get closeButtonClass() {
        const variant = this.headerVariant;
        let cls = 'slds-button slds-button_icon slds-modal__close';
        if (variant === 'brand' || variant === 'inverse') {
            cls += ' slds-button_icon-inverse';
        }
        return cls;
    }

    get closeIconVariant() {
        const v = this.headerVariant;
        return (v === 'brand' || v === 'inverse') ? 'inverse' : '';
    }

    get titleClass() {
        const v = this.headerVariant;
        let cls = 'slds-modal__title slds-hyphenate';
        if (v === 'brand' || v === 'inverse') cls += ' gm-title-light';
        return cls;
    }

    get subtitleClass() {
        const v = this.headerVariant;
        return (v === 'brand' || v === 'inverse')
            ? 'gm-subtitle gm-subtitle-light'
            : 'gm-subtitle';
    }

    get bodyClass() {
        return 'slds-modal__content slds-p-around_medium';
    }

    get footerClass() {
        let cls = 'slds-modal__footer';
        if (this.footerDirectional) cls += ' slds-modal__footer_directional';
        return cls;
    }

    // ───────────────────────────────────
    //  Actions
    // ───────────────────────────────────

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}