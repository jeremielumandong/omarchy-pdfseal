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
        displayMenu.open = false;
        editor.active = true;
        if (editor.item) editor.item.open();
    }
    function close() { if (editor.item) editor.item.close(); }
    function toggle() { if (opened) close(); else open(); }
    function persistDisplay(mode) {
        Quickshell.execDetached(["omarchy", "bar", "set", moduleName, "displayMode", mode]);
    }
    function setDisplayMode(mode) {
        if (mode !== "both" && mode !== "icon" && mode !== "text") return;
        displayMenu.open = false;
        persistDisplay(mode);
    }
    function toggleText() { setDisplayMode(displayMode === "icon" ? "both" : "icon"); }
    function toggleDisplayMenu() { displayMenu.open = !displayMenu.open; }
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
        tooltipText: "PDFSeal · Click to open · Right-click to show or hide text"
        active: root.opened
        Accessible.name: "PDFSeal"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.open();
            else if (buttonCode === Qt.RightButton) root.toggleDisplayMenu();
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
    PopupCard {
        id: displayMenu
        objectName: "pdfsealDisplayMenu"
        anchorItem: button
        bar: root.bar
        contentWidth: Style.space(210)
        contentHeight: fittedContentHeight(menuItems.implicitHeight)
        Column {
            id: menuItems
            width: parent.width
            spacing: Style.space(6)
            Button {
                objectName:"display-label"
                width:parent.width
                text:root.displayMode==="icon" ? "Show text" : "Hide text"
                tooltipText:root.vertical ? "Vertical bars always use the icon." : "Show or hide the PDFSeal label beside its icon."
                enabled:!root.vertical
                onClicked:root.toggleText()
            }
            Button { objectName:"display-text"; width:parent.width; text:"Text only"; selected:root.displayMode==="text"; onClicked:root.setDisplayMode("text") }
        }
    }
    Loader {
        id: editor
        active: false
        source: Qt.resolvedUrl("Editor.qml")
        onLoaded: item.open()
    }
}
