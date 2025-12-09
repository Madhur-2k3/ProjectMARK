import { LightningElement, api } from 'lwc';

export default class FieldValidator extends LightningElement {
    _value;
    _type;
    @api message = "";
    @api fieldName = "";   // optional if needed later

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val;
        this.validate();
    }

    @api
    get type() {
        return this._type;
    }
    set type(val) {
        this._type = val;
        this.validate();
    }

    @api validate() {
        if (!this._value) {
            this.message = "";
            return true;
        }

        const val = this._value.trim();

        switch (this._type) {

            /* -------------------------
               NUMBER TYPES
            --------------------------*/
            case "INTEGER":
            case "DOUBLE":
            case "CURRENCY":
                if (!/^-?\d+(\.\d+)?$/.test(val)) {
                    this.message = "Invalid number. Example: 123 or 45.67";
                    return false;
                }
                break;

            /* -------------------------
               EMAIL
            --------------------------*/
            case "EMAIL":
                if (!/^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/.test(val)) {
                    this.message = "Invalid email. Example: test@example.com";
                    return false;
                }
                break;

            /* -------------------------
               DATE (YYYY-MM-DD)
            --------------------------*/
            case "DATE":
            case "DATETIME":
                if (isNaN(Date.parse(val))) {
                    this.message = "Invalid date. Format: YYYY-MM-DD. Example: 2024-10-09";
                    return false;
                }
                break;

            /* -------------------------
               PHONE NUMBER (10 digits)
            --------------------------*/
            case "PHONE":
                if (!/^\d{10}$/.test(val)) {
                    this.message = "Invalid phone number. Must be 10 digits. Example: 9876543210";
                    return false;
                }
                break;

            /* -------------------------
               ACCOUNT ID (Salesforce)
               Allowed Length: 15 or 18
            --------------------------*/
            case "ID":
            case "SFID":
                if (!(val.length === 15 || val.length === 18)) {
                    this.message = "Invalid Salesforce Id. Must be 15 or 18 characters. Example: 001xx000003DG1t";
                    return false;
                }
                break;

            /* -------------------------
               DEFAULT OK
            --------------------------*/
            default:
                this.message = "";
                return true;
        }

        this.message = "";
        return true;
    }
}