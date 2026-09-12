import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

ShellRoot {
    property int phase: 0
    onPhaseChanged: console.log("Regression phase " + phase)
    property var focusTarget: null
    property var previousToplevel: null
    property string previousWorkspace: ""
    readonly property string focusWorkspace: "pdfseal-smoke-" + Date.now()
    readonly property string testDir: Quickshell.env("PDFSEAL_TEST_DIR")
    TestEvent { id: input }
    function findItem(item, name) {
        if (item.objectName === name) return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; ++i) {
            var found = findItem(children[i], name);
            if (found) return found;
        }
        return null;
    }
    function control(name) {
        for (var i = 0; i < nativeEditor.data.length; ++i) {
            var item = nativeEditor.data[i];
            if (item.contentItem) {
                var found = findItem(item.contentItem, name);
                if (found) return found;
            }
        }
        throw new Error("Missing control: " + name);
    }
    function click(item, x, y) {
        if (!input.mouseClick(item, x, y, Qt.LeftButton, Qt.NoModifier, 0)) throw new Error("Click failed");
    }
    function typeText(text) {
        for (var i = 0; i < text.length; ++i)
            if (!input.keyClickChar(text[i], Qt.NoModifier, 0)) throw new Error("Typing failed");
    }
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
        repeat: true
        onTriggered: {
            if (!Hyprland.focusedWorkspace) return;
            stop();
            previousToplevel = ToplevelManager.activeToplevel;
            previousWorkspace = Hyprland.focusedWorkspace.name;
            widget.settings = {displayMode: "icon"};
            if (!widget.showIcon || widget.showText) throw new Error("Icon-only display failed");
            widget.settings = {displayMode: "text"};
            if (widget.showIcon || !widget.showText) throw new Error("Text-only display failed");
            testBar.vertical = true;
            if (!widget.showIcon || widget.showText) throw new Error("Vertical bar icon failed");
            testBar.vertical = false;
            widget.settings = {displayMode: "both"};
            if (!widget.showIcon || !widget.showText) throw new Error("Icon and text display failed");
            testBar.barForeground = "#abcdef";
            if (findItem(widget, "pdfsealBarIcon").ink.toString() !== "#abcdef") throw new Error("Bar icon did not follow theme color");
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
                nativeEditor.tool = "text";
                // Real pointer and key events: click first, then type, without a second page click.
                var pageInput = control("pageInput");
                click(pageInput, pageInput.width * 0.1, pageInput.height * 0.3);
                if (!control("inlineTextEditor").activeFocus || nativeEditor.tool !== "select") throw new Error("Page click did not enter inline editing");
                typeText("Signed");
                input.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                if (doc.marks.length !== 2 || doc.marks[1].text !== "Signed") throw new Error("Typing did not place/update text");
                if (Math.abs(doc.marks[1].x - 0.1) > 0.01 || Math.abs(doc.marks[1].y - 0.3) > 0.01) throw new Error("Text position was lost");
                phase=12;
            } else if (phase===12) {
                var pageInput=control("pageInput");
                var oldWidth = doc.marks[1].w;
                click(control("increaseTextSize"), 10, 10);
                if (doc.marks[1].size !== 20 || doc.marks[1].w <= oldWidth) throw new Error("Font size did not update selected text and bounds");
                doc.undo();
                if (doc.marks[1].size !== 18) throw new Error("Font-size undo failed");
                doc.redo();
                if (doc.marks[1].size !== 20 || !doc.dirty) throw new Error("Font-size redo/dirty state failed");
                nativeEditor.tool = "select";
                click(pageInput, pageInput.width * 0.12, pageInput.height * 0.31);
                if (doc.selected !== 1 || !control("editSelectedText").visible) throw new Error("Existing text cannot be edited with Select");
                click(control("decreaseTextSize"), 10, 10);
                if (doc.marks[1].size !== 18) throw new Error("Reselected text size did not update");
                var history = doc.undoStack.length;
                input.mouseDoubleClickSequence(pageInput, pageInput.width * 0.12, pageInput.height * 0.31, Qt.LeftButton, Qt.NoModifier, 0);
                if (!control("inlineTextEditor").activeFocus) throw new Error("Double-click did not focus inline text");
                typeText("Updated text");
                if (doc.marks[1].text !== "Signed") throw new Error("Text draft committed before finishing");
                input.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                if (doc.marks.length !== 2 || doc.marks[1].text !== "Updated text") throw new Error("Text click created a duplicate instead of editing");
                if (doc.undoStack.length !== history + 1) throw new Error("Text edit was not grouped into one undo step");
                doc.undo();
                if (doc.marks[1].text !== "Signed") throw new Error("Text edit undo failed");
                doc.redo();
                click(pageInput, pageInput.width * 0.12, pageInput.height * 0.31);
                click(control("editSelectedText"), 20, 10);
                typeText("Cancel this");
                input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                if (doc.marks[1].text !== "Updated text") throw new Error("Escape changed existing text");
                nativeEditor.changeTextFont("serif");
                if (doc.marks[1].font !== "serif") throw new Error("Font choice did not update selected text");
                nativeEditor.tool = "text";
                click(pageInput, pageInput.width * 0.7, pageInput.height * 0.7);
                input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                if (doc.marks.length !== 2) throw new Error("Empty text placeholder was not discarded");
                nativeEditor.close();
                if (!nativeEditor.opened || !nativeEditor.confirmDiscard) throw new Error("Unsaved changes not protected");
                nativeEditor.confirmDiscard = false;
                click(control("tool-signature"),20,10);
                phase = 7;
            } else if (phase === 7 && control("signatureDialog").fontsReady) {
                click(control("signature-type"),20,10);
                control("signatureName").forceActiveFocus();
                typeText("Jeremie Example");
                click(control("signatureFont-2"),20,10);
                phase = 8;
            } else if (phase === 8) {
                click(control("placeSignature"),20,10);
                phase = 9;
            } else if (phase === 9 && !doc.busy && !nativeEditor.signatureOptions) {
                if (doc.marks.length !== 3 || doc.marks[2].kind !== "image" || doc.savedSignatures.length !== 1) throw new Error("Typed signature was not placed/saved");
                if (doc.savedSignatures[0].width < 500 || doc.savedSignatures[0].width / doc.savedSignatures[0].height < 3) throw new Error("Typed signature capture is cropped");
                var picture=doc.marks[2], oldW=picture.w, oldH=picture.h;
                var target=control("pageInput"), x=(picture.x+picture.w)*target.width, y=(picture.y+picture.h)*target.height;
                input.mousePress(target,x,y,Qt.LeftButton,Qt.NoModifier,0);
                input.mouseMove(target,x+20,y+15,0,Qt.LeftButton,Qt.NoModifier);
                input.mouseRelease(target,x+20,y+15,Qt.LeftButton,Qt.NoModifier,0);
                if (doc.marks[2].w <= oldW || doc.marks[2].h <= oldH) throw new Error("Signature corner resize failed");
                doc.undo();
                if (doc.marks[2].w !== oldW) throw new Error("Resize undo failed");
                doc.redo();
                doc.moveMark(2,0.45-doc.marks[2].x,0.65-doc.marks[2].y);
                click(control("tool-stamp"),20,10);
                phase=10;
            } else if (phase === 10) {
                click(control("stamp-6"),30,30);
                phase=11;
            } else if (phase === 11 && !doc.busy && !nativeEditor.stampOptions) {
                if (doc.marks.length !== 4 || doc.marks[3].kind !== "image") throw new Error("Dated stamp was not placed");
                if (doc.savedSignatures.length !== 1) throw new Error("Stamp polluted signature library");
                doc.moveMark(3,0.1-doc.marks[3].x,0.78-doc.marks[3].y);
                phase=13;
            } else if (phase===13) {
                var target=control("pageInput");
                // Selection returns keyboard focus to the page after using dialogs or text fields.
                click(target,target.width*0.15,target.height*0.8);
                if (doc.selected!==3) throw new Error("Stamp was not selected");
                input.keyClick(Qt.Key_Delete,Qt.NoModifier,0);
                if (doc.marks.length!==3 || doc.selected!==-1) throw new Error("Delete did not remove selected stamp");
                doc.undo();
                if (doc.marks.length!==4) throw new Error("Deleting stamp could not be undone");
                click(target,target.width*0.12,target.height*0.31);
                if (doc.selected!==1) throw new Error("Text was not selected");
                input.keyClick(Qt.Key_Delete,Qt.NoModifier,0);
                if (doc.marks.length!==3 || doc.marks.some(function(m){return m.kind==="text";})) throw new Error("Delete did not remove selected text");
                doc.undo();
                phase=4;
            } else if (phase === 4) {
                focusTarget = Hyprland.toplevels.values.find(function(t) { return t.title === "• input.pdf — PDFSeal"; });
                if (!focusTarget || !focusTarget.wayland) return;
                console.log("Focus target app ID: " + focusTarget.wayland.appId);
                Hyprland.dispatch(Hyprland.usingLua
                    ? 'hl.dsp.window.move({ workspace = "name:' + focusWorkspace + '", window = "address:0x' + focusTarget.address + '", follow = false })'
                    : "movetoworkspacesilent name:" + focusWorkspace + ",address:0x" + focusTarget.address);
                phase = 5;
            } else if (phase === 5 && focusTarget.workspace.name === focusWorkspace && !focusTarget.activated) {
                nativeEditor.open();
                phase = 6;
            } else if (phase === 6 && focusTarget.activated && Hyprland.focusedWorkspace.name === focusWorkspace) {
                if (!doc.ready || doc.marks.length !== 4 || doc.marks[1].text !== "Updated text" || !doc.dirty)
                    throw new Error("Workspace activation lost document edits");
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
                Hyprland.dispatch(Hyprland.usingLua
                    ? 'hl.dsp.focus({ workspace = ' + JSON.stringify("name:" + previousWorkspace) + ' })'
                    : "workspace name:" + previousWorkspace);
                if (previousToplevel) previousToplevel.activate();
                console.log("PASS: PDFSeal widget, icon/text modes, live theme bindings, inline text/fonts, typed signature, dated stamp, selection/Delete/undo, resize/undo, cross-workspace activation, unsaved guard, export and worker shutdown");
                Qt.quit();
            }
        }
    }
}
