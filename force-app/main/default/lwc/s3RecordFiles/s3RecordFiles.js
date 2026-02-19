import { LightningElement, api, track } from 'lwc';
import listObjectsByPrefix from '@salesforce/apex/S3Controller.listObjectsByPrefix';
import getDataFromS3 from '@salesforce/apex/S3Controller.getDataFromS3';
import getDataFromS3AsBase64 from '@salesforce/apex/S3Controller.getDataFromS3AsBase64';

// File types that can be previewed in-browser
const IMAGE_EXTS = new Set(['png', 'jpg', 'jpeg', 'gif', 'svg', 'bmp', 'webp', 'ico']);
const PDF_EXTS = new Set(['pdf']);
const CSV_EXTS = new Set(['csv']);
const TEXT_EXTS = new Set(['txt', 'json', 'xml', 'html', 'css', 'js', 'log', 'md', 'yml', 'yaml']);
const VIDEO_EXTS = new Set(['mp4', 'webm', 'ogg']);
const AUDIO_EXTS = new Set(['mp3', 'wav', 'ogg', 'aac']);

const MIME_MAP = {
    'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'gif': 'image/gif', 'svg': 'image/svg+xml', 'bmp': 'image/bmp',
    'webp': 'image/webp', 'ico': 'image/x-icon',
    'pdf': 'application/pdf',
    'txt': 'text/plain', 'csv': 'text/csv', 'json': 'application/json',
    'xml': 'text/xml', 'html': 'text/html', 'css': 'text/css',
    'js': 'application/javascript', 'log': 'text/plain', 'md': 'text/plain',
    'yml': 'text/yaml', 'yaml': 'text/yaml',
    'mp4': 'video/mp4', 'webm': 'video/webm', 'ogg': 'video/ogg',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'aac': 'audio/aac'
};

export default class S3RecordFiles extends LightningElement {
    @api recordId;
    @track files = [];
    @track error;
    @track loading = false;
    @track showAll = false;

    // Preview state
    @track showPreview = false;
    @track previewLoading = false;
    @track previewError;
    @track previewFileName = '';
    @track previewDataUrl = '';
    @track previewTextContent = '';
    @track csvHeaders = [];
    @track csvRows = [];
    @track previewMimeType = '';
    _previewExt = '';
    _previewFullKey = '';

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

    // Preview type getters
    get isImagePreview() {
        return IMAGE_EXTS.has(this._previewExt) && !this.previewError;
    }

    get isPdfPreview() {
        return PDF_EXTS.has(this._previewExt) && !this.previewError;
    }

    get isCsvPreview() {
        return CSV_EXTS.has(this._previewExt) && !this.previewError;
    }

    get isTextPreview() {
        return TEXT_EXTS.has(this._previewExt) && !this.previewError;
    }

    get isVideoPreview() {
        return VIDEO_EXTS.has(this._previewExt) && !this.previewError;
    }

