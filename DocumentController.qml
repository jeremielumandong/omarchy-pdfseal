import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    property string workerPath: decodeURIComponent(Qt.resolvedUrl("bin/pdfseal-worker").toString().replace(/^file:\/\//, ""))
    property bool ready: false
    property string operation: ""
    property string sourcePath: ""
    property string error: ""
    property string status: "Open a PDF to get started."
    property var pages: []
    property var marks: []
    property var undoStack: []
    property var redoStack: []
    property int current: 0
    property int selected: -1
    property real zoom: 1
    property string preview: ""
    property int previewPage: 0
    property int previewPixels: 0
    property int serial: 0
    property var pendingOpen: null
    property string savedState: ""
    property bool stopping: false
    readonly property bool busy: operation === "open" || operation === "export"
    readonly property var page: pages.length ? pages[Math.min(current, pages.length - 1)] : null
    readonly property bool loaded: pages.length > 0
    readonly property bool dirty: loaded && snapshot() !== savedState
    readonly property string fileName: sourcePath.split("/").pop()
    readonly property int desiredPixels: Math.min(2600, Math.max(1200, Math.round(1600 * zoom / 200) * 200))
    signal exported(string path)
    signal stopped()

    function filePath(url) {
        var text = url.toString();
        return text.startsWith("file://") ? decodeURIComponent(text.substring(7)) : "";
    }
    function fileUrl(path) {
        return "file://" + path.split("/").map(function(part) { return encodeURIComponent(part); }).join("/");
    }
    function snapshot() { return JSON.stringify({pages: pages, marks: marks}); }
    function remember() {
        undoStack = undoStack.concat([snapshot()]).slice(-100);
        redoStack = [];
    }
    function restore(value) {
        var state = JSON.parse(value);
        pages = state.pages;
        marks = state.marks;
        current = Math.min(current, pages.length - 1);
        selected = -1;
    }
    function undo() {
        if (busy || !undoStack.length) return;
        redoStack = redoStack.concat([snapshot()]);
        restore(undoStack[undoStack.length - 1]);
        undoStack = undoStack.slice(0, -1);
    }
    function redo() {
        if (busy || !redoStack.length) return;
        undoStack = undoStack.concat([snapshot()]);
        restore(redoStack[redoStack.length - 1]);
        redoStack = redoStack.slice(0, -1);
    }
    function addMark(mark) {
        remember();
        mark.page = page.number;
        marks = marks.concat([mark]);
        selected = marks.length - 1;
    }
    function removeMark() {
        if (busy || selected < 0) return;
        remember();
        marks = marks.filter(function(mark, index) { return index !== root.selected; });
        selected = -1;
    }
    function moveMark(index, dx, dy) {
        if (busy || index < 0 || (!dx && !dy)) return;
        var next = JSON.parse(JSON.stringify(marks));
        var mark = next[index];
        var minX = mark.x || 0, maxX = minX + (mark.w || 0);
        var minY = mark.y || 0, maxY = minY + (mark.h || 0);
        if (mark.kind === "ink") {
            minX = Math.min.apply(null, mark.points.map(function(p) { return p[0]; }));
            maxX = Math.max.apply(null, mark.points.map(function(p) { return p[0]; }));
            minY = Math.min.apply(null, mark.points.map(function(p) { return p[1]; }));
            maxY = Math.max.apply(null, mark.points.map(function(p) { return p[1]; }));
        }
        dx = Math.max(-minX, Math.min(1 - maxX, dx));
        dy = Math.max(-minY, Math.min(1 - maxY, dy));
        remember();
        if (mark.kind === "ink") mark.points = mark.points.map(function(p) { return [p[0] + dx, p[1] + dy]; });
        else { mark.x += dx; mark.y += dy; }
        marks = next;
    }
    function rotatePage() {
        if (busy || !page) return;
        remember();
        var next = pages.slice();
        var changed = Object.assign({}, page);
        changed.rotation = (changed.rotation + 90) % 360;
        next[current] = changed;
        pages = next;
    }
    function movePage(delta) {
        var target = current + delta;
        if (busy || target < 0 || target >= pages.length) return;
        remember();
        var next = pages.slice();
        var item = next.splice(current, 1)[0];
        next.splice(target, 0, item);
        pages = next;
        current = target;
    }
    function removePage() {
        if (busy || pages.length <= 1) return;
        remember();
        var removed = page.number;
        pages = pages.filter(function(p) { return p.number !== removed; });
        marks = marks.filter(function(mark) { return mark.page !== removed; });
        current = Math.min(current, pages.length - 1);
        selected = -1;
    }
    function request(op, values) {
        if (!ready || operation !== "") return false;
        operation = op;
        values.op = op;
        values.id = ++serial;
        worker.write(JSON.stringify(values) + "\n");
        return true;
    }
    function openDocument(path, password) {
        if (!path || busy) return;
        pendingOpen = { path: path, password: password || "" };
        error = "";
        if (!worker.running) {
            stopping = false;
            worker.stdinEnabled = true;
            worker.running = true;
        } else pump();
    }
    function pump() {
        if (!ready || operation !== "" || stopping) return;
        if (pendingOpen) {
            var next = pendingOpen;
            pendingOpen = null;
            status = "Opening PDF…";
            request("open", next);
        } else if (page && (previewPage !== page.number || previewPixels !== desiredPixels)) {
            request("render", {page: page.number, pixels: desiredPixels});
        }
    }
    function exportDocument(path, compress, password) {
        if (!loaded || busy) return;
        if (operation !== "") { error = "Wait for the page preview to finish, then export."; return; }
        error = "";
        status = "Exporting PDF…";
        request("export", {path: path, pages: pages, marks: marks, compress: compress, password: password});
    }
    function shutdown() {
        if (busy) return;
        stopping = true;
        pendingOpen = null;
        if (worker.running) worker.stdinEnabled = false;
        else stopped();
    }
    function receive(message) {
        if (message.event === "ready") { ready = true; pump(); return; }
        if (message.id !== serial) return;
        operation = "";
        if (!message.ok) {
            error = message.error || "PDF operation failed.";
            status = "Could not complete the operation.";
            return;
        }
        var result = message.result;
        if (message.op === "open") {
            sourcePath = result.path;
            pages = result.pages.map(function(p) { p.rotation = 0; return p; });
            marks = [];
            undoStack = [];
            redoStack = [];
            current = 0;
            selected = -1;
            preview = "";
            previewPage = 0;
            previewPixels = 0;
            savedState = snapshot();
            status = "Draw a signature or choose an annotation tool.";
        } else if (message.op === "render") {
            if (page && result.page === page.number && result.pixels === desiredPixels) {
                preview = fileUrl(result.path);
                previewPage = result.page;
                previewPixels = result.pixels;
            }
        } else if (message.op === "export") {
            savedState = snapshot();
            status = "Saved " + result.path.split("/").pop();
            exported(result.path);
        }
        pump();
    }
    onPageChanged: {
        selected = -1;
        if (page && page.number !== previewPage) preview = "";
        renderDebounce.restart();
    }
    onDesiredPixelsChanged: renderDebounce.restart()
    Timer { id: renderDebounce; interval: 120; onTriggered: root.pump() }
    Process {
        id: worker
        command: [root.workerPath]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function(data) {
                try { root.receive(JSON.parse(data)); }
                catch (e) { root.error = "Could not read the PDF worker response."; }
            }
        }
        onExited: function(exitCode, exitStatus) {
            root.ready = false;
            root.operation = "";
            if (root.stopping) {
                root.pages = [];
                root.marks = [];
                root.preview = "";
                root.stopped();
            } else root.error = "The PDF worker stopped. Reopen the PDF to continue.";
        }
    }
}
