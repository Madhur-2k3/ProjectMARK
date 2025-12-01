import { LightningElement, api, track, wire } from 'lwc';
import getFieldsBySObject from '@salesforce/apex/sObjectsController.getFieldsBySObject';
import getObjData from '@salesforce/apex/objectDataHandler.getObjData';
import getFilteredAccounts from '@salesforce/apex/objectDataHandler.getFilteredAccounts';
import updateRecords from '@salesforce/apex/objectDataHandler.updateRecords';
import deleteRecords from '@salesforce/apex/objectDataHandler.deleteRecords';

export default class FieldSelector extends LightningElement {


    @track fieldOptions = [];
    @track selectedFieldOptions = [];
    leftSelected = [];
    rightSelected = [];
    @track masterFieldOptions = [];
    //from madhur
    @api selectedObject;
    @api selectedOption;
    @api selectedField;
    @api selectedOperator;
    @api value;
    @track objects;
    @track records;
    @track filteredAccounts;
    @track draftValues = [];
    @track selectedRows = [];
    @track isPreviousDisabled = true;
    @track isNextDisabled = false;
    @track currentPage = 1;
    @track totalPages = 0;
    @track totalRecords = 0;
    @track pageSize = 5;
    @track paginatedData = [];
    @track conditions = '';
    @track showDatatable = false;

    disabled=true
    booleanFlag = false;

    dumArray=[
        {id:1,field:"",operator:"",value:"",logicOperator:"" },
    
    ]
    //end madhur

    

    // Wire with dynamic parameter
    @wire(getFieldsBySObject, { sObjectApiName: '$selectedObject' })
    wiredFields({ data, error }) {
    if (data) {

        // Store all fields permanently
        this.masterFieldOptions = data.map(f => ({
            label: f.label,
            value: f.apiName,
            type: f.fieldType
        }));
        // Reset the dual list left side with fresh copy
        this.fieldOptions = [...this.masterFieldOptions];
        // Reset the selected list
        this.selectedFieldOptions = [];
    } 
}

    

    handleLeftSelection(event) {
        this.leftSelected = event.target.value;
    }

    handleRightSelection(event) {
        this.rightSelected = event.target.value;
    }

    moveRight() {
        if (!this.leftSelected.length) return;

        let moved = this.fieldOptions.filter(f => this.leftSelected.includes(f.value));
        this.selectedFieldOptions = [...this.selectedFieldOptions, ...moved];
        console.log(JSON.stringify(this.selectedFieldOptions));
        this.fieldOptions = this.fieldOptions.filter(
            f => !this.leftSelected.includes(f.value)
        );

        this.leftSelected = [];
    }

    moveLeft() {
        if (!this.rightSelected.length) return;

        let moved = this.selectedFieldOptions.filter(f => this.rightSelected.includes(f.value));
        this.fieldOptions = [...this.fieldOptions, ...moved];

        this.selectedFieldOptions = this.selectedFieldOptions.filter(
            f => !this.rightSelected.includes(f.value)
        );

        this.rightSelected = [];
    }

    //from madhur

    get selectOptions(){
        return [
            {label:'All',value:'All'},
            {label:'Query',value:'Query'},
        ]
    }

    handleSecond(event){
        this.selectedOption = event.detail.value;
        if(this.selectedOption){
            this.booleanFlag = true;
        }else{
            this.booleanFlag = false;
        }
         
    }

    rebuildConditions() {
    const rows = this.dumArray.filter(
        row => row.field && row.operator && row.value
    );

    if (rows.length === 0) {
        this.conditions = "";
        return;
    }

    // Build raw segments with their logic operators
    const segments = rows.map((row, index) => {
        let condition = `${row.field} ${row.operator} ${row.field === 'name' ? `'${row.value}'` : row.value}`;
        return {
            condition,
            logic: index === 0 ? "" : rows[index - 1].logicOperator
        };
    });

    // Check if both AND & OR are used
    const hasAND = segments.some(s => s.logic === "AND");
    const hasOR  = segments.some(s => s.logic === "OR");

    // If only one type, simple join
    if (!(hasAND && hasOR)) {
        this.conditions = segments
            .map((s, i) => i === 0 ? s.condition : ` ${s.logic} ${s.condition}`)
            .join("");
        return;
    }

    // If mixing AND + OR → apply parentheses
    let grouped = "";
    let currentGroup = segments[0].condition;

    for (let i = 1; i < segments.length; i++) {
        const seg = segments[i];

        if (seg.logic === "AND") {
            currentGroup += ` AND ${seg.condition}`;
        } else {
            // close previous AND group
            grouped += `(${currentGroup}) OR `;
            currentGroup = seg.condition;
        }
    }

    // Add the last group
    grouped += `(${currentGroup})`;

    this.conditions = grouped;
}

    handleAddCondition(){
        this.rebuildConditions();

        //add a empty condition row
        this.dumArray=[...this.dumArray,{
            id:this.dumArray.length+1,
            field:"",
            operator:"",
            value:""
        }];
        console.log("dum Array: ",JSON.stringify(this.dumArray));
        console.log("Conditions: ",this.conditions);

    }
    

