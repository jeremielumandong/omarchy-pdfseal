import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

ShellRoot {
    property int colorHistory: 0
    property var touches: null
    property var pinchCenter: null
    property int phase: 0
    property bool checking:false
    property bool readerFitted:false
    property real previousZoom:1
    onPhaseChanged: console.log("Regression phase " + phase)
    property var focusTarget: null
    property var previousToplevel: null
    property string previousWorkspace: ""
    readonly property string focusWorkspace: "pdfseal-smoke-" + Date.now()
    readonly property string testDir: Quickshell.env("PDFSEAL_TEST_DIR")
    property var input: null
    Component {id:eventFactory;TestEvent {}}
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
        if(item.Window && item.Window.window)item.Window.window.requestActivate();
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
        property var activePopout: null
        function requestPopout(owner) { activePopout=owner; }
        function releasePopout(owner) { activePopout=null; }
        function hideTooltip(item) {}
        function showTooltip(item, text) {}
    }
    PanelWindow {
        visible: true
        implicitWidth: 160
        implicitHeight: 40
        Widget { id: widget; bar: testBar; function persistDisplay(mode) { settings={displayMode:mode}; } }
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
            nativeEditor.openedPdf(testDir + "/input.pdf");
            check.start();
        }
    }
    Timer {
        id: check
        interval: 100
        repeat: true
        onTriggered: {
            if(checking)return;checking=true;
            try {
            var doc = nativeEditor.document;
            if (doc.error) throw new Error(doc.error);
            if (phase === 0 && doc.preview && doc.operation === "") {
                if(!readerFitted){var reader=control("pdfViewport");reader.zoomAt(Math.max(0.5,Math.min(1,(reader.height-40)/reader.layouts[0].height)),reader.width/2,0);reader.contentY=0;readerFitted=true;return;}
                if (nativeEditor.themeBackground.toString() !== "#112233" || nativeEditor.themeForeground.toString() !== "#ddeeff")
                    throw new Error("Theme did not propagate");
                if (nativeEditor.openOptions) throw new Error("Plain PDF showed a password prompt");
                if (doc.pages.length !== 2) throw new Error("PDF did not load");
                doc.addMark({kind:"ink",color:"#153355",size:2,points:[[0.1,0.5],[0.3,0.4],[0.5,0.6]]});
                nativeEditor.tool = "text";
                // Real pointer and key events: click first, then type, without a second page click.
                var pageInput = control("pageInput");
                if(!input)input=eventFactory.createObject(pageInput.Window.window.contentItem);
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
                phase=23;
            } else if (phase===23) {
                var target=control("pageInput");
                click(target,target.width*0.12,target.height*0.31);
                click(control("openColorPicker"),20,10);
                phase=24;
            } else if (phase===24) {
                var picker=control("colorPicker"), hue=control("colorHue"), shade=control("colorShade");
                click(hue,10,hue.height/3);
                input.mousePress(shade,shade.width*0.2,shade.height*0.2,Qt.LeftButton,Qt.NoModifier,0);
                input.mouseMove(shade,shade.width*0.75,shade.height*0.25,0,Qt.LeftButton,Qt.NoModifier);
                input.mouseRelease(shade,shade.width*0.75,shade.height*0.25,Qt.LeftButton,Qt.NoModifier,0);
                if (Math.abs(picker.saturation-0.75)>0.03 || Math.abs(picker.value-0.75)>0.03) throw new Error("Dragging color selector failed");
                var panel=control("colorPickerPanel"), oldX=panel.x, drag=control("colorPickerDrag");
                input.mousePress(drag,25,10,Qt.LeftButton,Qt.NoModifier,0);
                input.mouseMove(drag,55,30,0,Qt.LeftButton,Qt.NoModifier);
                input.mouseMove(drag,70,35,0,Qt.LeftButton,Qt.NoModifier);
                input.mouseRelease(drag,70,35,Qt.LeftButton,Qt.NoModifier,0);
                if (panel.x<=oldX) throw new Error("Color picker could not be moved");
                colorHistory=doc.undoStack.length;
                click(control("applyColor"),20,10);
                if (doc.marks[1].color!==picker.hexColor || doc.undoStack.length!==colorHistory+1) throw new Error("Color did not apply to selected text as one edit");
                phase=25;
            } else if (phase===25) {
                click(control("openColorPicker"),20,10);
                phase=26;
            } else if (phase===26) {
                click(control("colorEyedropper"),20,10);
                if (nativeEditor.tool!=="eyedropper" || nativeEditor.colorOptions) throw new Error("Eyedropper did not activate");
                var target=control("pageInput");
                click(target,target.width*0.8,target.height*0.45);
                phase=27;
            } else if (phase===27 && nativeEditor.tool!=="eyedropper") {
                if (nativeEditor.ink!=="#336699" || doc.marks[1].color!=="#336699") {Qt.quit(); throw new Error("Eyedropper did not match the PDF color: "+nativeEditor.ink); }
                if (doc.marks.length!==4) throw new Error("Eyedropper added an annotation");
                phase=14;
            } else if (phase===14) {
                var viewport=control("pdfViewport");
                previousZoom=doc.zoom;
                input.mouseWheel(viewport,viewport.width/2,viewport.height/2,Qt.NoButton,Qt.ControlModifier,0,120,0);
                if (doc.zoom<=previousZoom) throw new Error("Ctrl-wheel did not zoom PDF");
                viewport.zoomAt(1,viewport.width/2,viewport.height/2);
                // Use a known blank area. On narrow windows the viewport's
                // center can land on the ink object, which owns object drags.
                var page=control("pageInput");
                pinchCenter=page.mapToItem(viewport,page.width*0.65,page.height*0.2);
                touches=input.touchEvent(viewport);
                touches.press(0,viewport,pinchCenter.x-30,pinchCenter.y);
                touches.press(1,viewport,pinchCenter.x+30,pinchCenter.y);
                touches.commit();
                phase=15;
            } else if (phase===15 || phase===16) {
                var viewport=control("pdfViewport");
                var distance=phase===15 ? 60 : 100;
                touches.move(0,viewport,pinchCenter.x-distance,pinchCenter.y);
                touches.move(1,viewport,pinchCenter.x+distance,pinchCenter.y);
                touches.commit();
                phase++;
            } else if (phase===17) {
                if (doc.zoom<=1.1) throw new Error("Pinch did not zoom PDF: zoom="+doc.zoom);
                var viewport=control("pdfViewport");
                touches.release(0,viewport,pinchCenter.x-100,pinchCenter.y);
                touches.release(1,viewport,pinchCenter.x+100,pinchCenter.y);
                touches.commit();
                viewport.zoomAt(1,viewport.width/2,viewport.height/2);
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
                                nativeEditor.openedPdf(testDir+"/encrypted.pdf");
                                phase = 18;
                            });
                            phase = 3;
                            return;
                        }
                    }
                }
                nativeEditor.openedPdf(testDir+"/encrypted.pdf");
                phase=18;
            } else if (phase===18 && nativeEditor.openOptions) {
                if (!doc.loaded || doc.fileName!=="input.pdf") throw new Error("Password prompt discarded open PDF");
                nativeEditor.openOptions=false;
                doc.openDocument(testDir+"/encrypted.pdf","test-password");
                phase=19;
            } else if (phase===19 && doc.fileName==="encrypted.pdf" && doc.operation==="") {
                if (nativeEditor.openOptions) throw new Error("Password prompt remained after correct password");
                nativeEditor.tool="note";
                var target=control("pageInput");click(target,target.width*0.2,target.height*0.5);
                phase=29;
            } else if (phase===29) {
                typeText("Review this clause");click(control("saveNote"),20,10);
                if(doc.marks.length!==1 || doc.marks[0].kind!=="note") throw new Error("Comment was not saved");
                click(control("tool-editText"),20,10);
                phase=30;
            } else if (phase===30 && !doc.busy && doc.textPage===doc.page.number) {
                var line=doc.textLines.find(function(line){return line.text.indexOf("Draw a signature")>=0;});
                if(!line) throw new Error("Existing PDF text was not detected");
                var target=control("pageInput");click(target,(line.x+line.w/2)*target.width,(line.y+line.h/2)*target.height);
                typeText("Replacement line");input.keyClick(Qt.Key_Return,Qt.NoModifier,0);
                if(doc.marks.length!==3 || doc.marks[2].text!=="Replacement line") throw new Error("Existing PDF text replacement failed");
                click(control("openDocumentTools"),20,10);
                phase=31;
            } else if (phase===31) {
                click(control("operation-duplicate"),20,10);
                click(control("applyDocumentTool"),20,10);
                phase=32;
            } else if (phase===32 && !doc.busy && doc.pages.length===3) {
                if(doc.marks.length || doc.undoStack.length || !doc.dirty) throw new Error("Document operation state was not updated");
                doc.search("Replacement line");
                phase=33;
            } else if (phase===33 && !doc.busy && doc.searchHits.length===2) {
                doc.exportDocument(testDir+"/tools.pdf",false,"");
                phase=34;
            } else if (phase===34 && doc.status.startsWith("Saved ")) {
                nativeEditor.openedPdf(testDir+"/forms.pdf");readerFitted=false;phase=35;
            } else if (phase===35 && doc.fileName==="forms.pdf" && doc.preview && !doc.busy) {
                if(!readerFitted){var reader=control("pdfViewport");reader.zoomAt(Math.max(0.5,Math.min(1,doc.zoom*(reader.height-40)/reader.layouts[0].height)),reader.width/2,0);reader.contentY=0;readerFitted=true;return;}
                if(doc.formFields.length!==6) throw new Error("Form widgets not detected");
                var field=control("formText-FullName");click(field,20,10);input.keyClick(Qt.Key_A,Qt.ControlModifier,0);typeText("Grace Hopper");input.keyClick(Qt.Key_Return,Qt.NoModifier,0);
                if(doc.formValues.FullName!=="Grace Hopper" || doc.undoStack.length!==1) throw new Error("Form typing was not one undoable edit");
                var check=doc.formFields.find(function(f){return f.name==="Agree";});click(control("form-Agree-"+check.id),5,5);
                var radio=doc.formFields.find(function(f){return f.name==="Choice" && f.onValue==="Two";});click(control("form-Choice-"+radio.id),5,5);
                click(control("formSelect-Select"),20,10);input.keyClick(Qt.Key_End,Qt.NoModifier,0);input.keyClick(Qt.Key_Return,Qt.NoModifier,0);
                phase=36;
            } else if (phase===36) {
                if(doc.formValues.Agree!=="" || doc.formValues.Choice!=="Two" || doc.formValues.Select!=="Beta") throw new Error("Form choices did not update");
                doc.exportDocument(testDir+"/filled-form.pdf",false,"");phase=37;
            } else if (phase===37 && doc.status.startsWith("Saved ")) {
                click(control("openSigning"),20,10);phase=47;
            } else if(phase===47){
                var recipient=control("recipientName");click(recipient,20,10);typeText("Ada Test");
                if(recipient.text!=="Ada Test")throw new Error("Recipient typing failed: value="+recipient.text+" focus="+recipient.activeFocus+" visible="+recipient.visible+" enabled="+recipient.enabled+" mode="+doc.signing.mode+" x="+recipient.x+" y="+recipient.y+" tools="+nativeEditor.toolsOptions+" form="+doc.formValues.Select);
                click(control("addRecipient"),20,10);
                click(control("fieldType-name"),20,10);phase=44;
            } else if(phase===44){
                var placement=control("signingPageInput");input.mousePress(placement,placement.width*0.3,placement.height*0.25,Qt.LeftButton,Qt.NoModifier,0);input.mouseMove(placement,placement.width*0.7,placement.height*0.31,10,Qt.LeftButton,Qt.NoModifier);input.mouseRelease(placement,placement.width*0.7,placement.height*0.31,Qt.LeftButton,Qt.NoModifier,0);
                if(doc.signing.fields.length!==1 || doc.signing.recipients.length!==1)throw new Error("Signing field placement failed: "+doc.signing.fields.length+" fields, "+doc.signing.recipients.length+" recipients, mode="+doc.signing.mode+", tool="+nativeEditor.tool+", size="+placement.width+"x"+placement.height);
                phase=45;
            } else if(phase===45){
                var placed=doc.signing.fields[0];var box=control("signingField-"+placed.id);
                input.mousePress(box,10,10,Qt.LeftButton,Qt.NoModifier,0);input.mouseMove(box,30,25,0,Qt.LeftButton,Qt.NoModifier);input.mouseRelease(box,30,25,Qt.LeftButton,Qt.NoModifier,0);
                if(doc.signing.fields[0].xN<=placed.xN)throw new Error("Signing field did not move");
                doc.undo();phase=46;
            } else if(phase===46){
                var box=control("signingField-"+doc.signing.fields[0].id);click(box,10,10);input.keyClick(Qt.Key_Delete,Qt.NoModifier,0);
                if(doc.signing.fields.length)throw new Error("Selected signing field was not deleted");
                doc.undo();
                doc.signing.addRecipient("Second Test");doc.signing.addField(0.3,0.36,0.4,0.06);
                if(doc.signing.canSign(doc.signing.activeRecipient))throw new Error("Signing order did not gate later recipient");
                doc.signing.mode="sign";doc.signing.requestFill(doc.signing.fields[0].id);phase=38;
            } else if (phase===38 && nativeEditor.fieldOptions) {
                var value=control("signingFieldValue");click(value,20,10);input.keyClick(Qt.Key_A,Qt.ControlModifier,0);typeText("Ada Signed");click(control("saveSigningField"),20,10);
                if(doc.formValues.Select!=="Beta" || doc.signing.recipients[0].name!=="Ada Test")throw new Error("Signing preparation changed form data or recipient name");
                if(doc.signing.audit.length!==1 || !doc.signing.canSign(doc.signing.recipients[1].id))throw new Error("Signing value or order failed");
                doc.exportDocument(testDir+"/handoff.pdf",false,"");phase=39;
            } else if(phase===39 && doc.status.startsWith("Saved ")){nativeEditor.openedPdf(testDir+"/handoff.pdf");phase=40;
            } else if(phase===40 && doc.fileName==="handoff.pdf" && doc.preview && !doc.busy){
                if(doc.signing.fields.length!==2 || doc.signing.fields[0].value.text!=="Ada Signed" || doc.signing.audit.length!==1 || doc.signing.mode!=="sign")throw new Error("Offline signing package did not resume");
                doc.signing.nextField();phase=41;
            } else if(phase===41 && nativeEditor.fieldOptions){
                click(control("saveSigningField"),20,10);
                if(!doc.signing.complete || doc.signing.audit.length!==2)throw new Error("Guided signing did not complete");
                nativeEditor.finalizeOptions=true;phase=42;
            } else if(phase===42){
                var signer=control("sealSigner");click(signer,20,10);typeText("PDFSeal UI Test");
                if(!control("saveSealedPdf").enabled)throw new Error("Finalize dialog not ready");
                nativeEditor.finalizeOptions=false;
                var capture=Quickshell.env("PDFSEAL_CAPTURE");
                if(capture){for(var i=0;i<nativeEditor.data.length;i++){var window=nativeEditor.data[i];if(window.contentItem && window.title!==undefined && String(window.title).endsWith("PDFSeal")){window.contentItem.children[0].grabToImage(function(result){result.saveToFile(capture+".signing.png");});break;}}}
                doc.exportDocument(testDir+"/sealed-workflow.pdf",true,"",{finalize:true,certificate:true,seal:{name:"PDFSeal UI Test",reason:"UI verification"}});phase=43;
            } else if(phase===43 && doc.status.startsWith("Saved ")){nativeEditor.close();phase=2;
            } else if (phase === 2 && !doc.ready && !doc.loaded) {
                input.mouseClick(widget,widget.width/2,widget.height/2,Qt.RightButton,Qt.NoModifier,0);
                phase=20;
            } else if (phase===20 || phase===21) {
                var menu=null;
                for (var i=0;i<widget.data.length;i++) if (widget.data[i].objectName==="pdfsealDisplayMenu") menu=widget.data[i];
                if (!menu || !menu.open) throw new Error("Right-click did not open display menu");
                var mode=phase===20 ? "icon" : "text";
                var choice=findItem(menu.contentItem[0],"display-"+mode);
                if (!choice) throw new Error("Missing display menu choice");
                click(choice,20,10);
                if (widget.displayMode!==mode || menu.open) throw new Error("Display menu selection did not apply");
                if (phase===20) {widget.toggleDisplayMenu();phase=21;return;}
                phase=22;
            } else if (phase===22) {
                Hyprland.dispatch(Hyprland.usingLua
                    ? 'hl.dsp.focus({ workspace = ' + JSON.stringify("name:" + previousWorkspace) + ' })'
                    : "workspace name:" + previousWorkspace);
                if (previousToplevel) previousToplevel.activate();
                console.log("PASS: PDFSeal widget, explicit icon/text menu, live theme bindings, inline text/fonts, typed signature, dated stamp, selection/Delete/undo, draggable color picker/PDF eyedropper, pinch/wheel zoom, password-only-when-required, comments, PDF text replacement, page duplication, search, interactive form text/checkbox/radio/dropdown, recipient order, field placement, offline handoff, guided fill and digital seal, resize/undo, cross-workspace activation, unsaved guard, export and worker shutdown");
                Qt.quit();
            }
            } catch(error) {console.error("FAIL phase "+phase+": "+error);stop();for(var i=0;i<nativeEditor.data.length;i++){var window=nativeEditor.data[i];if(window.contentItem && window.title!==undefined && String(window.title).endsWith("PDFSeal")){window.contentItem.children[0].grabToImage(function(result){result.saveToFile("/tmp/pdfseal-ui-failure.png");Qt.quit();});return;}}Qt.quit();} finally {checking=false;}
        }
    }
}
