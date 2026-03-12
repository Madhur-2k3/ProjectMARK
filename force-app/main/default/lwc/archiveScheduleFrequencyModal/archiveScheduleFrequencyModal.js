import { LightningElement, api } from 'lwc';

export default class ArchiveScheduleFrequencyModal extends LightningElement {

    @api selectedObject;
    @api selectedCriteria;
    @api scheduleName;
    @api selectedChildObjects;
    selectedFrequency;
    preferredTime = '02:00';
    selectedDayOfWeek = 'MON';

    frequencyOptions = [
        { label: 'Daily', value: 'DAILY' },
        { label: 'Weekly', value: 'WEEKLY' },
        { label: 'Monthly', value: 'MONTHLY' },
        { label: 'Yearly', value: 'YEARLY' }
    ];

    dayOfWeekOptions = [
        { label: 'Monday', value: 'MON' },
        { label: 'Tuesday', value: 'TUE' },
        { label: 'Wednesday', value: 'WED' },
        { label: 'Thursday', value: 'THU' },
        { label: 'Friday', value: 'FRI' },
        { label: 'Saturday', value: 'SAT' },
        { label: 'Sunday', value: 'SUN' }
    ];

    // ── Computed ──

    get isDisabled() {
        return !this.selectedFrequency;
    }

    get showDayOfWeek() {
        return this.selectedFrequency === 'WEEKLY';
    }

    get scheduleSummary() {
        const time = this.preferredTime || '02:00';
        const freq = this.selectedFrequency;

        if (freq === 'DAILY') {
            return `Runs every day at ${time}`;
        }
        if (freq === 'WEEKLY') {
            const dayLabel = this.dayOfWeekOptions.find(
                d => d.value === this.selectedDayOfWeek
            );
            const dayName = dayLabel ? dayLabel.label : this.selectedDayOfWeek;
            return `Runs every ${dayName} at ${time}`;
        }
        if (freq === 'MONTHLY') {
            return `Runs on the 1st of every month at ${time}`;
        }
        if (freq === 'YEARLY') {
            return `Runs on January 1st every year at ${time}`;
        }
        return '';
    }

    // ── Handlers ──

    handleFrequencyChange(event) {
        this.selectedFrequency = event.detail.value;
    }

    handleTimeChange(event) {
        this.preferredTime = event.detail.value;
    }

    handleDayOfWeekChange(event) {
        this.selectedDayOfWeek = event.detail.value;
    }

    handleNext() {
        this.dispatchEvent(
            new CustomEvent('schedulecomplete', {
                detail: {
                    frequency: this.selectedFrequency,
                    criteria: this.selectedCriteria,
                    object: this.selectedObject,
                    preferredTime: this.preferredTime,
                    dayOfWeek: this.selectedDayOfWeek,
                    scheduleName: this.scheduleName,
                    selectedChildObjects: this.selectedChildObjects
                }
            })
        );
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}