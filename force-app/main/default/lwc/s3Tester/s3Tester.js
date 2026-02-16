import { LightningElement, track } from 'lwc';
import getDataFromS3 from '@salesforce/apex/S3Controller.getDataFromS3';
import listObjectsFromS3 from '@salesforce/apex/S3Controller.listObjectsFromS3';
import putObjectToS3 from '@salesforce/apex/S3Controller.putObjectToS3';
// import getPresignedUrl from '@salesforce/apex/s3Presigner.getPresignedUrl';

export default class S3Tester extends LightningElement {
    @track fileName = 'test.txt';
    @track result;
    @track error;
    @track loading = false;
    @track selectedFileName;
    @track fileBase64;
    @track fileMimeType;
    @track items = [];
    @track columns = [
        { label: 'Name', fieldName: 'Key', type: 'text', wrapText: true },
        { label: 'Size (KB)', fieldName: 'SizeKB', type: 'number', typeAttributes: { maximumFractionDigits: 2 } },
        { label: 'Last Modified', fieldName: 'LastModified', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
        { type: 'button', typeAttributes: { label: 'Preview / Download', name: 'download', variant: 'brand' } }
    ];

    handleFileNameChange(event) {
        this.fileName = event.target.value;
    }

    async handleFetch() {
        this.result = null;
        this.error = null;
        this.loading = true;
        try {
            const res = await getDataFromS3({ fileName: this.fileName });
            this.result = res;
        } catch (e) {
            this.error = e?.body?.message || e?.message || JSON.stringify(e);
        } finally {
            this.loading = false;
        }
    }

    async handleList() {
        this.result = null;
        this.error = null;
        this.loading = true;
        try {
            const res = await listObjectsFromS3();
            // Pretty-print JSON
            try {
                const parsed = JSON.parse(res);
                // Map and format items for datatable
                this.items = parsed.map(item => ({
                    ...item,
                    SizeKB: item.Size ? (Number(item.Size) / 1024).toFixed(2) : 0,
                    LastModified: item.LastModified ? new Date(item.LastModified).toISOString() : null
                }));
                this.result = null;
                console.log("Response from s3 list", JSON.stringify(this.items, null, 2));
            } catch (err) {
                // If Apex returned non-JSON, show raw
                this.items = [];
                this.result = res;

            }
        } catch (e) {
            this.error = e?.body?.message || e?.message || JSON.stringify(e);
            console.error('listObjectsFromS3 error', e);
        } finally {
            this.loading = false;
        }
    }

    handleFileSelected(event) {
        this.result = null;
        this.error = null;
        const file = (event.target && event.target.files && event.target.files[0]) || (event.detail && event.detail.files && event.detail.files[0]);
        if (!file) return;
        this.selectedFileName = file.name;
        this.fileMimeType = file.type || 'application/octet-stream';
        const reader = new FileReader();
        reader.onload = () => {
            const dataUrl = reader.result;
            // data:[<mediatype>][;base64],<data>
            const base64 = dataUrl.split(',')[1];
            this.fileBase64 = base64;
        };
        reader.onerror = () => {
            this.error = 'Error reading file';
        };
        reader.readAsDataURL(file);
    }

    async handleUpload() {
        this.result = null;
        this.error = null;
        if (!this.fileBase64) {
            this.error = 'No file selected or file not loaded yet.';
            return;
        }
        this.loading = true;
        const fileNameToUse = this.selectedFileName || this.fileName || 'upload.bin';
        try {
            // Upload via Apex PUT (no presigned URL)
            const res = await putObjectToS3({ fileName: fileNameToUse, base64Body: this.fileBase64, contentType: this.fileMimeType });
            this.result = 'Upload via Apex: ' + res;
        } catch (e) {
            this.error = e?.body?.message || e?.message || JSON.stringify(e);
        } finally {
            this.loading = false;
        }
    }

    async handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'download') {
            this.result = null;
            this.error = null;
            this.loading = true;
            try {
                console.log('Fetching file via Apex GET:', row.Key);
                // Request content from Apex GET (no presigned URL)
                const content = await getDataFromS3({ fileName: row.Key });
                // Show preview modal / result block
                this.result = content;
                // Attempt to trigger download for text content
                try {
                    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
                    const url = URL.createObjectURL(blob);
                    const a = document.createElement('a');
                    a.href = url;
                    a.download = row.Key.replace(/\//g, '_');
                    document.body.appendChild(a);
                    a.click();
                    a.remove();
                    URL.revokeObjectURL(url);
                } catch (dErr) {
                    console.error('download attempt failed', dErr);
                    // ignore download errors; preview still available
                }
            } catch (e) {
                this.error = e?.body?.message || e?.message || JSON.stringify(e);
                console.error('getDataFromS3 error', e);
            } finally {
                this.loading = false;
            }
        }
    }
}