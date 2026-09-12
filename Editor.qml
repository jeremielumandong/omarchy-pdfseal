import QtQuick
import QtQuick.Dialogs
import Quickshell
import qs.Commons
import qs.Ui

Item {
    id: root
    property bool opened: false
    property bool confirmDiscard: false
    property bool exportOptions: false
    property bool openOptions: false
    property string nextAction: ""
    property string pickedPath: ""
    property string tool: "ink"
    property string ink: "#153355"
    property real penSize: 2
    property bool compress: true
    // Public for the integration smoke test and host introspection.
    readonly property color themeBackground: Color.background
    readonly property color themeForeground: Color.foreground
    property alias document: document
    function open() { opened = true; }
    function close() {
        if (document.busy) return;
        if (document.dirty) { nextAction = "close"; confirmDiscard = true; }
        else finishClose();
    }
    function finishClose() { document.shutdown(); opened = false; }
    function choosePdf() {
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
            root.pickedPath = document.filePath(selectedFile);
            root.openOptions = true;
        }
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
        title: (document.dirty ? "• " : "") + (document.loaded ? document.fileName + " — " : "") + "PDFSeal"
        visible: root.opened
        implicitWidth: 1120
        implicitHeight: 800
        minimumSize: Qt.size(900, 620)
        color: Color.background
        onClosed: {
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
                if (event.modifiers & Qt.ControlModifier) {
                    if (event.key === Qt.Key_O) { root.choosePdf(); event.accepted = true; }
                    else if (event.key === Qt.Key_S && document.loaded) { root.exportOptions = true; event.accepted = true; }
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
                        width: Math.max(110, parent.width - openButton.width - exportButton.width - closeButton.width - parent.spacing * 3)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button { id: openButton; text: "Open PDF"; focusable: true; bordered: true; enabled: !document.busy; onClicked: root.choosePdf() }
                    Button { id: exportButton; text: "Export PDF"; focusable: true; selected: true; enabled: document.loaded && document.operation === ""; onClicked: root.exportOptions = !root.exportOptions }
                    Button { id: closeButton; text: "Close"; focusable: true; enabled: !document.busy; onClicked: root.close() }
                }
                Row {
                    width: parent.width
                    visible: document.loaded
                    spacing: Style.space(6)
                    Repeater {
                        model: [{id:"select",label:"Select"},{id:"ink",label:"Sign / draw"},{id:"text",label:"Text"},{id:"highlight",label:"Highlight"},{id:"box",label:"Box"}]
                        delegate: Button {
                            required property var modelData
                            text: modelData.label
                            selected: root.tool === modelData.id
                            focusable: true
                            enabled: !document.busy
                            onClicked: { root.tool = modelData.id; if (modelData.id === "highlight") root.ink = "#efcb43"; else if (root.ink === "#efcb43") root.ink = "#153355"; }
                        }
                    }
                    Button { text: "Undo"; focusable: true; enabled: !document.busy && document.undoStack.length > 0; onClicked: document.undo() }
                    Button { text: "Redo"; focusable: true; enabled: !document.busy && document.redoStack.length > 0; onClicked: document.redo() }
                    Button { text: "Remove mark"; focusable: true; enabled: !document.busy && document.selected >= 0; onClicked: document.removeMark() }
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
                                    MouseArea { anchors.fill: parent; onClicked: root.ink = parent.modelData }
                                }
                            }
                        }
                        Row {
                            spacing: Style.space(6)
                            Button { text: "−"; onClicked: root.penSize = Math.max(0.5, root.penSize - 0.5) }
                            Label { text: root.penSize.toFixed(1) + " pt"; anchors.verticalCenter: parent.verticalCenter }
                            Button { text: "+"; onClicked: root.penSize = Math.min(12, root.penSize + 0.5) }
                        }
                        TextField {
                            id: annotationText
                            width: parent.width
                            visible: root.tool === "text"
                            placeholderText: "Text to place"
                            maximumLength: 160
                        }
                        Row {
                            visible: root.tool === "text"
                            spacing: Style.space(6)
                            Button { text: "A−"; onClicked: pageCanvas.textSize = Math.max(8, pageCanvas.textSize - 2) }
                            Label { text: pageCanvas.textSize + " pt"; anchors.verticalCenter: parent.verticalCenter }
                            Button { text: "A+"; onClicked: pageCanvas.textSize = Math.min(72, pageCanvas.textSize + 2) }
                        }
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
                                onClicked: document.current = index
                            }
                        }
                        Column {
                            id: pageActions
                            width: parent.width
                            spacing: Style.space(5)
                            Row {
                                spacing: Style.space(5)
                                Button { text: "↑"; enabled: !document.busy && document.current > 0; onClicked: document.movePage(-1) }
                                Button { text: "↓"; enabled: !document.busy && document.current < document.pages.length - 1; onClicked: document.movePage(1) }
                                Button { text: "Rotate"; enabled: !document.busy; onClicked: document.rotatePage() }
                            }
                            Button { width: parent.width; text: "Remove page"; enabled: !document.busy && document.pages.length > 1; onClicked: document.removePage() }
                        }
                        Row {
                            id: zoomControls
                            spacing: Style.space(5)
                            Button { text: "−"; onClicked: document.zoom = Math.max(0.5, document.zoom - 0.25) }
                            Label { text: Math.round(document.zoom * 100) + "%"; anchors.verticalCenter: parent.verticalCenter }
                            Button { text: "+"; onClicked: document.zoom = Math.min(3, document.zoom + 0.25) }
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
                                    textValue: annotationText.text
                                    onTextNeeded: annotationText.forceActiveFocus()
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
                            text: root.confirmDiscard ? "Your original file is unchanged. Export first to keep your edits." : root.openOptions ? "If this PDF is encrypted, enter its password." : "Save a new copy with your signatures, annotations and page changes."
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
        }
    }
}
