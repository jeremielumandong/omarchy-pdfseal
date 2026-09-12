import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
    property int phase: 0
    readonly property string testDir: Quickshell.env("PDFSEAL_TEST_DIR")
    QtObject {
        id: testBar
        property string position: "top"
        property bool vertical: false
        property int barSize: 30
        property bool foregroundAnimationEnabled: false
        property string fontFamily: "monospace"
        property color barForeground: "white"
        property color urgent: "red"
        function hideTooltip(item) {}
        function showTooltip(item, text) {}
    }
    PanelWindow {
        visible: true
        implicitWidth: 160
        implicitHeight: 40
        Widget { id: widget; bar: testBar }
    }
    Editor { id: nativeEditor }
    Timer {
        interval: 500
        running: true
        onTriggered: {
            widget.open();
            if (!widget.opened) throw new Error("Widget open failed");
            widget.close();
            if (widget.opened) throw new Error("Widget close failed");
            nativeEditor.open();
            Color.background = "#112233";
            Color.foreground = "#ddeeff";
            nativeEditor.document.openDocument(testDir + "/input.pdf", "");
            check.start();
        }
    }
    Timer {
        id: check
        interval: 100
        repeat: true
        onTriggered: {
            var doc = nativeEditor.document;
            if (doc.error) throw new Error(doc.error);
            if (phase === 0 && doc.preview && doc.operation === "") {
                if (nativeEditor.themeBackground.toString() !== "#112233" || nativeEditor.themeForeground.toString() !== "#ddeeff")
                    throw new Error("Theme did not propagate");
                if (doc.pages.length !== 2) throw new Error("PDF did not load");
                doc.addMark({kind:"ink",color:"#153355",size:2,points:[[0.1,0.5],[0.3,0.4],[0.5,0.6]]});
                doc.addMark({kind:"text",color:"#153355",size:18,x:0.1,y:0.3,w:0.4,h:0.1,text:"Signed from native QML"});
                doc.undo();
                if (doc.marks.length !== 1) throw new Error("Undo failed");
                doc.redo();
                if (doc.marks.length !== 2 || !doc.dirty) throw new Error("Redo/dirty state failed");
                nativeEditor.close();
                if (!nativeEditor.opened || !nativeEditor.confirmDiscard) throw new Error("Unsaved changes not protected");
                nativeEditor.confirmDiscard = false;
                doc.exportDocument(testDir + "/signed.pdf", true, "");
                phase = 1;
            } else if (phase === 1 && doc.status.startsWith("Saved ")) {
                if (doc.dirty) throw new Error("Save did not clear dirty state");
                var capturePath = Quickshell.env("PDFSEAL_CAPTURE");
                if (capturePath) {
                    for (var i = 0; i < nativeEditor.data.length; i++) {
                        var item = nativeEditor.data[i];
                        if (item.contentItem && item.title !== undefined && String(item.title).endsWith("PDFSeal")) {
                            item.contentItem.children[0].grabToImage(function(result) {
                                result.saveToFile(capturePath);
                                nativeEditor.close();
                                phase = 2;
                            });
                            phase = 3;
                            return;
                        }
                    }
                }
                nativeEditor.close();
                phase = 2;
            } else if (phase === 2 && !doc.ready && !doc.loaded) {
                console.log("PASS: PDFSeal widget, live theme bindings, native PDF preview, undo/redo, unsaved guard, export and worker shutdown");
                Qt.quit();
            }
        }
    }
}
