import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Item {
    id: root
    property bool opened: false
    property bool confirmDiscard: false
    property bool exportOptions: false
    property bool openOptions: false
    property bool signatureOptions: false
    property bool colorOptions: false
    property string previousColorTool: "select"
    property bool stampOptions: false
    property bool toolsOptions: false
    property bool findOptions: false
    property bool noteOptions: false
    property var noteTarget: null
    property string imageLabel: ""
    property string nextAction: ""
    property string pickedPath: ""
    property string tool: "ink"
    property string ink: "#153355"
    property real penSize: 2
    property real textSize: 18
    property string textFont: "sans"
    readonly property bool selectedText: document.selectedMark !== null && document.selectedMark.kind === "text"
    readonly property bool editingText: selectedText || pageCanvas.textEditing
    property bool compress: true
    // Public for the integration smoke test and host introspection.
    readonly property color themeBackground: Color.background
    readonly property color themeForeground: Color.foreground
    property alias document: document
    function activateWindow() {
        var windows = Hyprland.toplevels.values;
        for (var i = 0; i < windows.length; ++i) {
            var target = windows[i];
            if (target.title === window.title && target.wayland && target.wayland.appId === "org.quickshell") {
                target.wayland.minimized = false;
                // Foreign-toplevel activation can be ignored when focus_on_activate
                // is disabled. A bar click explicitly asks Hyprland to focus it.
                var address = "address:0x" + target.address;
                Hyprland.dispatch(Hyprland.usingLua
                    ? 'hl.dsp.focus({ window = "' + address + '" })'
                    : "focuswindow " + address);
                return true;
            }
        }
        return false;
    }
    function openedPdf(path) { pickedPath=path; document.openDocument(path, ""); }
    function open() {
        opened = true;
        if (!activateWindow()) {
            activation.attempts = 0;
            activation.restart();
        }
    }
    Timer {
        id: activation
        property int attempts: 0
        interval: 50
        repeat: true
        onTriggered: if (!root.opened || root.activateWindow() || ++attempts >= 20) stop()
    }
    function changeTextFont(font) {
        textFont = font;
        if (selectedText) document.updateSelectedText(document.selectedMark.text, textSize, textFont);
    }
    function changeInk(color) {
        ink = color;
        if (selectedText) document.updateSelectedText(document.selectedMark.text, textSize, textFont, color);
    }
    function changeTextSize(delta) {
        textSize = Math.max(8, Math.min(72, textSize + delta));
        if (selectedText) document.updateSelectedText(document.selectedMark.text, textSize, textFont);
    }
    Connections {
        target: document
        function onPasswordNeeded(path) { root.pickedPath=path; root.openOptions=true; }
        function onImagePrepared(asset) {
            document.addImage(asset);
            if (root.imageLabel !== "Stamp" && root.imageLabel !== "Saved")
                document.savedSignatures = [Object.assign({},asset,{label:root.imageLabel})].concat(document.savedSignatures).slice(0,20);
            root.signatureOptions = false;
            root.stampOptions = false;
            root.tool = "select";
        }
        function onSelectedMarkChanged() {
            if (!root.selectedText) return;
            var mark = document.selectedMark;
            root.textSize = mark.size;
            root.textFont = mark.font || "sans";
            root.ink = mark.color;
        }
    }
    function close() {
        pageCanvas.finishText(true);
        if (document.busy) return;
        if (document.dirty) { nextAction = "close"; confirmDiscard = true; }
        else finishClose();
    }
    function finishClose() { document.shutdown(); opened = false; }
    function choosePdf() {
        pageCanvas.finishText(true);
        if (document.dirty) { nextAction = "open"; confirmDiscard = true; }
        else pdfPicker.open();
    }
    function discard() {
        confirmDiscard = false;
        if (nextAction === "close") finishClose();
        else pdfPicker.open();
    }
    DocumentController { id: document }
    FileDialog {
        id: pdfPicker
        title: "Open a PDF"
        nameFilters: ["PDF documents (*.pdf)"]
        onAccepted: {
            root.openedPdf(document.filePath(selectedFile));
        }
    }
    FileDialog {
        id: newImagesPicker
        title:"Create a PDF from images"
        fileMode:FileDialog.OpenFiles
        nameFilters:["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted:document.fromImages(selectedFiles.map(function(url){return document.filePath(url);}))
    }
    FileDialog {
        id: savePicker
        title: "Export PDF"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pdf"
        nameFilters: ["PDF documents (*.pdf)"]
        onAccepted: {
            document.exportDocument(document.filePath(selectedFile), root.compress, exportPassword.text);
            exportPassword.text = "";
            root.exportOptions = false;
        }
    }
    component Label: Text {
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
    }
    FloatingWindow {
        id: window
        title: (document.dirty || pageCanvas.textDraftDirty ? "• " : "") + (document.loaded ? document.fileName + " — " : "") + "PDFSeal"
        visible: root.opened
        implicitWidth: 1120
        implicitHeight: 800
        minimumSize: Qt.size(900, 620)
        color: Color.background
        onClosed: {
            pageCanvas.finishText(true);
            if (document.busy || document.dirty) {
                root.opened = false;
                Qt.callLater(function() {
                    root.opened = true;
                    if (!document.busy) { root.nextAction = "close"; root.confirmDiscard = true; }
                });
            } else { root.opened = false; document.shutdown(); }
        }

        Rectangle {
            anchors.fill: parent
            color: Color.background
            focus: true
            Keys.onPressed: function(event) {
                if (root.signatureOptions || root.stampOptions || root.colorOptions || root.toolsOptions || root.noteOptions) return;
                if (event.modifiers & Qt.ControlModifier) {
                    if (event.key===Qt.Key_F) {root.findOptions=true;Qt.callLater(function(){findText.forceActiveFocus();});event.accepted=true;}
                    else if (event.key === Qt.Key_O) { root.choosePdf(); event.accepted = true; }
                    else if (event.key === Qt.Key_S && document.loaded) { pageCanvas.finishText(true); root.exportOptions = true; event.accepted = true; }
                    else if (event.key === Qt.Key_Z) {
                        if (event.modifiers & Qt.ShiftModifier) document.redo(); else document.undo();
                        event.accepted = true;
                    }
                } else if (event.key === Qt.Key_Delete) { document.removeMark(); event.accepted = true; }
            }
            Column {
                anchors.fill: parent
                anchors.margins: Style.space(18)
                spacing: Style.space(12)
                Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Label {
                        text: "PDFSeal"
                        font.bold: true
                        font.pixelSize: Style.font.subtitle
                        width: Math.max(110, parent.width - (imagesButton.visible ? imagesButton.width+parent.spacing : 0) - openButton.width - exportButton.width - closeButton.width - parent.spacing * 3)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button {id:imagesButton;visible:!document.loaded;text:"Images → PDF";enabled:!document.busy;onClicked:newImagesPicker.open()}
                    Button { id: openButton; text: "Open PDF"; focusable: true; bordered: true; enabled: !document.busy; onClicked: root.choosePdf() }
                    Button { id: exportButton; text: "Export PDF"; focusable: true; selected: true; enabled: document.loaded && document.operation === ""; onClicked: { pageCanvas.finishText(true); root.exportOptions = !root.exportOptions; } }
                    Button { id: closeButton; text: document.busy ? "Cancel operation" : "Close"; focusable: true; onClicked: document.busy ? document.cancel() : root.close() }
                }
                Flow {
                    width: parent.width
                    visible: document.loaded
                    spacing: Style.space(6)
                    Repeater {
                        model: [{id:"select",label:"Select"},{id:"signature",label:"Signature"},{id:"stamp",label:"Stamp"},{id:"ink",label:"Draw"},{id:"text",label:"Text"},{id:"editText",label:"Edit PDF text"},{id:"note",label:"Comment"},{id:"redact",label:"Redact"},{id:"highlight",label:"Highlight"},{id:"box",label:"Box"}]
                        delegate: Button {
                            required property var modelData
                            objectName: "tool-" + modelData.id
                            text: modelData.label
                            selected: root.tool === modelData.id
                            focusable: true
                            enabled: !document.busy
                            onClicked: {
                                pageCanvas.finishText(true);
                                if (modelData.id === "signature") { document.error=""; root.signatureOptions=true; return; }
                                if (modelData.id === "stamp") { document.error=""; root.stampOptions=true; return; }
                                root.tool=modelData.id;
                                if (modelData.id === "highlight") root.ink = "#efcb43";
                                else if (root.ink === "#efcb43") root.ink = "#153355";
                            }
                        }
                    }
                    Button {text:"Find";onClicked:{root.findOptions=!root.findOptions;if(root.findOptions)findText.forceActiveFocus();}}
                    Button { objectName:"openDocumentTools"; text:"Tools"; enabled:!document.busy; onClicked:{pageCanvas.finishText(true);root.toolsOptions=true;} }
                    Button { text: "Undo"; focusable: true; enabled: !document.busy && document.undoStack.length > 0; onClicked: {pageCanvas.finishText(true);document.undo();} }
                    Button { text: "Redo"; focusable: true; enabled: !document.busy && document.redoStack.length > 0; onClicked: {pageCanvas.finishText(true);document.redo();} }
                    Button { text: "Remove mark"; focusable: true; enabled: !document.busy && document.selected >= 0; onClicked: {pageCanvas.finishText(false);document.removeMark();} }
                }
                Row {
                    visible:root.findOptions && document.loaded
                    width:parent.width;spacing:8
                    TextField{id:findText;width:Math.max(160,parent.width-300);placeholderText:"Find in PDF";onAccepted:document.search(text)}
                    Button{text:"Find";enabled:!document.busy;onClicked:document.search(findText.text)}
                    Button{text:"←";enabled:document.searchHits.length>0;onClicked:document.nextSearch(-1)}
                    Button{text:"→";enabled:document.searchHits.length>0;onClicked:document.nextSearch(1)}
                    Label{text:document.searchHits.length ? (document.searchIndex+1)+" / "+document.searchHits.length : ""}
                }
                Rectangle {
                    width: parent.width
                    height: Style.space(1)
                    color: Color.muted
                    opacity: 0.35
                }
                Row {
                    id: body
                    width: parent.width
                    height: parent.height - y - footer.height - parent.spacing
                    spacing: Style.space(16)
                    Column {
                        id: sidebar
                        width: Style.space(185)
                        height: parent.height
                        spacing: Style.space(10)
                        visible: document.loaded
                        Label { text: "INK"; opacity: 0.6; font.pixelSize: Style.font.bodySmall }
                        Row {
                            spacing: Style.space(7)
                            Repeater {
                                model: ["#153355", "#1a1a1a", "#b33e35", "#efcb43"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: Style.space(27); height: width; radius: width / 2
                                    color: modelData
                                    border.width: root.ink === modelData ? 3 : 1
                                    border.color: root.ink === modelData ? Color.accent : Color.muted
                                    MouseArea { anchors.fill: parent; onClicked: root.changeInk(parent.modelData) }
                                }
                            }
                        }
                        Button {
                            objectName:"openColorPicker"
                            width:parent.width
                            text:"Custom color…"
                            enabled:!document.busy
                            onClicked:{pageCanvas.finishText(true);root.colorOptions=true;}
                        }
                        Row {
                            spacing: Style.space(6)
                            Button { text: "−"; onClicked: root.penSize = Math.max(0.5, root.penSize - 0.5) }
                            Label { text: root.penSize.toFixed(1) + " pt"; anchors.verticalCenter: parent.verticalCenter }
                            Button { text: "+"; onClicked: root.penSize = Math.min(12, root.penSize + 0.5) }
                        }
                        Button {
                            objectName: "editSelectedText"
                            width: parent.width
                            visible: root.selectedText && !pageCanvas.textEditing
                            enabled: !document.busy
                            text: "Edit selected text"
                            onClicked: pageCanvas.beginText(document.selected, 0, 0)
                        }
                        Button{width:parent.width;visible:document.selectedMark!==null && document.selectedMark.kind==="note";text:"Edit comment";onClicked:{root.noteTarget={index:document.selected,x:0,y:0};root.noteOptions=true;}}
                        Flow {
                            width: parent.width
                            visible: root.tool === "text" || root.editingText
                            spacing: Style.space(3)
                            Repeater {
                                model: [{id:"sans",label:"Sans"},{id:"serif",label:"Serif"},{id:"mono",label:"Mono"}]
                                delegate: Button {
                                    required property var modelData
                                    objectName: "font-" + modelData.id
                                    text: modelData.label
                                    selected: root.textFont === modelData.id
                                    enabled: !document.busy
                                    onClicked: root.changeTextFont(modelData.id)
                                }
                            }
                        }
                        Row {
                            visible: root.tool === "text" || root.editingText
                            enabled: !document.busy
                            spacing: Style.space(6)
                            Button { objectName: "decreaseTextSize"; text: "A−"; onClicked: root.changeTextSize(-2) }
                            Label { text: root.textSize + " pt"; anchors.verticalCenter: parent.verticalCenter }
                            Button { objectName: "increaseTextSize"; text: "A+"; onClicked: root.changeTextSize(2) }
                        }
                        Label {
                            width: parent.width
                            visible: root.tool === "text" || root.editingText
                            font.pixelSize: Style.font.bodySmall
                            opacity: 0.7
                            text: pageCanvas.textEditing ? "Type on the page. Enter saves; Escape cancels." : root.selectedText ? "Double-click text to edit. Drag to move it." : "Click the page and start typing."
                        }
                        Label{width:parent.width;visible:root.tool==="editText";text:"Click an outlined line to cover and retype it. Fonts are approximate; covered text remains in the PDF. Use Redact to remove content.";font.pixelSize:Style.font.bodySmall;opacity:0.7}
                        Button{width:parent.width;visible:root.tool==="redact";text:"Apply true redaction";onClicked:{root.toolsOptions=true;documentTools.action="redact";}}
                        Label { text: "PAGES"; opacity: 0.6; font.pixelSize: Style.font.bodySmall }
                        ListView {
                            width: parent.width
                            height: Math.max(60, parent.height - y - pageActions.implicitHeight - zoomControls.implicitHeight - Style.space(25))
                            clip: true
                            model: document.pages
                            spacing: Style.space(4)
                            delegate: Button {
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                text: "Page " + modelData.number + (modelData.rotation ? "  ↻ " + modelData.rotation + "°" : "")
                                selected: document.current === index
                                focusable: true
                                enabled: !document.busy
                                onClicked: {pageCanvas.finishText(true);document.current=index;}
                            }
                        }
                        Column {
                            id: pageActions
                            width: parent.width
                            spacing: Style.space(5)
                            Row {
                                spacing: Style.space(5)
                                Button { text: "↑"; enabled: !document.busy && document.current > 0; onClicked: {pageCanvas.finishText(true);document.movePage(-1);} }
                                Button { text: "↓"; enabled: !document.busy && document.current < document.pages.length - 1; onClicked: {pageCanvas.finishText(true);document.movePage(1);} }
                                Button { text: "Rotate"; enabled: !document.busy; onClicked: {pageCanvas.finishText(true);document.rotatePage();} }
                            }
                            Button { width: parent.width; text: "Remove page"; enabled: !document.busy && document.pages.length > 1; onClicked: {pageCanvas.finishText(true);document.removePage();} }
                        }
                        Row {
                            id: zoomControls
                            spacing: Style.space(5)
                            Button { text: "−"; onClicked: viewport.zoomAt(document.zoom-0.25,viewport.width/2,viewport.height/2) }
                            Label { text: Math.round(document.zoom * 100) + "%"; anchors.verticalCenter: parent.verticalCenter }
                            Button { text: "+"; onClicked: viewport.zoomAt(document.zoom+0.25,viewport.width/2,viewport.height/2) }
                        }
                    }
                    Rectangle {
                        width: parent.width - (sidebar.visible ? sidebar.width + parent.spacing : 0)
                        height: parent.height
                        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.045)
                        radius: Style.cornerRadius
                        Label {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 60, Style.space(440))
                            horizontalAlignment: Text.AlignHCenter
                            text: document.loaded ? "Rendering page…" : "Sign a document. Keep it local.\n\nDraw signatures, add text and highlights, arrange pages, and export a PDF.\n\nOpen a PDF to begin."
                            visible: !document.loaded || document.preview === ""
                        }
                        Flickable {
                            id: viewport
                            objectName: "pdfViewport"
                            function zoomAt(value, px, py) {
                                if (!document.loaded || document.busy) return;
                                var next=Math.max(0.5,Math.min(5,value));
                                var ratio=next/document.zoom;
                                var pageX=(contentX+px-pageFrame.x)*ratio;
                                var pageY=(contentY+py-pageFrame.y)*ratio;
                                document.zoom=next;
                                contentX=Math.max(0,Math.min(contentWidth-width,pageFrame.x+pageX-px));
                                contentY=Math.max(0,Math.min(contentHeight-height,pageFrame.y+pageY-py));
                            }
                            PinchHandler {
                                id: pdfPinch
                                objectName: "pdfPinch"
                                target: null
                                enabled: document.loaded && !document.busy
                                acceptedDevices: PointerDevice.TouchPad | PointerDevice.TouchScreen
                                property real startingZoom: 1
                                onActiveChanged: if (active) { pageCanvas.finishText(true); startingZoom=document.zoom; viewport.cancelFlick(); }
                                onActiveScaleChanged: if (active) viewport.zoomAt(startingZoom*activeScale,centroid.position.x,centroid.position.y)
                            }
                            WheelHandler {
                                target: null
                                acceptedModifiers: Qt.ControlModifier
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: function(event) {
                                    var delta=event.angleDelta.y || event.pixelDelta.y;
                                    viewport.zoomAt(document.zoom*Math.exp(delta/600),event.x,event.y);
                                    event.accepted=true;
                                }
                            }
                            anchors.fill: parent
                            anchors.margins: Style.space(16)
                            clip: true
                            visible: document.loaded && document.preview !== ""
                            contentWidth: Math.max(width, pageFrame.width)
                            contentHeight: Math.max(height, pageFrame.height)
                            boundsBehavior: Flickable.StopAtBounds
                            Item {
                                id: pageFrame
                                property bool sideways: document.page ? document.page.rotation % 180 !== 0 : false
                                property real factor: document.page ? Math.min((viewport.width - 8) / (sideways ? document.page.height : document.page.width), (viewport.height - 8) / (sideways ? document.page.width : document.page.height)) * document.zoom : 1
                                width: document.page ? (sideways ? document.page.height : document.page.width) * factor : 0
                                height: document.page ? (sideways ? document.page.width : document.page.height) * factor : 0
                                x: Math.max(0, (viewport.width - width) / 2)
                                y: Math.max(0, (viewport.height - height) / 2)
                                PageCanvas {
                                    id: pageCanvas
                                    anchors.centerIn: parent
                                    width: document.page ? document.page.width * pageFrame.factor : 0
                                    height: document.page ? document.page.height * pageFrame.factor : 0
                                    rotation: document.page ? document.page.rotation : 0
                                    document: root.document
                                    tool: root.tool
                                    inkColor: root.ink
                                    strokeSize: root.penSize
                                    textSize: root.textSize
                                    textFont: root.textFont
                                    onExistingTextEditingStarted:function(size){root.textSize=Math.round(size);root.textFont="sans";root.ink="#000000";}
                                    onNoteRequested:function(index,x,y){root.noteTarget={index:index,x:x,y:y};root.noteOptions=true;}
                                    previewInk:root.colorOptions ? colorPicker.hexColor : ""
                                    onColorPicked:function(color){root.changeInk(color);root.tool=root.previousColorTool;document.status="Color "+color+" selected.";}
                                    onColorPickCancelled:{root.tool=root.previousColorTool;document.status="Color sampling cancelled.";}
                                    onTextEditingStarted: root.tool = "select"
                                }
                            }
                        }
                    }
                }
                Label {
                    id: footer
                    width: parent.width
                    text: document.error || document.status
                    color: document.error ? Color.urgent : Color.foreground
                    font.pixelSize: Style.font.bodySmall
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: root.confirmDiscard || root.openOptions || root.exportOptions
                color: Qt.rgba(0, 0, 0, 0.55)
                MouseArea { anchors.fill: parent }
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, Style.space(450))
                    height: dialogContent.implicitHeight + Style.space(40)
                    color: Color.background
                    border.color: Color.accent
                    border.width: Style.space(1)
                    radius: Style.cornerRadius
                    Column {
                        id: dialogContent
                        anchors.centerIn: parent
                        width: parent.width - Style.space(40)
                        spacing: Style.space(12)
                        Label {
                            width: parent.width
                            font.bold: true
                            font.pixelSize: Style.font.subtitle
                            text: root.confirmDiscard ? "Discard unsaved changes?" : root.openOptions ? "Open PDF" : "Export PDF"
                        }
                        Label {
                            width: parent.width
                            text: root.confirmDiscard ? "Your original file is unchanged. Export first to keep your edits." : root.openOptions ? "This PDF requires a password to open." : "Save a new copy with your signatures, annotations and page changes."
                        }
                        TextField { id: openPassword; width: parent.width; visible: root.openOptions; password: true; placeholderText: "Password (optional)" }
                        TextField { id: exportPassword; width: parent.width; visible: root.exportOptions; password: true; placeholderText: "Protect with a password (optional)" }
                        Button { width: parent.width; visible: root.exportOptions; text: "Lossless compression"; selected: root.compress; onClicked: root.compress = !root.compress }
                        Label { width: parent.width; visible: root.exportOptions; text: "Leaving the password empty creates an unencrypted copy."; opacity: 0.7; font.pixelSize: Style.font.bodySmall }
                        Row {
                            spacing: Style.space(8)
                            Button {
                                text: "Cancel"
                                focusable: true
                                onClicked: { root.confirmDiscard = false; root.openOptions = false; root.exportOptions = false; openPassword.text = ""; exportPassword.text = ""; }
                            }
                            Button {
                                text: root.confirmDiscard ? "Discard" : root.openOptions ? "Open" : "Choose destination"
                                selected: true
                                focusable: true
                                onClicked: {
                                    if (root.confirmDiscard) root.discard();
                                    else if (root.openOptions) {
                                        document.openDocument(root.pickedPath, openPassword.text);
                                        openPassword.text = "";
                                        root.openOptions = false;
                                    } else {
                                        savePicker.selectedFile = document.fileUrl(document.sourcePath.replace(/[^/]+$/, "signed-" + document.fileName));
                                        savePicker.open();
                                    }
                                }
                            }
                        }
                    }
                }
            }
            NoteDialog {
                anchors.fill:parent;visible:root.noteOptions
                value:root.noteTarget && root.noteTarget.index>=0 ? document.marks[root.noteTarget.index].text : ""
                onAccepted:function(text){document.saveNote(root.noteTarget.index,text,root.noteTarget.x,root.noteTarget.y,"#efcb43");root.noteOptions=false;root.tool="select";}
                onDismissed:root.noteOptions=false
            }
            ColorPicker {
                id:colorPicker
                objectName:"colorPicker"
                anchors.fill:parent
                visible:root.colorOptions
                initialColor:root.ink
                onAccepted:function(color){root.changeInk(color);root.colorOptions=false;}
                onDismissed:root.colorOptions=false
                onEyedropperRequested:{root.colorOptions=false;root.previousColorTool=root.tool;root.tool="eyedropper";pageCanvas.forceActiveFocus();document.status="Click a color on the PDF. Escape cancels.";}
            }
            ToolsDialog {
                id:documentTools
                anchors.fill:parent
                visible:root.toolsOptions
                document:root.document
                onDismissed:root.toolsOptions=false
            }
            SignatureDialog {
                objectName: "signatureDialog"
                anchors.fill: parent
                visible: root.signatureOptions
                document: root.document
                onSubmitted: function(source, label) { root.imageLabel=label; root.document.prepareImage(source); }
                onDismissed: root.signatureOptions=false
            }
            StampPicker {
                anchors.fill: parent
                visible: root.stampOptions
                document: root.document
                onSubmitted: function(source) { root.imageLabel="Stamp"; root.document.prepareImage(source); }
                onDismissed: root.stampOptions=false
            }
        }
    }
}
