import { LightningElement, api, track } from 'lwc';
import listObjectsByPrefix from '@salesforce/apex/S3Controller.listObjectsByPrefix';
import getDataFromS3 from '@salesforce/apex/S3Controller.getDataFromS3';

export default class S3RecordFiles extends LightningElement {
    @api recordId;
    @track files = [];
    @track error;
    @track loading = false;
    @track showAll = false;

    get fileCount() {
        return this.files.length;
    }

    get title() {
        return `Notes & Attachments (${this.fileCount})`;
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get displayedFiles() {
        if (this.showAll) {
            return this.files;
        }
        return this.files.slice(0, 4);
    }

    get hasMoreFiles() {
        return this.files.length > 4 && !this.showAll;
    }

    connectedCallback() {
        this.loadFiles();
    }

    async loadFiles() {
        this.loading = true;
        this.error = null;
        try {
            const result = await listObjectsByPrefix({ prefix: this.recordId });
            const parsed = JSON.parse(result);
            this.files = parsed.map(item => {
                const fullKey = item.Key || '';
                // Strip prefix folder to get just filename
                const fileName = fullKey.includes('/') ? fullKey.substring(fullKey.lastIndexOf('/') + 1) : fullKey;
                // Derive extension
                const ext = fileName.includes('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
                // Format size
                const sizeBytes = Number(item.Size) || 0;
                let sizeLabel;
                if (sizeBytes >= 1048576) {
                    sizeLabel = (sizeBytes / 1048576).toFixed(1) + ' MB';
                } else if (sizeBytes >= 1024) {
                    sizeLabel = (sizeBytes / 1024).toFixed(1) + ' KB';
                } else {
                    sizeLabel = sizeBytes + ' B';
                }
                // Format date
                let dateLabel = '';
                if (item.LastModified) {
                    const d = new Date(item.LastModified);
                    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                    dateLabel = `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
                }
                return {
                    id: fullKey,
                    fullKey,
                    fileName,
                    ext,
                    sizeLabel,
                    dateLabel,
                    iconName: this.getIconName(ext)
                };
            });
        } catch (e) {
            this.error = e?.body?.message || e?.message || JSON.stringify(e);
            console.error('loadFiles error', e);
        } finally {
            this.loading = false;
        }
    }

    getIconName(ext) {
        const iconMap = {
            'csv': 'doctype:csv',
            'pdf': 'doctype:pdf',
            'xls': 'doctype:excel',
            'xlsx': 'doctype:excel',
            'doc': 'doctype:word',
            'docx': 'doctype:word',
            'ppt': 'doctype:ppt',
            'pptx': 'doctype:ppt',
            'txt': 'doctype:txt',
            'xml': 'doctype:xml',
            'json': 'doctype:txt',
            'html': 'doctype:html',
            'zip': 'doctype:zip',
            'png': 'doctype:image',
            'jpg': 'doctype:image',
            'jpeg': 'doctype:image',
            'gif': 'doctype:image',
            'svg': 'doctype:image',
            'mp4': 'doctype:video',
            'mp3': 'doctype:audio'
        };
        return iconMap[ext] || 'doctype:attachment';
    }

    handleRefresh() {
        this.showAll = false;
        this.loadFiles();
    }

    handleViewAll() {
        this.showAll = true;
    }

    async handleDownload(event) {
        const fullKey = event.currentTarget.dataset.key;
        const fileName = event.currentTarget.dataset.filename;
        if (!fullKey) return;

        this.loading = true;
        this.error = null;
        try {
            const content = await getDataFromS3({ fileName: fullKey });

            // Download using data URI (LWS-compatible)
            const base64 = btoa(unescape(encodeURIComponent(content)));
            const dataUri = 'data:application/octet-stream;base64,' + base64;

            const container = this.template.querySelector('.slds-card__body');
            const a = document.createElement('a');
            a.href = dataUri;
            a.download = fileName || fullKey.replace(/\//g, '_');
            a.style.display = 'none';
            container.appendChild(a);
            a.click();
            container.removeChild(a);
        } catch (e) {
            this.error = e?.body?.message || e?.message || JSON.stringify(e);
            console.error('Download error', e);
        } finally {
            this.loading = false;
        }
    }
}
