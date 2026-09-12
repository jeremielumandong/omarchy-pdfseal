import QtQuick
import QtQuick.Dialogs
import qs.Commons
import qs.Ui

Rectangle {
    id: root
    required property var document
    property string mode: "draw"
    property string signatureColor: "#1c2a4a"
    property int fontIndex: 0
    property var strokes: []
    readonly property var families: [scriptFont.name, casualFont.name, formalFont.name]
    readonly property bool fontsReady: scriptFont.status === FontLoader.Ready && casualFont.status === FontLoader.Ready && formalFont.status === FontLoader.Ready
    signal submitted(string source, string label)
    signal dismissed()
    color: Qt.rgba(0,0,0,0.55)
    focus: visible
    Keys.onEscapePressed: if (!document.busy) dismissed()
    onVisibleChanged: if (visible) { mode = "draw"; strokes = []; typedName.text = ""; preview.requestPaint(); }
    onModeChanged: { preview.requestPaint(); if (mode === "type") Qt.callLater(function() { typedName.forceActiveFocus(); }); }
    onFontIndexChanged: preview.requestPaint()
    onSignatureColorChanged: preview.requestPaint()
    FontLoader { id: scriptFont; source: Qt.resolvedUrl("assets/fonts/Sacramento.woff"); onStatusChanged: preview.requestPaint() }
    FontLoader { id: casualFont; source: Qt.resolvedUrl("assets/fonts/Caveat.woff"); onStatusChanged: preview.requestPaint() }
    FontLoader { id: formalFont; source: Qt.resolvedUrl("assets/fonts/DancingScript.woff"); onStatusChanged: preview.requestPaint() }
    FileDialog {
        id: imagePicker
        title: "Choose a signature image"
        nameFilters: ["Signature images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: root.submitted(root.document.filePath(selectedFile), "Uploaded")
    }
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, Style.space(700))
        height: content.implicitHeight + Style.space(40)
        color: Color.background
        border.color: Color.accent
        radius: Style.cornerRadius
        Column {
            id: content
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(14)
            Text { text:"Your signature"; color:Color.foreground; font.family:Style.font.family; font.pixelSize:Style.font.title }
            ListView {
                visible: root.document.savedSignatures.length > 0
                width: parent.width; height: Style.space(65)
                orientation: ListView.Horizontal; spacing: Style.space(8); clip: true
                model: root.document.savedSignatures
                delegate: Rectangle {
                    required property var modelData
                    width: Style.space(140); height: Style.space(60); color: "white"; radius: 4
                    Image { anchors.fill:parent; anchors.margins:8; source:parent.modelData.dataUrl; fillMode:Image.PreserveAspectFit }
                    MouseArea { anchors.fill:parent; enabled:!root.document.busy; onClicked:root.submitted(parent.modelData.dataUrl,"Saved") }
                }
            }
            Row {
                spacing: Style.space(8)
                Repeater {
                    model: ["draw","type","upload"]
                    delegate: Button {
                        required property string modelData
                        objectName: "signature-" + modelData
                        text: modelData[0].toUpperCase() + modelData.substring(1)
                        selected: root.mode === modelData
                        enabled: !root.document.busy
                        onClicked: root.mode = modelData
                    }
                }
            }
            Rectangle {
                width: parent.width; height: width * 0.3
                color: "white"; radius: 4; clip: true
                Canvas {
                    id: preview
                    objectName: "signaturePreview"
                    width: 1600
                    height: 480
                    scale: parent.width / width
                    transformOrigin: Item.TopLeft
                    visible: root.mode !== "upload"
                    onPaint: {
                        var ctx = getContext("2d"); ctx.reset();
                        ctx.strokeStyle = root.signatureColor; ctx.fillStyle = root.signatureColor;
                        ctx.lineWidth = 6; ctx.lineCap = "round"; ctx.lineJoin = "round";
                        if (root.mode === "type") {
                            var value = typedName.text.trim();
                            ctx.font = "192px '" + root.families[root.fontIndex] + "'";
                            var size = Math.min(192, 192 * 1450 / Math.max(1,ctx.measureText(value).width));
                            ctx.font = size + "px '" + root.families[root.fontIndex] + "'";
                            ctx.textAlign = "center"; ctx.textBaseline = "middle";
                            ctx.fillText(value,800,240);
                        } else root.strokes.forEach(function(stroke) {
                            ctx.beginPath();
                            stroke.forEach(function(p,i) { if(i===0)ctx.moveTo(p[0]*1600,p[1]*480);else ctx.lineTo(p[0]*1600,p[1]*480); });
                            ctx.stroke();
                        });
                    }
                    MouseArea {
                        objectName: "signatureDrawingPad"
                        anchors.fill: parent
                        enabled: root.mode === "draw" && !root.document.busy
                        function point(mouse) { return [Math.max(0,Math.min(1,mouse.x/width)),Math.max(0,Math.min(1,mouse.y/height))]; }
                        onPressed: function(mouse) { root.strokes = root.strokes.concat([[point(mouse)]]); preview.requestPaint(); }
                        onPositionChanged: function(mouse) { if (pressed) { root.strokes[root.strokes.length-1].push(point(mouse)); preview.requestPaint(); } }
                        onReleased: { root.strokes = root.strokes.slice(); preview.requestPaint(); }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.mode === "draw" && !root.strokes.length
                    text: "Draw your signature here"; color: "#777777"; font.family: Style.font.family; font.pixelSize: Style.font.body
                }
                Button { anchors.centerIn:parent; visible:root.mode==="upload"; text:"Choose PNG / JPEG / WebP"; foreground:"#153355"; enabled:!root.document.busy; onClicked:imagePicker.open() }
            }
            TextField {
                id: typedName
                objectName: "signatureName"
                width: parent.width; visible: root.mode === "type"; enabled: !root.document.busy
                placeholderText: "Type your name"; maximumLength: 100
                onTextChanged: preview.requestPaint()
            }
            Row {
                visible: root.mode === "type"; spacing: Style.space(8)
                Repeater {
                    model: ["Script","Casual","Formal"]
                    delegate: Button {
                        required property string modelData
                        required property int index
                        objectName: "signatureFont-" + index
                        text: modelData; fontFamily: root.families[index]; fontSize: Style.space(26)
                        selected: root.fontIndex === index; enabled:root.fontsReady && !root.document.busy
                        onClicked:root.fontIndex=index
                    }
                }
            }
            Row {
                visible: root.mode !== "upload"; spacing: Style.space(8)
                Repeater {
                    model: ["#1c2a4a","#211d17","#1d4ba3"]
                    delegate: Rectangle {
                        required property string modelData
                        width:Style.space(26); height:width; radius:width/2; color:modelData
                        border.width:root.signatureColor===modelData?3:1; border.color:Color.accent
                        MouseArea { anchors.fill:parent; onClicked:root.signatureColor=parent.modelData }
                    }
                }
                Button { text:"Clear"; visible:root.mode==="draw"; onClicked:{root.strokes=[];preview.requestPaint();} }
            }
            Text { width:parent.width; text:root.document.error || (root.document.busy ? "Preparing signature…" : "Saved signatures stay in this session. Nothing is uploaded."); wrapMode:Text.WordWrap; color:root.document.error?Color.urgent:Color.foreground; font.family:Style.font.family; font.pixelSize:Style.font.bodySmall }
            Row {
                spacing:Style.space(8)
                Button { text:"Cancel"; enabled:!root.document.busy; onClicked:root.dismissed() }
                Button {
                    objectName:"placeSignature"
                    text:"Place signature"; selected:true; visible:root.mode!=="upload"
                    enabled:!root.document.busy && (root.mode==="type" ? root.fontsReady && typedName.text.trim().length>0 : root.strokes.some(function(s){return s.length>1;}))
                    onClicked:root.submitted(preview.toDataURL("image/png"),root.mode==="type"?"Typed":"Drawn")
                }
            }
        }
    }
}