    get isAudioPreview() {
        return AUDIO_EXTS.has(this._previewExt) && !this.previewError;
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
                const fileName = fullKey.includes('/') ? fullKey.substring(fullKey.lastIndexOf('/') + 1) : fullKey;
                const ext = fileName.includes('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
                const sizeBytes = Number(item.Size) || 0;
                let sizeLabel;
                if (sizeBytes >= 1048576) {
                    sizeLabel = (sizeBytes / 1048576).toFixed(1) + ' MB';
                } else if (sizeBytes >= 1024) {
                    sizeLabel = (sizeBytes / 1024).toFixed(1) + ' KB';
                } else {
                    sizeLabel = sizeBytes + ' B';
                }
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
            'csv': 'doctype:csv', 'pdf': 'doctype:pdf',
            'xls': 'doctype:excel', 'xlsx': 'doctype:excel',
            'doc': 'doctype:word', 'docx': 'doctype:word',
            'ppt': 'doctype:ppt', 'pptx': 'doctype:ppt',
            'txt': 'doctype:txt', 'xml': 'doctype:xml',
            'json': 'doctype:txt', 'html': 'doctype:html',
            'zip': 'doctype:zip',
            'png': 'doctype:image', 'jpg': 'doctype:image',
            'jpeg': 'doctype:image', 'gif': 'doctype:image', 'svg': 'doctype:image',
            'mp4': 'doctype:video', 'mp3': 'doctype:audio'
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

    /**
     * Determines whether a file can be previewed in-browser.
     */
    _isPreviewable(ext) {
        return IMAGE_EXTS.has(ext) || PDF_EXTS.has(ext) || CSV_EXTS.has(ext)
            || TEXT_EXTS.has(ext) || VIDEO_EXTS.has(ext) || AUDIO_EXTS.has(ext);
    }

    /**
     * Click handler: preview if possible, otherwise download.
     */
    handleFileClick(event) {
        const fullKey = event.currentTarget.dataset.key;
        const fileName = event.currentTarget.dataset.filename;
        const ext = (event.currentTarget.dataset.ext || '').toLowerCase();

        if (!fullKey) return;

        if (this._isPreviewable(ext)) {
            this._openPreview(fullKey, fileName, ext);
        } else {
            this._downloadFile(fullKey, fileName);
        }
    }

    /**
     * Opens the preview modal and fetches file content.
     */
    async _openPreview(fullKey, fileName, ext) {
        this._previewFullKey = fullKey;
        this._previewExt = ext;
        this.previewFileName = fileName;
        this.previewDataUrl = '';
        this.previewTextContent = '';
        this.csvHeaders = [];
        this.csvRows = [];
        this.previewError = null;
        this.previewMimeType = MIME_MAP[ext] || 'application/octet-stream';
        this.showPreview = true;
        this.previewLoading = true;

        try {
            if (CSV_EXTS.has(ext)) {
                // CSV: parse into table data
                const content = await getDataFromS3({ fileName: fullKey });
                this._parseCsv(content);
            } else if (TEXT_EXTS.has(ext)) {
                // Text content can use the string-based method
                const content = await getDataFromS3({ fileName: fullKey });
                this.previewTextContent = content;
            } else {
                // Binary content needs base64
                const base64Content = await getDataFromS3AsBase64({ fileName: fullKey });
                this.previewDataUrl = `data:${this.previewMimeType};base64,${base64Content}`;
            }
        } catch (e) {
            this.previewError = e?.body?.message || e?.message || 'Failed to load preview';
            console.error('Preview error', e);
        } finally {
            this.previewLoading = false;
        }
    }

    handleClosePreview() {
        this.showPreview = false;
        this.previewDataUrl = '';
        this.previewTextContent = '';
        this.csvHeaders = [];
        this.csvRows = [];
        this._previewExt = '';
        this._previewFullKey = '';
        this.previewError = null;
    }

    /**
     * Parses CSV content into headers and rows for table display.
     * Handles quoted fields containing commas.
     */
    _parseCsv(content) {
        const lines = content.split(/\r?\n/).filter(line => line.trim() !== '');
        if (lines.length === 0) {
            this.csvHeaders = [];
            this.csvRows = [];
            return;
        }

        const parseLine = (line) => {
            const fields = [];
            let current = '';
            let inQuotes = false;
            for (let i = 0; i < line.length; i++) {
                const ch = line[i];
                if (inQuotes) {
                    if (ch === '"' && i + 1 < line.length && line[i + 1] === '"') {
                        current += '"';
                        i++;
                    } else if (ch === '"') {
                        inQuotes = false;
                    } else {
                        current += ch;
                    }
                } else {
                    if (ch === '"') {
                        inQuotes = true;
                    } else if (ch === ',') {
                        fields.push(current.trim());
                        current = '';
                    } else {
                        current += ch;
                    }
                }
            }
            fields.push(current.trim());
            return fields;
        };

        this.csvHeaders = parseLine(lines[0]);
        this.csvRows = lines.slice(1).map((line, idx) => {
            const cells = parseLine(line);
            return {
                id: 'row-' + idx,
                cells: cells.map((val, ci) => ({ id: 'cell-' + idx + '-' + ci, value: val }))
            };
        });
    }

    /**
     * Download from the preview modal.
     */
    async handleDownloadFromPreview() {
        await this._downloadFile(this._previewFullKey, this.previewFileName);
    }

    /**
     * Downloads a file from S3.
     */
    async _downloadFile(fullKey, fileName) {
        this.loading = true;
        this.error = null;
        try {
            const base64Content = await getDataFromS3AsBase64({ fileName: fullKey });
            const ext = (fileName || '').split('.').pop().toLowerCase();
            const mime = MIME_MAP[ext] || 'application/octet-stream';
            const dataUri = `data:${mime};base64,${base64Content}`;

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