import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Item {
    id:root
    required property var document
    property bool interactive:true
    Repeater {
        id:fields
        model:root.document.page ? root.document.formFields.filter(function(f){return f.page===root.document.page.number;}) : []
        delegate:Rectangle {
            id:field
            required property var modelData
            objectName:"form-"+modelData.name+"-"+modelData.id
            property string value:root.document.formValues[modelData.name] || ""
            x:modelData.x*root.width;y:modelData.y*root.height
            width:modelData.w*root.width;height:modelData.h*root.height
            color:modelData.flat ? "#2277aadd" : "white"
            border.color:editor.activeFocus ? Color.accent : "#8dabc5"
            radius:modelData.type==="radio" ? width/2 : 0
            enabled:root.interactive && !root.document.busy && !modelData.readOnly
            TextEdit {
                id:editor
                objectName:"formText-"+field.modelData.name
                anchors.fill:parent;anchors.margins:2
                visible:field.modelData.type==="text"
                text:field.value
                color:"#211d17";selectionColor:"#b6d4ff"
                font.family:"Nimbus Sans";font.pixelSize:Math.max(8,Math.min(18,parent.height*0.6))
                textFormat:TextEdit.PlainText;wrapMode:field.modelData.multiline ? TextEdit.Wrap : TextEdit.NoWrap
                selectByMouse:true;clip:true
                onTextChanged:if(activeFocus)root.document.setFormValue(field.modelData.name,text)
                onActiveFocusChanged:if(!activeFocus)root.document.finishFormEdit()
                Keys.onPressed:function(event){if((event.key===Qt.Key_Return || event.key===Qt.Key_Enter) && !field.modelData.multiline){root.forceActiveFocus();event.accepted=true;}}
            }
            Text {
                anchors.centerIn:parent
                visible:field.modelData.type==="checkbox"
                text:field.value===field.modelData.onValue ? "✓" : ""
                color:"#211d17";font.pixelSize:Math.max(8,parent.height*0.8)
            }
            Rectangle {
                anchors.centerIn:parent
                visible:field.modelData.type==="radio" && field.value===field.modelData.onValue
                width:parent.width*0.55;height:parent.height*0.55;radius:width/2;color:"#211d17"
            }
            MouseArea {
                anchors.fill:parent
                visible:field.modelData.type==="checkbox" || field.modelData.type==="radio"
                onClicked:{root.document.finishFormEdit();root.document.setFormValue(field.modelData.name,field.modelData.type==="checkbox" && field.value ? "" : field.modelData.onValue);root.document.finishFormEdit();}
            }
            Controls.ComboBox {
                objectName:"formSelect-"+field.modelData.name
                anchors.fill:parent
                visible:field.modelData.type==="dropdown"
                model:field.modelData.options
                textRole:"label";valueRole:"value"
                currentIndex:field.modelData.options.findIndex(function(option){return option.value===field.value;})
                font.family:"Nimbus Sans";font.pixelSize:Math.max(8,Math.min(18,height*0.6))
                background:Rectangle{color:"white";border.color:"#8dabc5"}
                contentItem:Text{text:parent.displayText;color:"#211d17";font:parent.font;verticalAlignment:Text.AlignVCenter;leftPadding:3;elide:Text.ElideRight}
                onActivated:{root.document.finishFormEdit();root.document.setFormValue(field.modelData.name,currentValue);root.document.finishFormEdit();}
            }
        }
    }
}
