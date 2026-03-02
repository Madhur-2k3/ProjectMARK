import { LightningElement, api, track } from 'lwc';
import listObjectsByPrefix from '@salesforce/apex/S3Controller.listObjectsByPrefix';
import getDataFromS3 from '@salesforce/apex/S3Controller.getDataFromS3';
import getFilteredCsvFromS3 from '@salesforce/apex/S3Controller.getFilteredCsvFromS3';
import getDataFromS3AsBase64 from '@salesforce/apex/S3Controller.getDataFromS3AsBase64';
import getCsvFieldMetadata from '@salesforce/apex/S3Controller.getCsvFieldMetadata';
import hasDownloadPermission from '@salesforce/customPermission/Can_Download_Archive_Files';

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

    // CSV filter state (filterBuilder integration)
    @track csvFieldMeta = [];    // [{apiName, label, type}] for filterBuilder
    @track csvObjectName = '';   // SObject name for filterBuilder
    @track csvFilterMode = 'all'; // 'all' or 'filter'
    _allCsvRows = [];            // unfiltered backup
    _csvWhereClause = '';        // current WHERE clause from filterBuilder

    get canDownload() {
        return hasDownloadPermission;
    }

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

    get hasFilterFields() {
        return this.csvFieldMeta && this.csvFieldMeta.length > 0;
    }

    get isAllRecordsMode() {
        return this.csvFilterMode === 'all';
    }

    get isFilterRecordsMode() {
        return this.csvFilterMode === 'filter';
    }

    get allRecordsVariant() {
        return this.csvFilterMode === 'all' ? 'brand' : 'neutral';
    }

    get filterRecordsVariant() {
        return this.csvFilterMode === 'filter' ? 'brand' : 'neutral';
    }

    // Filtered CSV rows based on filterBuilder WHERE clause
    get filteredCsvRows() {
        if (this.csvFilterMode === 'all' || !this._csvWhereClause) {
            return this._allCsvRows;
        }
        return this._allCsvRows.filter(row => this._evaluateWhereClause(row));
    }

    // Row count label
    get csvRowCountLabel() {
        const filtered = this.filteredCsvRows.length;
        const total = this._allCsvRows.length;
        if (filtered === total) {
            return `${total} row${total !== 1 ? 's' : ''}`;
        }
        return `${filtered} of ${total} rows`;
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
                // CSV: fetch with FLS filtering, then parse into table data
                const content = await getFilteredCsvFromS3({ fileName: fullKey });
                this._parseCsv(content);

                // Fetch field metadata for filterBuilder
                try {
                    const objName = this._extractObjectNameFromKey(fullKey);
                    if (objName && this.csvHeaders.length > 0) {
                        this.csvObjectName = objName;
                        const meta = await getCsvFieldMetadata({
                            objectName: objName,
                            fieldNames: this.csvHeaders
                        });
                        this.csvFieldMeta = meta || [];
                    }
                } catch (metaErr) {
                    console.warn('Could not load field metadata for filters:', metaErr);
                    // Non-fatal: filters just won't appear
                }
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
        this._allCsvRows = [];
        this._previewExt = '';
        this._previewFullKey = '';
        this.previewError = null;
        this.csvFieldMeta = [];
        this.csvObjectName = '';
        this._csvWhereClause = '';
        this.csvFilterMode = 'all';
    }

    // ─── CSV Toggle Handlers ─────────────────────────────────────

    handleShowAllRecords() {
        this.csvFilterMode = 'all';
        this._csvWhereClause = '';
    }

    handleShowFilterRecords() {
        this.csvFilterMode = 'filter';
    }

    // ─── FilterBuilder Integration ───────────────────────────────

    /**
     * Handler for filterBuilder's wherechange event.
     * Receives a SOQL-style WHERE clause string and triggers re-filtering.
     */
    handleWhereChange(event) {
        this._csvWhereClause = event.detail || '';
    }

    /**
     * Extracts object name from S3 key (client-side version).
     * Pattern: recordId/ObjectName_ObjectName_-_DA-XXXX.csv
     */
    _extractObjectNameFromKey(key) {
        if (!key) return null;
        let fName = key.includes('/') ? key.substring(key.lastIndexOf('/') + 1) : key;
        const dotIdx = fName.lastIndexOf('.');
        if (dotIdx > 0) fName = fName.substring(0, dotIdx);

        // Look for "_-_DA-" delimiter
        const daIdx = fName.indexOf('_-_DA-');
        if (daIdx > 0) {
            const beforeDA = fName.substring(0, daIdx);
            // Pattern: ObjectName_ObjectName → first part is the object
            // For custom objects like Booking__c_Booking__c, find __c suffix
            for (const suffix of ['__c', '__mdt', '__e', '__b', '__x']) {
                const sIdx = beforeDA.indexOf(suffix);
                if (sIdx > 0) {
                    return beforeDA.substring(0, sIdx + suffix.length);
                }
            }
            // Standard object: first segment before _
            const usIdx = beforeDA.indexOf('_');
            return usIdx > 0 ? beforeDA.substring(0, usIdx) : beforeDA;
        }
        return null;
    }

    /**
     * Evaluates the WHERE clause from filterBuilder against a single CSV row.
     * Supports: =, !=, >, >=, <, <=, LIKE
     * Supports: AND, OR, parenthesized custom logic
     */
    _evaluateWhereClause(row) {
        const clause = this._csvWhereClause;
        if (!clause) return true;

        try {
            // Tokenize the clause into conditions and logical operators
            const tokens = this._tokenizeWhereClause(clause);
            return this._evalTokens(tokens, row);
        } catch (e) {
            console.warn('WHERE clause evaluation error:', e);
            return true; // Show row if evaluation fails
        }
    }

    /**
     * Tokenizes a WHERE clause into an array of tokens:
     * conditions become {type:'cond', field, op, value},
     * AND/OR become {type:'logic', value:'AND'|'OR'},
     * parentheses become {type:'paren', value:'('|')'}
     */
    _tokenizeWhereClause(clause) {
        const tokens = [];
        let remaining = clause.trim();

        while (remaining.length > 0) {
            remaining = remaining.trimStart();
            if (!remaining) break;

            // Parentheses
            if (remaining[0] === '(') {
                tokens.push({ type: 'paren', value: '(' });
                remaining = remaining.substring(1);
                continue;
            }
            if (remaining[0] === ')') {
                tokens.push({ type: 'paren', value: ')' });
                remaining = remaining.substring(1);
                continue;
            }

            // AND / OR
            const logicMatch = remaining.match(/^(AND|OR)\b/i);
            if (logicMatch) {
                tokens.push({ type: 'logic', value: logicMatch[1].toUpperCase() });
                remaining = remaining.substring(logicMatch[0].length);
                continue;
            }

            // Condition: field operator value
            const condMatch = remaining.match(
                /^(\S+?)\s+(=|!=|>=|<=|>|<|LIKE)\s+(.+?)(?=\s+AND\b|\s+OR\b|\)|$)/i
            );
            if (condMatch) {
                let val = condMatch[3].trim();
                // Remove quotes
                if ((val.startsWith("'") && val.endsWith("'")) ||
                    (val.startsWith('"') && val.endsWith('"'))) {
                    val = val.substring(1, val.length - 1);
                }
                // Remove LIKE wildcards for contains matching
                if (condMatch[2].toUpperCase() === 'LIKE') {
                    val = val.replace(/%/g, '');
                }
                tokens.push({
                    type: 'cond',
                    field: condMatch[1],
                    op: condMatch[2].toUpperCase(),
                    value: val
                });
                remaining = remaining.substring(condMatch[0].length);
                continue;
            }

            // Skip unrecognized character
            remaining = remaining.substring(1);
        }

        return tokens;
    }

    /**
     * Recursively evaluates tokenized WHERE clause with support for
     * AND, OR, and parenthesized groups.
     */
    _evalTokens(tokens, row) {
        const { result } = this._evalExpr(tokens, 0, row);
        return result;
    }

    _evalExpr(tokens, pos, row) {
        let left, idx = pos;

        // Get first operand
        if (idx < tokens.length && tokens[idx].type === 'paren' && tokens[idx].value === '(') {
            const inner = this._evalExpr(tokens, idx + 1, row);
            left = inner.result;
            idx = inner.nextPos;
            // Skip closing paren
            if (idx < tokens.length && tokens[idx].type === 'paren' && tokens[idx].value === ')') {
                idx++;
            }
        } else if (idx < tokens.length && tokens[idx].type === 'cond') {
            left = this._evalCondition(tokens[idx], row);
            idx++;
        } else {
            return { result: true, nextPos: idx + 1 };
        }

        // Chain with AND/OR
        while (idx < tokens.length && tokens[idx].type === 'logic') {
            const logic = tokens[idx].value;
            idx++;

            let right;
            if (idx < tokens.length && tokens[idx].type === 'paren' && tokens[idx].value === '(') {
                const inner = this._evalExpr(tokens, idx + 1, row);
                right = inner.result;
                idx = inner.nextPos;
                if (idx < tokens.length && tokens[idx].type === 'paren' && tokens[idx].value === ')') {
                    idx++;
                }
            } else if (idx < tokens.length && tokens[idx].type === 'cond') {
                right = this._evalCondition(tokens[idx], row);
                idx++;
            } else {
                break;
            }

            left = logic === 'AND' ? (left && right) : (left || right);
        }

        return { result: left, nextPos: idx };
    }

    /**
     * Evaluates a single condition against a CSV row.
     */
    _evalCondition(cond, row) {
        const colIdx = this.csvHeaders.indexOf(cond.field);
        if (colIdx < 0 || colIdx >= row.cells.length) return true;

        const cellVal = (row.cells[colIdx].value || '').trim();
        const filterVal = (cond.value || '').trim();

        // Get field type from metadata
        const fieldMeta = this.csvFieldMeta.find(f => f.apiName === cond.field);
        const fieldType = fieldMeta ? fieldMeta.type : 'STRING';

        // Compare as numbers for numeric types
        const numericTypes = new Set(['INTEGER', 'DOUBLE', 'CURRENCY']);
        if (numericTypes.has(fieldType)) {
            const cellNum = parseFloat(cellVal);
            const filterNum = parseFloat(filterVal);
            if (!isNaN(cellNum) && !isNaN(filterNum)) {
                return this._compareValues(cellNum, cond.op, filterNum);
            }
        }

        // Date/DateTime comparison
        if (fieldType === 'DATE' || fieldType === 'DATETIME') {
            const cellDate = new Date(cellVal);
            const filterDate = new Date(filterVal);
            if (!isNaN(cellDate.getTime()) && !isNaN(filterDate.getTime())) {
                return this._compareValues(cellDate.getTime(), cond.op, filterDate.getTime());
            }
        }

        // String comparison (case-insensitive)
        const cellLower = cellVal.toLowerCase();
        const filterLower = filterVal.toLowerCase();

        switch (cond.op) {
            case '=':
                return cellLower === filterLower;
            case '!=':
                return cellLower !== filterLower;
            case 'LIKE':
                return cellLower.includes(filterLower);
            default:
                return this._compareValues(cellLower, cond.op, filterLower);
        }
    }

    _compareValues(a, op, b) {
        switch (op) {
            case '=':  return a === b;
            case '!=': return a !== b;
            case '>':  return a > b;
            case '>=': return a >= b;
            case '<':  return a < b;
            case '<=': return a <= b;
            case 'LIKE': return String(a).toLowerCase().includes(String(b).toLowerCase());
            default:   return true;
        }
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
        this._allCsvRows = lines.slice(1).map((line, idx) => {
            const cells = parseLine(line);
            return {
                id: 'row-' + idx,
                cells: cells.map((val, ci) => ({ id: 'cell-' + idx + '-' + ci, value: val }))
            };
        });
        this.csvRows = this._allCsvRows;
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