    get options(){
        return [
            {label:'Account',value:'Account'},
            {label:'Contact',value:'Contact'},
            {label:'Lead',value:'Lead'},
            {label:'Opportunity',value:'Opportunity'}
        ]
    }
    get selectOptions(){
        return [
            {label:'All',value:'All'},
            {label:'Query',value:'Query'},
        ]
    }
    // get fieldOptions(){
    //     return this.masterFieldOptions;
    // }
    get allFieldsForQuery() {
    return this.masterFieldOptions;
}
    get operatorOptions(){
        return[
            {label:"Greater Than",value:">"},
            {label:"Less Than",value:"<"},
            {label:"Equal To",value:"="}
        ]
    }
    get logicOperatorOptions(){
        return[
            {label:"AND",value:"AND"},
            {label:"OR",value:"OR"}
        ]
    }
    get pageSizeOptions(){
        return[
            {label:"5",value:5},
            {label:"10",value:10},
            {label:"15",value:15},
            {label:"20",value:20}
        ]
    }

    handlePageSizeChange(event){
        this.pageSize = parseInt(event.detail.value);
        this.totalPages = Math.ceil(this.totalRecords / this.pageSize);
        this.currentPage = 1;
        this.updatePaginatedData();
    }
    columns = [
        
        {label:'Record',fieldName:'recordLink',type:'url',typeAttributes:{label:{fieldName:'Name'},target:'_blank'}},
        {label:'Name',fieldName:'Name',editable:true},
        {label:'Id',fieldName:'Id'},
    ];
    filteredAccountColumns=[
        
        {label:'Name',fieldName:'Name'},
        {label:'Annual Revenue',fieldName:'AnnualRevenue'},
    ];
    handleChange(event){
        this.selectedObject = event.detail.value;
        if(this.selectedObject){
            this.booleanFlag = true;
        }else{
            this.booleanFlag = false;
        }
    }
    handleSecond(event){
        this.selectedOption = event.detail.value;
        if(this.selectedOption==='Query'){
            this.booleanFlag = true;
        }else{
            this.booleanFlag = false;
        }
        
    }

    handleFieldChange(event){
        const index = event.target.dataset.index;
        this.dumArray[index].field = event.detail.value;
        this.dumArray = [...this.dumArray];
        this.rebuildConditions();

    }
    handleOptionChange(event){
        const index = event.target.dataset.index;
        this.dumArray[index].operator = event.detail.value;
        this.dumArray = [...this.dumArray];
        this.rebuildConditions();

    }
    handleInput(event){
        const index = event.target.dataset.index;
        this.dumArray[index].value = event.target.value;
        this.dumArray = [...this.dumArray];
        this.rebuildConditions();
    }
    handleLogicOperatorChange(event){
        const index = event.target.dataset.index;
        this.dumArray[index].logicOperator = event.detail.value;
        this.dumArray = [...this.dumArray];
        this.rebuildConditions();
    }

    //convert fields to set
    get selectedFields(){
        
        const fieldSet = new Set(
            this.dumArray
                .filter(row=>row.field)
                .map(row=>row.field)
        );
        return Array.from(fieldSet).join(',');
                

    }

    async handleFilterAccounts(){

        try {
            this.filteredAccounts = await getFilteredAccounts({objectName:this.selectedObject,fields:this.selectedFields,conditions:this.conditions});
            console.log("Filtered Accounts:",JSON.stringify(this.filteredAccounts));
            this.totalRecords = this.filteredAccounts.length;
            this.totalPages = Math.ceil(this.totalRecords / this.pageSize);
            this.currentPage = 1;
            this.updatePaginatedData();
            this.showDatatable = true;
        } catch (error) {
            console.error('Error fetching filtered accounts:', error);
        }
    }
    updatePaginatedData(){
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = startIndex + this.pageSize;
        this.paginatedData = this.filteredAccounts.slice(startIndex, endIndex);
        this.isPreviousDisabled = this.currentPage === 1;
        this.isNextDisabled = this.currentPage === this.totalPages;
    }
    
    handlePrevious(){
        if(this.currentPage > 1){
            this.currentPage--;
            this.updatePaginatedData();
        }
    }

    handleNext(){
        if(this.currentPage < this.totalPages){
            this.currentPage++;
            this.updatePaginatedData();
        }
    }

    handleDelete(event){
        const index=event.target.dataset.index;
        this.dumArray.splice(index,1);
        this.dumArray=[...this.dumArray];
        this.rebuildConditions();
        console.log("dum Array after delete: ",JSON.stringify(this.dumArray));
        console.log("Conditions after delete: ",this.conditions);
    }

    async handleSave(event) {
        const updatedFields = event.detail.draftValues;
        try {
            await updateRecords({ recordsToUpdate: updatedFields });
            this.showToast('Success', 'Records updated successfully', 'success');
            this.draftValues = [];
            // await this.handleClick();
            refreshApex(this.objects);
        } catch (error) {
            this.showToast('Error', 'Error updating records', 'error');
            
        }
    }

    handleRowSelection(event){
        this.selectedRows = event.detail.selectedRows;
        console.log("Selected Rows:",JSON.stringify(this.selectedRows));
    }

    async handleDeleteRecords(){
        console.log("Inside handle del")
        const recordIds = this.selectedRows.map(row => row.Id);
        console.log("Record Ids:", recordIds);
        if(recordIds.length === 0){
            this.showToast('Error', 'No records selected for deletion', 'error');
            return;
        }
        try{
            await deleteRecords({ recordIds: recordIds });
            this.showToast('Success', 'Records deleted successfully', 'success');
            this.selectedRows = [];
            await this.handleClick();
        }
        catch(error){
            this.showToast('Error', 'Error deleting records', 'error');
        }

    }

    async handleClick(){
      const records = await getObjData({searchKey:this.selectedObject})

      this.objects = records.map(obj=>({
        ...obj,
        recordLink:'/'+obj.Id
      }));
        // this.objects = records;
      console.log("Line 49",JSON.stringify(this.objects));
    }

    //end madhur

}