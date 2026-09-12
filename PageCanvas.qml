import QtQuick
import qs.Commons

Item {
    id: root
    required property var document
    property string tool: "ink"
    property string inkColor: "#153355"
    property real strokeSize: 2
    property real textSize: 18
    property string textFont: "sans"
    property string previewInk: ""
    signal colorPicked(string color)
    signal colorPickCancelled()
    property var textDraft: null
    readonly property bool textEditing: textDraft !== null
    readonly property bool textDraftDirty: textDraft !== null && inlineText.text.trim() !== textDraft.original
    property var draft: null
    property real dragX: 0
    property real dragY: 0
    property bool resizing: false
    readonly property real unit: document.page ? width / document.page.width : 1
    readonly property bool available: document.preview !== "" && !document.busy
    signal textEditingStarted()
    signal existingTextEditingStarted(real size)
    signal noteRequested(int index,real x,real y)
    Keys.onPressed: function(event) {
        if (tool === "eyedropper" && event.key === Qt.Key_Escape) {
            colorPickCancelled(); event.accepted=true; return;
        }
        if (!textEditing && available && document.selected >= 0 &&
                (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
            document.removeMark();
            event.accepted = true;
        }
    }

    function fontFamily(font) {
        return font === "serif" ? "Nimbus Roman" : font === "mono" ? "Nimbus Mono PS" : "Nimbus Sans";
    }
    function beginText(index, x, y) {
        if (!available) return;
        finishText(true);
        var mark = index >= 0 ? document.marks[index] : null;
        if (mark && mark.kind !== "text") return;
        document.selected = index;
        textDraft = {index: index, x: mark ? mark.x : x, y: mark ? mark.y : y, original: mark ? mark.text : ""};
        inlineText.text = mark ? mark.text : "";
        textEditingStarted();
        inlineText.forceActiveFocus();
        inlineText.selectAll();
    }
    function beginOriginal(line) {
        if (!available) return;
        finishText(true);
        document.selected=-1;
        line=Object.assign({},line,{textY:Math.max(0,line.y-line.size*0.282/document.page.height)});
        textDraft={index:-1,x:line.x,y:line.textY,original:line.text,sourceLine:line};
        inlineText.text=line.text;
        existingTextEditingStarted(line.size);
        textEditingStarted();
        inlineText.forceActiveFocus();inlineText.selectAll();
    }
    function finishText(save) {
        if (!textDraft) return;
        var draft = textDraft;
        var value = inlineText.text.trim();
        textDraft = null;
        if (!save || document.busy || !document.page) return;
        if (draft.sourceLine) {document.replaceText(draft.sourceLine,value,textSize,inkColor,textFont);return;}
        if (draft.index < 0) {
            if (value) document.addMark(document.textMark(draft.x, draft.y, value, textSize, inkColor, textFont));
        } else if (!value) {
            document.selected = draft.index;
            document.removeMark();
        } else document.updateText(draft.index, value, textSize, textFont, inkColor);
    }

    function bounds(mark) {
        if (mark.kind !== "ink") return {x: mark.x, y: mark.y, w: mark.w || 0.15, h: mark.h || 0.04};
        var xs = mark.points.map(function(p) { return p[0]; });
        var ys = mark.points.map(function(p) { return p[1]; });
        var x = Math.min.apply(null, xs), y = Math.min.apply(null, ys);
        return {x: x, y: y, w: Math.max.apply(null, xs) - x, h: Math.max.apply(null, ys) - y};
    }
    function hit(x, y) {
        for (var i = document.marks.length - 1; i >= 0; --i) {
            var mark = document.marks[i];
            if (mark.page !== document.page.number || mark.kind==="cover") continue;
            var box = bounds(mark);
            if (x >= box.x - 0.01 && x <= box.x + box.w + 0.01 && y >= box.y - 0.01 && y <= box.y + box.h + 0.01) return i;
        }
        return -1;
    }
    function paintMark(ctx, mark, selected) {
        if (selected && previewInk && mark.kind === "text") mark=Object.assign({},mark,{color:previewInk});
        if (selected && root.resizing) mark = Object.assign({}, mark, {
            w:Math.max(0.01,Math.min(1-mark.x,mark.w+root.dragX)),
            h:Math.max(0.01,Math.min(1-mark.y,mark.h+root.dragY))});
        ctx.save();
        if (selected && !root.resizing) ctx.translate(root.dragX * width, root.dragY * height);
        ctx.strokeStyle = mark.color;
        ctx.fillStyle = mark.color;
        ctx.lineWidth = mark.size * unit;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        if (mark.kind === "image") {
            if (canvas.isImageLoaded(mark.dataUrl)) ctx.drawImage(mark.dataUrl, mark.x * width, mark.y * height, mark.w * width, mark.h * height);
            else canvas.loadImage(mark.dataUrl);
        } else if (mark.kind === "ink") {
            ctx.beginPath();
            for (var i = 0; i < mark.points.length; ++i) {
                var point = mark.points[i];
                if (i === 0) ctx.moveTo(point[0] * width, point[1] * height);
                else ctx.lineTo(point[0] * width, point[1] * height);
            }
            ctx.stroke();
        } else if (mark.kind === "text") {
            ctx.font = (mark.size * unit) + "px '" + fontFamily(mark.font) + "'";
            ctx.textBaseline = "alphabetic";
            mark.text.split("\n").forEach(function(line, i) {
                ctx.fillText(line, mark.x * width, mark.y * height + mark.size * unit * (1 + i * 1.2));
            });
        } else if (mark.kind === "note") {
            ctx.fillRect(mark.x*width,mark.y*height,18*unit,18*unit);
            ctx.fillStyle="#211d17";ctx.font=(14*unit)+"px sans-serif";ctx.fillText("…",mark.x*width+2*unit,mark.y*height+12*unit);
        } else if (mark.kind === "cover" || mark.kind === "redact") {
            ctx.fillStyle=mark.kind==="cover" ? "#ffffff" : "#000000";
            ctx.fillRect(mark.x*width,mark.y*height,mark.w*width,mark.h*height);
        } else if (mark.kind === "highlight") {
            ctx.globalAlpha = 0.3;
            ctx.globalCompositeOperation = "multiply";
            ctx.fillRect(mark.x * width, mark.y * height, mark.w * width, mark.h * height);
        } else ctx.strokeRect(mark.x * width, mark.y * height, mark.w * width, mark.h * height);
        ctx.restore();
        if (selected && (root.tool === "select" || (root.tool === "text" && mark.kind === "text"))) {
            var b = bounds(mark);
            ctx.save();
            ctx.strokeStyle = "#4279c2";
            ctx.lineWidth = 1.5;
            var dx = root.resizing ? 0 : root.dragX, dy = root.resizing ? 0 : root.dragY;
            ctx.strokeRect((b.x + dx) * width - 4, (b.y + dy) * height - 4, b.w * width + 8, b.h * height + 8);
            if (["image","box","highlight","redact"].indexOf(mark.kind) >= 0) {
                ctx.fillStyle = "#4279c2";
                ctx.fillRect((b.x+dx+b.w)*width-4,(b.y+dy+b.h)*height-4,8,8);
            }
            ctx.restore();
        }
    }

    Rectangle { anchors.fill: parent; color: "white" }
    Image {
        anchors.fill: parent
        source: root.document.preview
        asynchronous: true
        cache: false
        fillMode: Image.Stretch
    }
    Canvas {
        id: canvas
        anchors.fill: parent
        onImageLoaded: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!root.document.page) return;
            if (root.tool==="editText" && root.document.textPage===root.document.page.number) {
                ctx.strokeStyle="#4279c2";ctx.lineWidth=1;ctx.globalAlpha=0.4;
                root.document.textLines.forEach(function(line){ctx.strokeRect(line.x*root.width,line.y*root.height,line.w*root.width,line.h*root.height);});
                ctx.globalAlpha=1;
            }
            var hit=root.document.searchIndex>=0 ? root.document.searchHits[root.document.searchIndex] : null;
            if (hit && hit.page===root.document.page.number) {
                ctx.fillStyle="#ffcc00";ctx.globalAlpha=0.35;ctx.fillRect(hit.x*root.width,hit.y*root.height,hit.w*root.width,hit.h*root.height);ctx.globalAlpha=1;
            }
            root.document.marks.forEach(function(mark, index) {
                if (root.textDraft && root.textDraft.index === index) return;
                if (mark.page === root.document.page.number && mark.kind!=="redact") root.paintMark(ctx, mark, index === root.document.selected);
            });
            if (root.textDraft && root.textDraft.sourceLine) {
                var line=root.textDraft.sourceLine;ctx.fillStyle="white";
                ctx.fillRect(line.x*root.width-1,line.y*root.height-1,line.w*root.width+2,line.h*root.height+2);
            }
            // Redaction regions remain visibly opaque even after adding other marks.
            root.document.marks.forEach(function(mark,index){if(mark.kind==="redact" && mark.page===root.document.page.number)root.paintMark(ctx,mark,index===root.document.selected);});
            if (root.draft) root.paintMark(ctx, root.draft, false);

        }
    }
    Connections {
        target: root.document
        function onColorSampled(color) {root.colorPicked(color);}
        function onTextLinesChanged(){canvas.requestPaint();}
        function onSearchIndexChanged(){canvas.requestPaint();}
        function onMarksChanged() { canvas.requestPaint(); }
        function onPageChanged() { root.finishText(false); root.draft = null; canvas.requestPaint(); }
        function onSelectedChanged() { canvas.requestPaint(); }
    }
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onToolChanged: { if (tool==="editText") document.ensureText(); if (tool !== "select") finishText(true); canvas.requestPaint(); }
    onPreviewInkChanged: canvas.requestPaint()
    onDraftChanged: canvas.requestPaint()
    onTextDraftChanged: canvas.requestPaint()
    MouseArea {
        objectName: "pageInput"
        anchors.fill: parent
        enabled: root.available && root.tool!=="signing"
        cursorShape: root.tool === "select" ? Qt.ArrowCursor : Qt.CrossCursor
        property real startX: 0
        property real startY: 0
        function position(mouse) { return [Math.max(0, Math.min(1, mouse.x / width)), Math.max(0, Math.min(1, mouse.y / height))]; }
        onPressed: function(mouse) {
            root.finishText(true);
            root.forceActiveFocus();
            var p = position(mouse);
            startX = p[0]; startY = p[1];
            if (root.tool === "eyedropper") {
                root.document.sampleColor(p[0],p[1]);return;
            }
            if (root.tool === "select") {
                var selected = root.document.selectedMark;
                root.resizing = selected && ["image","box","highlight","redact"].indexOf(selected.kind) >= 0
                    && Math.abs(p[0]-selected.x-selected.w)*width < 10 && Math.abs(p[1]-selected.y-selected.h)*height < 10;
                if (root.resizing) return;
                root.document.selected = root.hit(p[0], p[1]);
                return;
            }
            if (root.tool==="note") {root.noteRequested(-1,p[0],p[1]);return;}
            if (root.tool==="editText") {
                if (root.document.textPage!==root.document.page.number) {root.document.ensureText();return;}
                var line=root.document.textLines.find(function(line){return p[0]>=line.x-0.004 && p[0]<=line.x+line.w+0.004 && p[1]>=line.y-0.004 && p[1]<=line.y+line.h+0.004;});
                if(line)root.beginOriginal(line);else root.document.status="Choose a text line. Scanned pages need OCR first.";
                return;
            }
            if (root.tool === "text") {
                var index = root.hit(p[0], p[1]);
                if (index >= 0 && root.document.marks[index].kind === "text") {
                    root.beginText(index, 0, 0);
                } else root.beginText(-1, p[0], p[1]);
                return;
            }
            root.draft = {kind: root.tool, color: root.inkColor, size: root.strokeSize,
                x: p[0], y: p[1], w: 0, h: 0, points: [p]};
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return;
            var p = position(mouse);
            if (root.tool === "select") {
                root.dragX = p[0] - startX; root.dragY = p[1] - startY;
            } else if (root.draft) {
                if (root.draft.kind === "ink") root.draft.points.push(p);
                else {
                    root.draft.x = Math.min(startX, p[0]); root.draft.y = Math.min(startY, p[1]);
                    root.draft.w = Math.abs(p[0] - startX); root.draft.h = Math.abs(p[1] - startY);
                }
            }
            canvas.requestPaint();
        }
        onReleased: {
            if (root.tool === "select") {
                if (root.resizing) root.document.resizeMark(root.document.selected, root.dragX, root.dragY);
                else root.document.moveMark(root.document.selected, root.dragX, root.dragY);
            }
            else if (root.draft && (root.draft.kind === "ink" ? root.draft.points.length > 1 : root.draft.w > 0.002 && root.draft.h > 0.002))
                root.document.addMark(root.draft);
            root.dragX = 0; root.dragY = 0; root.draft = null; root.resizing = false;
            canvas.requestPaint();
        }
        onCanceled: { root.dragX = 0; root.dragY = 0; root.draft = null; root.resizing = false; }
        onDoubleClicked: function(mouse) {
            var p = position(mouse);
            var index = root.hit(p[0], p[1]);
            if (root.tool === "select" && index >= 0) {
                if(root.document.marks[index].kind === "text") root.beginText(index, 0, 0);
                else if(root.document.marks[index].kind === "note") root.noteRequested(index,0,0);
            }
        }
    }
    SigningOverlay {anchors.fill:parent;document:root.document;visible:root.tool==="signing";enabled:root.available}
    FormOverlay {
        anchors.fill:parent
        visible:root.document.showForms && root.document.formFields.length>0 && root.tool==="select" && !root.textEditing
        document:root.document
        interactive:root.available
    }
    TextEdit {
        id: inlineText
        objectName: "inlineTextEditor"
        visible: root.textEditing
        enabled: !root.document.busy
        x: root.textDraft ? root.textDraft.x * root.width : 0
        y: root.textDraft ? root.textDraft.y * root.height + root.textSize * root.unit - baselineOffset : 0
        width: Math.max(80, contentWidth + 8)
        height: Math.max(font.pixelSize * 1.3, contentHeight)
        font.family: root.fontFamily(root.textFont)
        font.pixelSize: Math.max(1, root.textSize * root.unit)
        color: root.inkColor
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.NoWrap
        selectByMouse: true
        selectionColor: "#b6d4ff"
        selectedTextColor: root.inkColor
        onActiveFocusChanged: if (!activeFocus) root.finishText(true)
        Keys.onPressed: function(event) {
        if (tool === "eyedropper" && event.key === Qt.Key_Escape) {
            colorPickCancelled(); event.accepted=true; return;
        }
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                root.finishText(true); root.forceActiveFocus(); event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.finishText(false); root.forceActiveFocus(); event.accepted = true;
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            color: "transparent"
            border.color: "#4279c2"
            border.width: 1
            z: -1
        }
        Text {
            visible: !inlineText.text
            text: "Type here…"
            color: "#777777"
            font: inlineText.font
        }
    }
}
