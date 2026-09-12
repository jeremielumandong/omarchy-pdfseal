import QtQuick
import qs.Commons

Item {
    id: root
    required property var document
    property string tool: "ink"
    property string inkColor: "#153355"
    property real strokeSize: 2
    property var draft: null
    property real dragX: 0
    property real dragY: 0
    readonly property real unit: document.page ? width / document.page.width : 1
    readonly property bool available: document.preview !== "" && !document.busy
    signal textPlacementRequested(real x, real y)
    signal textSelected()

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
            if (mark.page !== document.page.number) continue;
            var box = bounds(mark);
            if (x >= box.x - 0.01 && x <= box.x + box.w + 0.01 && y >= box.y - 0.01 && y <= box.y + box.h + 0.01) return i;
        }
        return -1;
    }
    function paintMark(ctx, mark, selected) {
        ctx.save();
        if (selected) ctx.translate(root.dragX * width, root.dragY * height);
        ctx.strokeStyle = mark.color;
        ctx.fillStyle = mark.color;
        ctx.lineWidth = mark.size * unit;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        if (mark.kind === "ink") {
            ctx.beginPath();
            for (var i = 0; i < mark.points.length; ++i) {
                var point = mark.points[i];
                if (i === 0) ctx.moveTo(point[0] * width, point[1] * height);
                else ctx.lineTo(point[0] * width, point[1] * height);
            }
            ctx.stroke();
        } else if (mark.kind === "text") {
            ctx.font = (mark.size * unit) + "px 'Nimbus Sans'";
            ctx.textBaseline = "alphabetic";
            ctx.fillText(mark.text, mark.x * width, mark.y * height + mark.size * unit);
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
            ctx.strokeRect((b.x + root.dragX) * width - 4, (b.y + root.dragY) * height - 4, b.w * width + 8, b.h * height + 8);
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
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!root.document.page) return;
            root.document.marks.forEach(function(mark, index) {
                if (mark.page === root.document.page.number) root.paintMark(ctx, mark, index === root.document.selected);
            });
            if (root.draft) root.paintMark(ctx, root.draft, false);
        }
    }
    Connections {
        target: root.document
        function onMarksChanged() { canvas.requestPaint(); }
        function onPageChanged() { root.draft = null; canvas.requestPaint(); }
        function onSelectedChanged() { canvas.requestPaint(); }
    }
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onToolChanged: canvas.requestPaint()
    onDraftChanged: canvas.requestPaint()
    MouseArea {
        objectName: "pageInput"
        anchors.fill: parent
        enabled: root.available
        cursorShape: root.tool === "select" ? Qt.ArrowCursor : Qt.CrossCursor
        property real startX: 0
        property real startY: 0
        function position(mouse) { return [Math.max(0, Math.min(1, mouse.x / width)), Math.max(0, Math.min(1, mouse.y / height))]; }
        onPressed: function(mouse) {
            var p = position(mouse);
            startX = p[0]; startY = p[1];
            if (root.tool === "select") {
                root.document.selected = root.hit(p[0], p[1]);
                return;
            }
            if (root.tool === "text") {
                var index = root.hit(p[0], p[1]);
                if (index >= 0 && root.document.marks[index].kind === "text") {
                    root.document.selected = index;
                    root.textSelected();
                } else root.textPlacementRequested(p[0], p[1]);
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
            if (root.tool === "select") root.document.moveMark(root.document.selected, root.dragX, root.dragY);
            else if (root.draft && (root.draft.kind === "ink" ? root.draft.points.length > 1 : root.draft.w > 0.002 && root.draft.h > 0.002))
                root.document.addMark(root.draft);
            root.dragX = 0; root.dragY = 0; root.draft = null;
            canvas.requestPaint();
        }
        onCanceled: { root.dragX = 0; root.dragY = 0; root.draft = null; }
    }
}
