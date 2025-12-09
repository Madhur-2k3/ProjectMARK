import { LightningElement, api } from 'lwc';

export default class FieldValidator extends LightningElement {

    _value;
    _type;

    @api message = "";

    // ----- AUTO VALIDATE WHEN VALUE CHANGES -----
    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val;
        this.validate();       // ⭐ automatically validates on any value change
    }

    // ----- AUTO VALIDATE WHEN TYPE CHANGES -----
    @api
    get type() {
        return this._type;
    }
    set type(val) {
        this._type = val;
        this.validate();       // ⭐ allow re-validation if field type changes
    }

    // ----- VALIDATION LOGIC -----
    @api validate() {

        // empty allowed
        if (!this._value) {
            this.message = "";
            return true;
        }

        switch (this._type) {

            case "INTEGER":
            case "DOUBLE":
            case "CURRENCY":
                if (!/^-?\d+(\.\d+)?$/.test(this._value)) {
                    this.message = "Invalid number. Example: 123 or 45.67";
                    return false;
                }
                break;

            case "EMAIL":
                if (!/^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/.test(this._value)) {
                    this.message = "Invalid email. Example: test@example.com";
                    return false;
                }
                break;

            case "DATE":
            case "DATETIME":
                if (isNaN(Date.parse(this._value))) {
                    this.message = "Invalid date. Example: 2024-10-09";
                    return false;
                }
                break;

            default:
                this.message = "";
                return true;
        }

        // valid input
        this.message = "";
        return true;
    }
}