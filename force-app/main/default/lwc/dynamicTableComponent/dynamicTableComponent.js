import { LightningElement, track, wire } from 'lwc';
import getDataArchive from '@salesforce/apex/DataArchiveObjectController.getArchivedObjectPaginated';

export default class DynamicTableComponent extends LightningElement {
    @track tableData = [];
    @track columns = [];

    pageNumberInt = 1;
    pageSizeInt = 100;

    @wire(getDataArchive, { pageNumberInt: '$pageNumberInt', pageSizeInt: '$pageSizeInt' })
    wiredDataArchive({ error, data }) {
        if (data) {
            
            let tableData = JSON.parse(JSON.stringify(data.data));

            
            tableData.forEach(row => {
                row.NameLink = '/' + row.Id; 
            });

            
            let cols = data.columns.map(col => {
                if (col.fieldName === 'Name') {
                    return {
                        label: col.label,
                        fieldName: 'NameLink', 
                        type: 'url',
                        typeAttributes: {
                            label: { fieldName: 'Name' }, 
                            target: '_blank'              
                        }
                    };
                }
                return col;
            });

            this.tableData = tableData;
            this.columns = cols;
        } else if (error) {
            console.error('Error fetching data archive:', error);
        }
    }
}