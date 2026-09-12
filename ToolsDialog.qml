import QtQuick
import QtQuick.Dialogs
import qs.Commons
import qs.Ui

Rectangle {
    id: root
    required property var document
    property string action: "merge"
    property string preset: "lossless"
    property string numberPosition: "bottom-center"
    property bool allPages: true
    property string pickedFile: ""
    property var pickedImages: []
    signal dismissed()
    color: Qt.rgba(0,0,0,0.55)
    MouseArea { anchors.fill: parent }
    function run() {
        var values = {};
        if (action === "merge") values = {file:pickedFile,filePassword:password.text};
        else if (action === "images") values = {paths:pickedImages};
        else if (action === "duplicate") values = {number:document.current+1};
        else if (action === "extract") values = {selection:range.text};
        else if (action === "crop") {
            values = {left:Number(left.text)/100,top:Number(top.text)/100,right:Number(right.text)/100,bottom:Number(bottom.text)/100};
            if (!allPages) values.only=document.current+1;
        } else if (action === "watermark") values = {text:watermark.text,size:Number(watermarkSize.text),opacity:Number(opacity.text)/100,rotation:Number(angle.text)};
        else if (action === "numbers") values = {size:Number(numberSize.text),start:Number(start.text),position:numberPosition};
        else if (action === "compress") values = {preset:preset};
        else if (["split","png","jpeg"].indexOf(action)>=0) { folderPicker.open(); return; }
        document.apply(action,values);
        password.text="";
    }
    onVisibleChanged: if (visible) document.error=""
    Connections {
        target: root.document
        function onOperationFinished(result) { if (!result.candidate && !result.saved) root.dismissed(); }
    }
    FileDialog {
        id: mergePicker
        title: "Append PDF"
        nameFilters: ["PDF documents (*.pdf)"]
        onAccepted: root.pickedFile=root.document.filePath(selectedFile)
    }
    FileDialog {
        id: imagePicker
        title: "Append images as PDF pages"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: root.pickedImages=selectedFiles.map(function(url) {return root.document.filePath(url);})
    }
    FolderDialog {
        id: folderPicker
        title: "Choose export folder"
        onAccepted: root.document.apply(root.action,{folder:root.document.filePath(selectedFolder)})
    }
    FileDialog {
        id: compressionPicker
        title: "Save compressed PDF"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pdf"
        nameFilters: ["PDF documents (*.pdf)"]
        onAccepted: root.document.acceptCompression(root.document.filePath(selectedFile))
    }
    component Label: Text {
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width-40,Style.space(670))
        height: Math.min(parent.height-40,content.implicitHeight+40)
        color: Color.background
        border.color: Color.accent
        radius: Style.cornerRadius
        Flickable {
            anchors.fill: parent
            anchors.margins: 20
            contentHeight: content.implicitHeight
            clip: true
            Column {
                id: content
                width: parent.width
                spacing: Style.space(12)
                Label { text:"Document tools"; font.bold:true; font.pixelSize:Style.font.subtitle }
                Flow {
                    width: parent.width
                    spacing: Style.space(5)
                    enabled: !root.document.busy
                    Repeater {
                        model: [{id:"merge",label:"Merge PDF"},{id:"split",label:"Split"},{id:"extract",label:"Extract"},{id:"duplicate",label:"Duplicate page"},
                            {id:"crop",label:"Crop"},{id:"watermark",label:"Watermark"},{id:"numbers",label:"Page numbers"},{id:"images",label:"Images → PDF"},
                            {id:"png",label:"PDF → PNG"},{id:"jpeg",label:"PDF → JPEG"},{id:"compress",label:"Compress"},{id:"ocr",label:"OCR"},{id:"redact",label:"Apply redaction"},{id:"flatten",label:"Flatten forms"}]
                        delegate: Button {
                            required property var modelData
                            objectName:"operation-"+modelData.id
                            text:modelData.label
                            selected:root.action===modelData.id
                            onClicked: {root.action=modelData.id;root.document.compressionPreview=null;root.document.error="";}
                        }
                    }
                }
                Label {
                    width: parent.width
                    text: ["split","png","jpeg","compress"].indexOf(root.action)>=0
                        ? "Export uses your current edits. Your original file is preserved."
                        : "Applies to the edited document and clears annotation undo history. Export a copy to save the result."
                    opacity:0.7
                    font.pixelSize:Style.font.bodySmall
                }
                Column {
                    width: parent.width; spacing:8; visible:root.action==="merge"
                    Button {text:root.pickedFile ? root.pickedFile.split("/").pop() : "Choose PDF to append";onClicked:mergePicker.open()}
                    TextField {id:password;width:parent.width;password:true;placeholderText:"Password for appended PDF (optional)"}
                }
                Column {
                    width:parent.width;spacing:8;visible:root.action==="images"
                    Button {text:root.pickedImages.length ? root.pickedImages.length+" images selected" : "Choose images";onClicked:imagePicker.open()}
                    Label {width:parent.width;text:"Each image becomes a new page appended to this PDF."}
                }
                TextField {id:range;width:parent.width;visible:root.action==="extract";placeholderText:"Pages, e.g. 1,3-5"}
                Column {
                    width:parent.width;spacing:8;visible:root.action==="crop"
                    Label {text:"Margins to remove (%)"}
                    Row {
                        spacing:8
                        TextField {id:left;width:115;text:"0";placeholderText:"Left"}
                        TextField {id:top;width:115;text:"0";placeholderText:"Top"}
                        TextField {id:right;width:115;text:"0";placeholderText:"Right"}
                        TextField {id:bottom;width:115;text:"0";placeholderText:"Bottom"}
                    }
                    Label {text:"Left · Top · Right · Bottom — 0 to 49 percent each";font.pixelSize:Style.font.bodySmall}
                    Button {text:root.allPages ? "All pages" : "Current page only";onClicked:root.allPages=!root.allPages}
                }
                Column {
                    width:parent.width;spacing:8;visible:root.action==="watermark"
                    TextField {id:watermark;width:parent.width;text:"CONFIDENTIAL";placeholderText:"Watermark text"}
                    Row {
                        spacing:8
                        TextField {id:watermarkSize;width:130;text:"60";placeholderText:"Font size"}
                        TextField {id:opacity;width:130;text:"25";placeholderText:"Opacity %"}
                        TextField {id:angle;width:130;text:"45";placeholderText:"Angle"}
                    }
                    Label {text:"Font size (pt) · Opacity (%) · Angle (°)";font.pixelSize:Style.font.bodySmall}
                }
                Column {
                    width:parent.width;spacing:8;visible:root.action==="numbers"
                    Row {
                        spacing:8
                        TextField {id:numberSize;width:130;text:"12";placeholderText:"Font size"}
                        TextField {id:start;width:130;text:"1";placeholderText:"Start at"}
                    }
                    Label {text:"Font size (pt) · Starting number";font.pixelSize:Style.font.bodySmall}
                    Flow {
                        width:parent.width;spacing:5
                        Repeater {
                            model:["top-left","top-center","top-right","bottom-left","bottom-center","bottom-right"]
                            delegate:Button {required property string modelData;text:modelData;selected:root.numberPosition===modelData;onClicked:root.numberPosition=modelData}
                        }
                    }
                }
                Column {
                    width:parent.width;spacing:8;visible:root.action==="compress"
                    Row {
                        spacing:8
                        Repeater {
                            model:[{id:"lossless",label:"Lossless"},{id:"images",label:"Smaller images"},{id:"compact",label:"Compact"}]
                            delegate:Button {required property var modelData;text:modelData.label;selected:root.preset===modelData.id;onClicked:{root.preset=modelData.id;root.document.compressionPreview=null;}}
                        }
                    }
                    Label {width:parent.width;text:root.preset==="compact" ? "Compact converts every page to a 120 DPI image. Text selection, links and forms are lost." : root.preset==="images" ? "Recompresses eligible images while preserving text and vectors." : "Preserves document quality and content."}
                    Label {
                        visible:root.document.compressionPreview!==null
                        text:root.document.compressionPreview ? "Before: "+(root.document.compressionPreview.before/1024).toFixed(1)+" KB → After: "+(root.document.compressionPreview.after/1024).toFixed(1)+" KB" : ""
                    }
                    Row {
                        visible:root.document.compressionPreview!==null;spacing:8;enabled:!root.document.busy
                        Button {text:"Save copy";onClicked:compressionPicker.open()}
                        Button {text:"Replace open document";onClicked:root.document.acceptCompression("")}
                    }
                }
                Label{width:parent.width;visible:root.action==="redact";text:"Permanently removes covered content by rebuilding affected pages as 300 DPI images and checking that the text is gone. Those pages lose selectable text. Embedded attachments are removed by default."}
                Button{visible:root.action==="redact";text:"Keep embedded attachments";selected:root.document.keepAttachments;onClicked:root.document.keepAttachments=!root.document.keepAttachments}
                Label {width:parent.width;visible:root.action==="ocr";text:"Recognizes English text locally and adds a searchable text layer. Page appearance is preserved."}
                Label {width:parent.width;visible:root.action==="flatten";text:"Makes filled form values and annotation appearances permanent. Fields can no longer be edited."}
                Label {width:parent.width;text:root.document.error || (root.document.busy ? root.document.status : "");visible:text!=="";color:root.document.error ? Color.urgent : Color.foreground}
                Row {
                    spacing:8
                    Button {text:root.document.busy ? "Cancel operation" : "Close";onClicked:root.document.busy ? root.document.cancel() : root.dismissed()}
                    Button {
                        objectName:"applyDocumentTool"
                        text:root.action==="compress" ? "Preview compression" : ["split","png","jpeg"].indexOf(root.action)>=0 ? "Choose export folder" : "Apply"
                        selected:true
                        enabled:!root.document.busy && (root.action!=="merge" || root.pickedFile!=="") && (root.action!=="images" || root.pickedImages.length>0)
                        onClicked:root.run()
                    }
                }
            }
        }
    }
}
