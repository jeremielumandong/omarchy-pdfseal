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
    readonly property var selectedMark: selected >= 0 && selected < marks.length ? marks[selected] : null
    property real zoom: 1
    property string preview: ""
    property int previewPage: 0
    property int previewPixels: 0
    property var previews:({})
    property var previewOrder:[]
    property var wantedPages:[]
    property int renderingPage:0
    signal documentReset()
    property int serial: 0
    property string openingPath: ""
    signal passwordNeeded(string path)
    property var pendingOpen: null
    property var pendingColor: null
    signal colorSampled(string color)
    property var pendingImage: null
    property var savedSignatures: []
    property var pendingAction: null
    property var formFields: []
    property var formValues: ({})
    property string formEditName: ""
    property bool showForms: true
    property alias signing: signing
    SigningController {id:signing;document:root}
    property var textLines: []
    property int textPage: 0
    property bool textRequested: false
    property var searchHits: []
    property int searchIndex: -1
    property bool keepAttachments: false
    property int revision: 0
    property real progress: 0
    property var compressionPreview: null
    signal operationFinished(var result)
    property string savedState: ""
    property bool stopping: false
    readonly property bool busy: (operation !== "" && operation !== "render") || pendingImage !== null || pendingColor !== null || pendingAction !== null
    readonly property var page: pages.length ? pages[Math.min(current, pages.length - 1)] : null
    readonly property bool loaded: pages.length > 0
    readonly property bool dirty: loaded && snapshot() !== savedState
    readonly property string fileName: sourcePath.split("/").pop()
    readonly property int desiredPixels: Math.min(2600, Math.max(1200, Math.round(1600 * zoom / 200) * 200))
    signal exported(string path)
    signal stopped()
    signal imagePrepared(var asset)

    function filePath(url) {
        var text = url.toString();
        return text.startsWith("file://") ? decodeURIComponent(text.substring(7)) : "";
    }
    function fileUrl(path) {
        return "file://" + path.split("/").map(function(part) { return encodeURIComponent(part); }).join("/");
    }
    function snapshot() { return JSON.stringify({pages: pages, marks: marks, revision: revision,formValues:formValues,signing:signing.manifest()}); }
    function remember() {
        formEditName="";
        undoStack = undoStack.concat([snapshot()]).slice(-100);
        redoStack = [];
    }
    function restore(value) {
        var state = JSON.parse(value);
        pages = state.pages;
        marks = state.marks;
        revision = state.revision || 0;
        formValues=state.formValues || {};formEditName="";
        var previousMode=signing.mode;signing.hydrate(state.signing,false);signing.mode=previousMode;
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
    function textMark(x, y, text, size, color, font) {
        var lines = text.split("\n");
        var length = Math.max.apply(null, lines.map(function(line) { return line.length; }));
        return {kind: "text", color: color, font: font || "sans", size: size, text: text, x: x, y: y,
            w: Math.min(1 - x, Math.max(0.01, length * size * 0.6 / page.width)),
            h: Math.min(1 - y, size * (1.3 + (lines.length - 1) * 1.2) / page.height)};
    }
    function updateText(index, text, size, font, color) {
        var mark = marks[index];
        if (busy || !page || !mark || mark.kind !== "text" || mark.page !== page.number) return;
        size = Math.max(8, Math.min(72, size));
        font = font || mark.font || "sans";
        color = color || mark.color;
        if (mark.text === text && mark.size === size && (mark.font || "sans") === font && mark.color === color) return;
        var next = marks.slice();
        next[index] = Object.assign({}, mark, textMark(mark.x, mark.y, text, size, color, font));
        remember();
        marks = next;
    }
    function updateSelectedText(text, size, font, color) { updateText(selected, text, size, font, color); }
    function addImage(asset) {
        if (busy || !page) return;
        var w = 0.32;
        var h = w * page.width * asset.height / asset.width / page.height;
        if (h > 0.35) { w *= 0.35 / h; h = 0.35; }
        addMark({kind:"image",color:"#000000",size:1,x:(1-w)/2,y:0.3,w:w,h:h,dataUrl:asset.dataUrl});
        status = "Drag to move; use the corner handle to resize.";
    }
    function resizeMark(index, dw, dh) {
        var mark = marks[index];
        if (busy || !mark || ["image", "box", "highlight", "redact"].indexOf(mark.kind) < 0) return;
        var w = Math.max(0.01, Math.min(1 - mark.x, mark.w + dw));
        var h = Math.max(0.01, Math.min(1 - mark.y, mark.h + dh));
        if (w === mark.w && h === mark.h) return;
        remember();
        var next = marks.slice();
        next[index] = Object.assign({}, mark, {w:w,h:h});
        marks = next;
    }
    function finishFormEdit(){formEditName="";}
    function setFormValue(name,value) {
        if(busy || formValues[name]===value)return;
        if(formEditName!==name){remember();formEditName=name;}
        var next=Object.assign({},formValues);next[name]=value;formValues=next;
    }
    function ensureText() {textRequested=true;pump();}
    function search(query) {
        if (!loaded || busy) return;
        error="";
        pendingAction={op:"search",values:{query:query}};
        pump();
    }
    function nextSearch(delta) {
        if (!searchHits.length) return;
        searchIndex=(searchIndex+delta+searchHits.length)%searchHits.length;
        var number=searchHits[searchIndex].page;
        var index=pages.findIndex(function(page){return page.number===number;});
        if (index>=0) current=index;
    }
    function replaceText(line,text,size,color,font) {
        if (busy || !page) return;
        remember();
        var cover={kind:"cover",page:page.number,color:"#ffffff",size:1,x:Math.max(0,line.x-0.002),y:Math.max(0,line.y-0.002),w:Math.min(1-line.x,line.w+0.004),h:Math.min(1-line.y,line.h+0.004)};
        var next=marks.concat([cover]);
        if (text) next.push(Object.assign({page:page.number},textMark(line.x,line.textY===undefined ? line.y : line.textY,text,size,color,font)));
        marks=next;selected=next.length-1;
    }
    function saveNote(index,text,x,y,color) {
        if (busy || !page || !text.trim()) return;
        if (index<0) addMark({kind:"note",color:color,size:1,x:x,y:y,w:18/page.width,h:18/page.height,text:text.trim()});
        else if (marks[index] && marks[index].kind==="note" && marks[index].text!==text.trim()) {
            remember();var next=marks.slice();next[index]=Object.assign({},next[index],{text:text.trim()});marks=next;
        }
    }
    function sampleColor(x,y) {
        if (!loaded || busy) return;
        error="";
        status="Sampling PDF color…";
        pendingColor={page:page.number,pixels:desiredPixels,x:x,y:y,marks:marks,formValues:formValues};
        pump();
    }
    function prepareImage(source) {
        if (!loaded || busy) return;
        error = "";
        pendingImage = {source: source};
        pump();
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
        if(!canChangePages())return;
        if (busy || !page) return;
        remember();
        var next = pages.slice();
        var changed = Object.assign({}, page);
        changed.rotation = (changed.rotation + 90) % 360;
        next[current] = changed;
        pages = next;
    }
    function movePage(delta) {
        if(!canChangePages())return;
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
        if(!canChangePages())return;
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
    function fromImages(paths) {
        if (busy || loaded || !paths.length) return;
        error="";
        pendingAction={op:"fromImages",values:{paths:paths}};
        if (!worker.running) {stopping=false;worker.stdinEnabled=true;worker.running=true;} else pump();
    }
    function openDocument(path, password) {
        if (!path || busy) return;
        openingPath = path;
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
        } else if (pendingColor) {
            var sample=pendingColor;pendingColor=null;request("sample",sample);
        } else if (pendingImage) {
            var image = pendingImage;
            pendingImage = null;
            status = "Preparing image…";
            request("image", image);
        } else if (pendingAction) {
            var action = pendingAction;
            pendingAction = null;
            request(action.op, action.values);
        } else if(page) {
            var desired=[page.number].concat(wantedPages.filter(function(n){return n!==root.page.number;}));
            if(textRequested && textPage!==page.number && previewFor(page.number)) {request("text",{page:page.number});return;}
            for(var i=0;i<desired.length;i++) {
                if(!previews[desired[i]+":"+desiredPixels]) {renderingPage=desired[i];request("render",{page:desired[i],pixels:desiredPixels});return;}
            }
        }
    }
    function previewEntry(number){
        var exact=previews[number+":"+desiredPixels];if(exact)return exact;
        for(var i=previewOrder.length-1;i>=0;i--){var value=previews[previewOrder[i]];if(value && value.page===number)return value;}
        return null;
    }
    function previewFor(number){var entry=previewEntry(number);return entry ? entry.url : "";}
    function syncCurrentPreview(){var entry=page ? previewEntry(page.number) : null;preview=entry ? entry.url : "";previewPage=entry ? entry.page : 0;previewPixels=entry ? entry.pixels : 0;}
    function requestPages(numbers){
        numbers=numbers.slice(0,7);
        if(wantedPages.join(",")===numbers.join(","))return;
        wantedPages=numbers;
        if(operation==="render" && numbers.indexOf(renderingPage)<0 && page && renderingPage!==page.number)worker.write(JSON.stringify({op:"cancel",target:serial})+"\n");
        renderDebounce.restart();
    }

    function canChangePages(){if(signing.fields.length){error="Export or clear the signing setup before changing page structure.";return false;}return true;}
    function apply(action, options) {
        if(!canChangePages())return;
        if (!loaded || busy) return;
        error = "";
        progress = 0;
        status = "Preparing document…";
        pendingAction = {op:"apply", values:Object.assign({}, options || {}, {action:action,pages:pages,marks:marks,keepAttachments:keepAttachments,formValues:formValues})};
        pump();
    }
    function acceptCompression(path) {
        if (busy || !compressionPreview) return;
        pendingAction = {op:"acceptCompression",values:path ? {path:path} : {}};
        pump();
    }
    function cancel() {
        if (operation === "") return;
        worker.write(JSON.stringify({op:"cancel",target:serial}) + "\n");
        status = "Cancelling…";
    }
    function exportDocument(path, compress, password, options) {
        finishFormEdit();
        if (!loaded || busy) return;
        error = "";
        status = "Exporting PDF…";
        pendingAction={op:"export",values:Object.assign({path: path, pages: pages, marks: marks, compress: compress, password: password,keepAttachments:keepAttachments,formValues:formValues,signing:signing.recipients.length ? signing.manifest() : null},options || {})};
        pump();
    }
    function shutdown() {
        if (busy) return;
        stopping = true;
        pendingOpen = null;
        pendingImage = null;
        pendingColor = null;
        pendingAction = null;
        if (worker.running) worker.stdinEnabled = false;
        else stopped();
    }
    function receive(message) {
        if (message.event === "ready") { ready = true; pump(); return; }
        if (message.id !== serial) return;
        if (message.event === "progress") {
            progress = message.total ? message.current / message.total : 0;
            status = message.stage + "… " + message.current + "/" + message.total;
            return;
        }
        operation = "";
        if (!message.ok) {
            if(message.op==="render" && message.error==="Operation cancelled"){renderingPage=0;pump();return;}
            if (message.op === "open" && message.passwordRequired) {
                error = "";
                status = "This PDF requires its password.";
                passwordNeeded(openingPath);
                return;
            }
            var cancelled = message.error === "Operation cancelled";
            error = cancelled ? "" : (message.error || "PDF operation failed.");
            status = cancelled ? "Operation cancelled. Your document is unchanged." : "Could not complete the operation.";
            return;
        }
        var result = message.result;
        if (message.op === "open" || result.baked) {
            previews={};previewOrder=[];wantedPages=[];renderingPage=0;
            revision = result.baked ? revision + 1 : 0;
            signing.hydrate(result.signing,true);
            compressionPreview = null;
            textPage=0;textLines=[];searchHits=[];searchIndex=-1;
            formFields=result.forms ? result.forms.fields : [];formValues=result.forms ? result.forms.values : {};formEditName="";
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
            documentReset();
            if (!result.baked) savedState = snapshot();
            status = result.baked ? "Document updated. Export a copy to save it." : "Draw a signature or choose an annotation tool.";
            if (result.baked) operationFinished(result);
        } else if (message.op === "apply" || message.op === "acceptCompression") {
            if (result.candidate) { compressionPreview = result; status = "Compression preview ready."; }
            else if (result.folder) status = "Saved " + result.count + " files in " + result.folder;
            else if (result.saved) status = "Saved " + result.saved;
            operationFinished(result);
        } else if (message.op === "render") {
            renderingPage=0;
            var key=result.page+":"+result.pixels;
            var next=Object.assign({},previews);next[key]={page:result.page,pixels:result.pixels,url:fileUrl(result.path)};
            var order=previewOrder.filter(function(k){return k!==key;}).concat([key]);
            while(order.length>8)delete next[order.shift()];
            previews=next;previewOrder=order;syncCurrentPreview();
        } else if (message.op === "text") {
            textPage=result.page;textLines=result.lines;
        } else if (message.op === "search") {
            searchHits=result.hits.filter(function(hit){return pages.some(function(page){return page.number===hit.page;});});
            searchIndex=-1;nextSearch(1);
            status=searchHits.length ? searchHits.length+" matching lines." : "No matching text. Scanned pages may need OCR.";
        } else if (message.op === "sample") {
            colorSampled(result.color);
        } else if (message.op === "image") {
            imagePrepared(result);
        } else if (message.op === "export") {
            savedState = snapshot();
            status = "Saved " + result.path.split("/").pop();
            exported(result.path);
        }
        pump();
    }
    onPageChanged: {
        selected = -1;
        syncCurrentPreview();
        renderDebounce.restart();
    }
    onDesiredPixelsChanged:{syncCurrentPreview();renderDebounce.restart();}
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
                root.previews={};root.previewOrder=[];root.wantedPages=[];root.preview = "";
                root.stopped();
            } else root.error = "The PDF worker stopped. Reopen the PDF to continue.";
        }
    }
}
