import QtQuick
import qs.Commons
import qs.Ui

Column {
    id:root
    required property var document
    readonly property var signing:document.signing
    signal exportRequested(bool finalize)
    spacing:6
    enabled:!document.busy
    Flow {
        width:parent.width;spacing:6
        Button{text:"Prepare fields";selected:root.signing.mode==="prepare";onClicked:root.signing.mode="prepare"}
        Button{text:"Fill in order";selected:root.signing.mode==="sign";onClicked:{root.signing.mode="sign";root.signing.activeRecipient=root.signing.nextRecipient();}}
        Button{text:"Next required";visible:root.signing.mode==="sign";onClicked:root.signing.nextField()}
        Button{text:"Save handoff PDF";enabled:root.signing.recipients.length>0;onClicked:root.exportRequested(false)}
        Button{text:"Finalize and seal";enabled:root.signing.fields.length>0 && root.signing.complete;onClicked:root.exportRequested(true)}
        Button{text:"Clear signing setup";onClicked:root.signing.clear()}
        Button{text:"Hide signing panel";onClicked:root.signing.mode=""}
    }
    Flow {
        width:parent.width;spacing:6
        Repeater {
            model:root.signing.recipients
            delegate:Button {required property var modelData;text:modelData.order+". "+modelData.name+" ("+root.signing.pending(modelData.id).length+" left)";selected:root.signing.activeRecipient===modelData.id;onClicked:root.signing.activeRecipient=modelData.id}
        }
    }
    Flow {
        width:parent.width;spacing:6;visible:root.signing.mode==="prepare"
        TextField{id:name;objectName:"recipientName";width:180;placeholderText:"Recipient name";onAccepted:{root.signing.addRecipient(text);text="";}}
        Button{objectName:"addRecipient";text:"Add recipient";onClicked:{root.signing.addRecipient(name.text);name.text="";}}
        Button{text:"Rename selected";enabled:name.text.trim()!=="" && root.signing.activeRecipient!=="";onClicked:{root.signing.renameRecipient(name.text);name.text="";}}
        Button{text:"Earlier";onClicked:root.signing.reorder(-1)}
        Button{text:"Later";onClicked:root.signing.reorder(1)}
        Button{text:"Remove recipient";onClicked:root.signing.removeRecipient()}
        Repeater{model:["signature","initial","date","name","text","checkbox"];delegate:Button{required property string modelData;objectName:"fieldType-"+modelData;text:modelData;selected:root.signing.placingType===modelData;onClicked:root.signing.placingType=modelData}}
        Button{text:root.signing.selected && root.signing.selected.required ? "Required field" : "Optional field";visible:root.signing.selected!==null;selected:root.signing.selected && root.signing.selected.required;onClicked:root.signing.updateField(root.signing.selectedId,{required:!root.signing.selected.required})}
        Button{text:"Delete field";visible:root.signing.selected!==null;onClicked:root.signing.removeField()}
    }
    Text{width:parent.width;text:root.signing.mode==="prepare" ? "Select a recipient and field type, then drag a box on the PDF. Drag an existing field to move it; use its corner to resize." : "Click a field or choose Next required. Save a handoff PDF for the next recipient to open locally.";color:Color.foreground;opacity:0.7;font.family:Style.font.family;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap}
}
