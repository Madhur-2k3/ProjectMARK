import { LightningElement, track, wire } from 'lwc';
import getDataArchive from '@salesforce/apex/DataArchiveObjectController.getArchivedObject';

export default class ParentComponent extends LightningElement {
    @track archiveRecords = [];       
    @track archiveColumns = [];      

    @wire(getDataArchive)
    wiredArchiveData({ error, data }) {
        if (data) {
            
            let processedRecords = JSON.parse(JSON.stringify(data.data));

            
            processedRecords.forEach(record => {
                record.nameUrl = '/' + record.Id;
            });

           
            let processedColumns = data.columns.map(columns => {
                if (columns.fieldName === 'Name') {
                    return {
                        label: columns.label,
                        fieldName: 'nameUrl',     
                        type: 'url',
                        typeAttributes: {
                            label: { fieldName: 'Name' }, 
                            target: '_blank'
                        }
                    };
                }
                return columns;
            });

            
            this.archiveRecords = processedRecords;
            this.archiveColumns = processedColumns;

        } else if (error) {
            console.error('Error fetching archived records:', error);
        }
    }
}