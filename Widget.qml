import QtQuick
import qs.Ui

BarWidget {
    id: root
    moduleName: "arkane.pdfseal"
    readonly property bool opened: editor.item ? editor.item.opened : false
    // The idle bar widget has no editor and no PDF worker.
    function open() {
        editor.active = true;
        if (editor.item) editor.item.open();
    }
    function close() { if (editor.item) editor.item.close(); }
    function toggle() { if (opened) close(); else open(); }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.vertical || !root.setting("showLabel", true) ? "PDF" : "PDFSeal"
        tooltipText: "PDFSeal · Native PDF signing and annotation"
        active: root.opened
        Accessible.name: "PDFSeal"
        onPressed: function(buttonCode) { if (buttonCode === Qt.LeftButton) root.open(); }
    }
    Loader {
        id: editor
        active: false
        source: Qt.resolvedUrl("Editor.qml")
        onLoaded: item.open()
    }
}
