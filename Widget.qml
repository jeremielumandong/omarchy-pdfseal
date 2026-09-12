import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "arkane.pdfseal"
    readonly property bool opened: editor.item ? editor.item.opened : false
    readonly property string displayMode: setting("displayMode", setting("showLabel", true) ? "both" : "icon")
    readonly property bool showIcon: vertical || displayMode !== "text"
    readonly property bool showText: !vertical && displayMode !== "icon"
    // The idle bar widget has no editor and no PDF worker.
    function open() {
        editor.active = true;
        if (editor.item) editor.item.open();
    }
    function close() { if (editor.item) editor.item.close(); }
    function toggle() { if (opened) close(); else open(); }
    function cycleDisplay() {
        var next = displayMode === "both" ? "icon" : displayMode === "icon" ? "text" : "both";
        Quickshell.execDetached(["omarchy", "bar", "set", moduleName, "displayMode", next]);
    }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "PDFSeal"
        labelVisible: false
        fixedWidth: root.vertical ? root.barSize : content.implicitWidth + scaledHorizontalMargin * 2
        fixedHeight: root.vertical ? icon.height + scaledVerticalPadding * 2 : root.barSize
        tooltipText: "PDFSeal · Click to open · Right-click to switch icon / text"
        active: root.opened
        Accessible.name: "PDFSeal"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.open();
            else if (buttonCode === Qt.RightButton) root.cycleDisplay();
        }
        Row {
            id: content
            anchors.centerIn: parent
            spacing: Style.space(6)
            Canvas {
                id: icon
                objectName: "pdfsealBarIcon"
                visible: root.showIcon
                width: Style.space(20)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                property color ink: button.active && button.useActiveColor ? button.activeColor : button.foreground
                onInkChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.scale(width / 24, height / 24);
                    ctx.strokeStyle = ink;
                    ctx.lineWidth = 1.6;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.moveTo(5, 2); ctx.lineTo(14, 2); ctx.lineTo(20, 8);
                    ctx.lineTo(20, 22); ctx.lineTo(5, 22); ctx.closePath();
                    ctx.moveTo(14, 2); ctx.lineTo(14, 8); ctx.lineTo(20, 8);
                    ctx.moveTo(8, 18);
                    ctx.bezierCurveTo(13, 7, 15, 12, 11, 17);
                    ctx.bezierCurveTo(8, 21, 14, 14, 15, 17);
                    ctx.bezierCurveTo(16, 19, 17, 16, 18, 16);
                    ctx.stroke();
                }
            }
            Text {
                visible: root.showText
                anchors.verticalCenter: parent.verticalCenter
                text: "PDFSeal"
                textFormat: Text.PlainText
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                color: icon.ink
                renderType: Text.NativeRendering
            }
        }
    }
    Loader {
        id: editor
        active: false
        source: Qt.resolvedUrl("Editor.qml")
        onLoaded: item.open()
    }
}
