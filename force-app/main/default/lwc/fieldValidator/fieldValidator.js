import { LightningElement, api } from 'lwc';

export default class FieldValidator extends LightningElement {
    _value;
    _type;
    @api message = "";

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

            /* --------------------------------------
               NUMBER TYPES
            --------------------------------------- */
            case "INTEGER":
            case "DOUBLE":
            case "CURRENCY":
                if(this.val==null){
                    console.log("inside null")
                    return true;
                }
                if (!/^-?\d+(\.\d+)?$/.test(val)) {
                    console.log("inside invalid")
                    this.message =
                        `Invalid input: "${val}". You have to give input like: 123 or 45.67`;
                    return false;
                }
                break;

            /* --------------------------------------
               EMAIL
            --------------------------------------- */
            case "EMAIL":
                if (!/^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/.test(val)) {
                    this.message =
                        `Invalid input: "${val}". You have to give input like: test@example.com`;
                    return false;
                }
                break;

            /* --------------------------------------
               DATE (strict YYYY-MM-DD)
            --------------------------------------- */
            case "DATE":
            case "DATETIME":
                if (!/^\d{4}-\d{2}-\d{2}$/.test(val)) {
                    this.message =
                        `Invalid input: "${val}". You have to give input like: 2024-10-09 (Format: YYYY-MM-DD)`;
                    return false;
                }
                break;

            /* --------------------------------------
               INTERNATIONAL PHONE NUMBER
            --------------------------------------- */
            case "PHONE":
                if (!/^\+?[0-9\s\-()]{8,}$/.test(val)) {
                    this.message =
                        `Invalid input: "${val}". You have to give input like: +1 234 567 8901`;
                    return false;
                }
                break;

            /* --------------------------------------
               SALESFORCE ID (15 or 18 length)
            --------------------------------------- */
            case "ID":
            case "SFID":
                if (!(val.length === 16 || val.length === 18)) {
                    this.message =
                        `Invalid input: "${val}". You have to give input like: 001xx000003DG1t`;
                    return false;
                }
                break;

            /* --------------------------------------
               DEFAULT (anything else)
            --------------------------------------- */
            default:
                this.message = "";
                return true;
        }

        this.message = "";
        return true;
    }
}