import QtQuick

Item {
    id:root
    required property var document
    property var recipients:[]
    property var fields:[]
    property var audit:[]
    property string mode:""
    property string placingType:"signature"
    property string activeRecipient:""
    property string selectedId:""
    readonly property var selected:fields.find(function(f){return f.id===selectedId;}) || null
    readonly property bool complete:fields.every(function(f){return !f.required || !!f.value;})
    signal fillRequested(var field)
    function uid(){return Date.now().toString(36)+Math.random().toString(36).slice(2);}
    function manifest(){return {version:1,recipients:recipients,fields:fields,audit:audit,docHashSha256:""};}
    function hydrate(m,resume){recipients=m ? m.recipients : [];fields=m ? m.fields : [];audit=m ? m.audit : [];selectedId="";activeRecipient=nextRecipient();mode=resume && recipients.length ? "sign" : "";}
    function nextRecipient(){var ordered=recipients.slice().sort(function(a,b){return a.order-b.order;});var next=ordered.find(function(r){return pending(r.id).length>0;});return next ? next.id : ordered.length ? ordered[0].id : "";}
    function pending(id){return fields.filter(function(f){return f.recipientId===id && f.required && !f.value;});}
    function canSign(id){var r=recipients.find(function(r){return r.id===id;});return r && !recipients.some(function(other){return other.order<r.order && pending(other.id).length>0;});}
    function addRecipient(name){if(document.busy || recipients.length>=100)return;document.remember();var colors=["#2f5e8c","#cc3b25","#4f6b43","#8d5fb0","#b7892f"];var r={id:uid(),name:name.trim() || "Recipient "+(recipients.length+1),color:colors[recipients.length%colors.length],order:recipients.length+1};recipients=recipients.concat([r]);activeRecipient=r.id;}
    function renameRecipient(name){if(!name.trim() || !activeRecipient)return;document.remember();recipients=recipients.map(function(r){return r.id===activeRecipient ? Object.assign({},r,{name:name.trim()}) : r;});}
    function reorder(delta){var index=recipients.findIndex(function(r){return r.id===activeRecipient;});var target=index+delta;if(index<0 || target<0 || target>=recipients.length)return;document.remember();var next=recipients.slice();var r=next.splice(index,1)[0];next.splice(target,0,r);recipients=next.map(function(r,i){return Object.assign({},r,{order:i+1});});}
    function removeRecipient(){if(!activeRecipient)return;document.remember();var id=activeRecipient;recipients=recipients.filter(function(r){return r.id!==id;}).map(function(r,i){return Object.assign({},r,{order:i+1});});fields=fields.filter(function(f){return f.recipientId!==id;});activeRecipient=nextRecipient();selectedId="";}
    function addField(x,y,w,h){if(!activeRecipient || !document.page || fields.length>=300)return;document.remember();var f={id:uid(),recipientId:activeRecipient,type:placingType,page:document.page.number-1,xN:x,yN:y,wN:w,hN:h,required:true};fields=fields.concat([f]);selectedId=f.id;}
    function updateField(id,patch){if(!fields.some(function(f){return f.id===id;}))return;document.remember();fields=fields.map(function(f){return f.id===id ? Object.assign({},f,patch) : f;});}
    function removeField(){if(!selectedId)return;document.remember();var id=selectedId;fields=fields.filter(function(f){return f.id!==id;});selectedId="";}
    function requestFill(id){var f=fields.find(function(f){return f.id===id;});if(!f || document.busy)return;if(!canSign(f.recipientId)){document.error="Complete earlier recipients' required fields first.";return;}activeRecipient=f.recipientId;selectedId=id;document.current=document.pages.findIndex(function(p){return p.number===f.page+1;});fillRequested(f);}
    function nextField(){var list=pending(activeRecipient);if(!list.length){activeRecipient=nextRecipient();list=pending(activeRecipient);}if(list.length)requestFill(list[0].id);else document.status="Every required signing field is complete.";}
    function fill(id,value){var f=fields.find(function(f){return f.id===id;});if(!f || !canSign(f.recipientId))return;document.remember();fields=fields.map(function(f){return f.id===id ? Object.assign({},f,{value:value}) : f;});audit=audit.concat([{fieldId:id,recipientId:f.recipientId,type:f.type,at:new Date().toISOString()}]);document.status="Field completed. Choose Next required to continue.";}
    function clear(){document.remember();hydrate(null,false);}
}
