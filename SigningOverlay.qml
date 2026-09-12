import QtQuick

Item {
    id:root
    required property var document
    readonly property var signing:document.signing
    property var draft:null
    enabled:!document.busy
    Keys.onPressed:function(event){if(root.signing.mode==="prepare" && (event.key===Qt.Key_Delete || event.key===Qt.Key_Backspace)){root.signing.removeField();event.accepted=true;}}
    MouseArea {
        objectName:"signingPageInput"
        preventStealing:true
        anchors.fill:parent;enabled:root.signing.mode==="prepare"
        property real startX:0;property real startY:0
        cursorShape:Qt.CrossCursor
        onPressed:function(mouse){root.forceActiveFocus();startX=Math.max(0,Math.min(1,mouse.x/width));startY=Math.max(0,Math.min(1,mouse.y/height));root.draft={x:startX,y:startY,w:0,h:0};}
        onPositionChanged:function(mouse){if(pressed){var x=Math.max(0,Math.min(1,mouse.x/width)),y=Math.max(0,Math.min(1,mouse.y/height));root.draft={x:Math.min(x,startX),y:Math.min(y,startY),w:Math.abs(x-startX),h:Math.abs(y-startY)};}}
        onReleased:{var d=root.draft;if(d && d.w>0.01 && d.h>0.01)root.signing.addField(d.x,d.y,d.w,d.h);root.draft=null;}
        onCanceled:root.draft=null
    }
    Rectangle{visible:root.draft!==null;x:root.draft ? root.draft.x*root.width : 0;y:root.draft ? root.draft.y*root.height : 0;width:root.draft ? root.draft.w*root.width : 0;height:root.draft ? root.draft.h*root.height : 0;color:"#335a99dd";border.color:"#4279c2"}
    Repeater {
        model:root.document.page ? root.signing.fields.filter(function(f){return f.page===root.document.page.number-1;}) : []
        delegate:Rectangle {
            id:field
            objectName:"signingField-"+modelData.id
            required property var modelData
            property var recipient:root.signing.recipients.find(function(r){return r.id===modelData.recipientId;})
            property real dx:0;property real dy:0;property bool resizing:false
            x:(modelData.xN+(resizing ? 0 : dx))*root.width;y:(modelData.yN+(resizing ? 0 : dy))*root.height
            width:(modelData.wN+(resizing ? dx : 0))*root.width;height:(modelData.hN+(resizing ? dy : 0))*root.height
            color:modelData.value ? "transparent" : "#2277aadd"
            border.color:recipient ? recipient.color : "#4279c2";border.width:root.signing.selectedId===modelData.id ? 2 : 1
            Image{anchors.fill:parent;source:field.modelData.value && field.modelData.value.kind==="image" ? field.modelData.value.dataUrl : "";fillMode:Image.Stretch}
            Text{anchors.fill:parent;anchors.margins:2;verticalAlignment:Text.AlignVCenter;wrapMode:Text.Wrap;clip:true;color:"#211d17";font.family:"Nimbus Sans";font.pixelSize:Math.max(8,Math.min(18,parent.height*0.66));text:field.modelData.value ? field.modelData.value.kind==="text" ? field.modelData.value.text : field.modelData.value.kind==="check" ? field.modelData.value.checked ? "X" : "" : "" : field.modelData.type+(field.modelData.required ? " *" : "")}
            Rectangle{width:8;height:8;anchors.right:parent.right;anchors.bottom:parent.bottom;color:parent.border.color;visible:root.signing.mode==="prepare"}
            MouseArea {
                preventStealing:true
                anchors.fill:parent
                property real startX:0;property real startY:0
                onPressed:function(mouse){root.forceActiveFocus();root.signing.selectedId=field.modelData.id;var p=mapToItem(root,mouse.x,mouse.y);startX=p.x;startY=p.y;field.resizing=mouse.x>width-12 && mouse.y>height-12;}
                onPositionChanged:function(mouse){if(!pressed || root.signing.mode!=="prepare")return;var p=mapToItem(root,mouse.x,mouse.y);var f=field.modelData;field.dx=Math.max(field.resizing ? 0.01-f.wN : -f.xN,Math.min(1-f.xN-f.wN,(p.x-startX)/root.width));field.dy=Math.max(field.resizing ? 0.01-f.hN : -f.yN,Math.min(1-f.yN-f.hN,(p.y-startY)/root.height));}
                onReleased:{if(root.signing.mode==="sign")root.signing.requestFill(field.modelData.id);else if(field.dx || field.dy){var f=field.modelData;root.signing.updateField(f.id,field.resizing ? {wN:f.wN+field.dx,hN:f.hN+field.dy} : {xN:f.xN+field.dx,yN:f.yN+field.dy});}field.dx=0;field.dy=0;field.resizing=false;}
                onCanceled:{field.dx=0;field.dy=0;field.resizing=false;}
            }
        }
    }
}
