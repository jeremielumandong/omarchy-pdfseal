import QtQuick
import QtQuick.Dialogs
import qs.Commons
import qs.Ui

Rectangle {
    id:root
    required property var document
    signal dismissed()
    property string certificatePath:""
    property bool includeAudit:true
    color:Qt.rgba(0,0,0,0.55)
    MouseArea{anchors.fill:parent}
    FileDialog{id:certificatePicker;title:"Choose signing certificate";nameFilters:["PKCS#12 certificate (*.p12 *.pfx)"];onAccepted:root.certificatePath=root.document.filePath(selectedFile)}
    FileDialog {
        id:destination
        title:"Save digitally sealed PDF";fileMode:FileDialog.SaveFile;defaultSuffix:"pdf";nameFilters:["PDF documents (*.pdf)"]
        onAccepted:{root.document.exportDocument(root.document.filePath(selectedFile),true,"",{finalize:true,signing:root.document.signing.manifest(),certificate:root.includeAudit,seal:{name:signer.text.trim(),reason:reason.text,location:location.text,p12:root.certificatePath,password:password.text}});password.text="";root.dismissed();}
    }
    Rectangle {
        anchors.centerIn:parent;width:Math.min(parent.width-40,620);height:Math.min(parent.height-40,content.implicitHeight+40)
        color:Color.background;border.color:Color.accent;radius:Style.cornerRadius
        Flickable {
            anchors.fill:parent;anchors.margins:20;contentHeight:content.implicitHeight;clip:true
            Column {
                id:content;width:parent.width;spacing:12
                Text{text:"Finalize and digitally seal";color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.subtitle;font.bold:true}
                TextField{id:signer;objectName:"sealSigner";width:parent.width;placeholderText:"Signer name"}
                TextField{id:reason;width:parent.width;placeholderText:"Reason (optional)"}
                TextField{id:location;width:parent.width;placeholderText:"Location (optional)"}
                Flow{width:parent.width;spacing:8;Button{text:root.certificatePath ? root.certificatePath.split("/").pop() : "Import .p12 / .pfx";onClicked:certificatePicker.open()}Button{text:"Use local self-signed certificate";selected:!root.certificatePath;onClicked:{root.certificatePath="";password.text="";}}}
                TextField{id:password;width:parent.width;visible:root.certificatePath!=="";password:true;placeholderText:"Certificate password"}
                Button{text:"Append Certificate of Completion";selected:root.includeAudit;onClicked:root.includeAudit=!root.includeAudit}
                Text{width:parent.width;text:root.certificatePath ? "The certificate and private key are used locally. The final seal makes later changes detectable. Certificate trust depends on the recipient's PDF viewer." : "Creates a local self-signed certificate. It provides tamper evidence; identity is self-asserted and timestamps use this device's clock.";color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.body;wrapMode:Text.WordWrap}
                Text{width:parent.width;text:"The saved file is final. Required fields must be completed, form values are flattened, and the digital seal is added last.";color:Color.foreground;opacity:0.7;font.family:Style.font.family;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap}
                Row{spacing:8;Button{text:"Cancel";onClicked:{password.text="";root.dismissed();}}Button{objectName:"saveSealedPdf";text:"Choose destination";selected:true;enabled:signer.text.trim()!=="" && root.document.signing.complete && !root.document.busy;onClicked:{destination.selectedFile=root.document.fileUrl(root.document.sourcePath.replace(/[^/]+$/,"sealed-"+root.document.fileName));destination.open();}}}
            }
        }
    }
}
