import QtQuick
import QtTest
import Quickshell

ShellRoot {
    id:root
    property int phase:0
    property bool checking:false
    property var input:null
    property real openedAt:0
    property real firstPreviewMs:0
    property real wheelStart:0
    property int scrollTicks:0
    property int peakCanvases:0
    property string pageOnePreview:""
    property real dragScrollX:0
    property real dragScrollY:0
    readonly property string testDir:Quickshell.env("PDFSEAL_TEST_DIR")
    Component{id:eventFactory;TestEvent{}}
    Editor{id:editor}
    function find(item,name){if(item.objectName===name)return item;var children=item.children || [];for(var i=0;i<children.length;i++){var result=find(children[i],name);if(result)return result;}return null;}
    function control(name){for(var i=0;i<editor.data.length;i++){var item=editor.data[i];if(item.contentItem){var result=find(item.contentItem,name);if(result)return result;}}throw new Error("Missing "+name);}
    function click(item,x,y){item.Window.window.requestActivate();if(!input.mouseClick(item,x,y,Qt.LeftButton,Qt.NoModifier,0))throw new Error("Pointer event failed");}
    function drag(page,x,y,dx,dy,objectGesture){
        var reader=control("pdfViewport"),start=page.mapToItem(reader,x,y);
        reader.Window.window.requestActivate();
        var oldX=reader.contentX,oldY=reader.contentY;
        input.mousePress(reader,start.x,start.y,Qt.LeftButton,Qt.NoModifier,0);
        // Several moves beyond the drag threshold exercise Flickable's grab;
        // a single synthetic move can miss the gesture takeover entirely.
        for(var step=1;step<=8;step++){
            input.mouseMove(reader,start.x+dx*step/8,start.y+dy*step/8,10,Qt.LeftButton,Qt.NoModifier);
            if(objectGesture && (Math.abs(reader.contentX-oldX)>1 || Math.abs(reader.contentY-oldY)>1))throw new Error("Object gesture scrolled the PDF at step "+step);
        }
        input.mouseRelease(reader,start.x+dx,start.y+dy,Qt.LeftButton,Qt.NoModifier,0);
    }
    function moveObject(index){
        var doc=editor.document,page=control("pageInput"),mark=doc.marks[index],box=page.parent.bounds(mark);
        var old=JSON.stringify(mark),history=doc.undoStack.length;
        drag(page,(box.x+box.w/2)*page.width,(box.y+box.h/2)*page.height,48,64,true);
        var moved=page.parent.bounds(doc.marks[index]);
        if(doc.selected!==index || Math.abs((moved.x-box.x)*page.width-48)>2 || Math.abs((moved.y-box.y)*page.height-64)>2)throw new Error("Object did not follow the pointer: "+mark.kind);
        if(doc.undoStack.length!==history+1)throw new Error("Object drag should create one undo step");
        doc.undo();if(JSON.stringify(doc.marks[index])!==old)throw new Error("Object drag undo failed");
    }
    Timer{interval:300;running:true;onTriggered:{editor.open();root.openedAt=Date.now();editor.openedPdf(root.testDir+"/twelve-pages.pdf");check.start();}}
    Timer {
        id:check;interval:100;repeat:true
        onTriggered:{
            if(root.checking)return;root.checking=true;
            try {
                var doc=editor.document,reader=control("pdfViewport");
                root.peakCanvases=Math.max(root.peakCanvases,Object.keys(reader.canvases).length);
                if(doc.error)throw new Error(doc.error);
                if(root.peakCanvases>7 || Object.keys(doc.previews).length>8)throw new Error("Reader did not bound live pages and previews");
                if(root.phase===0 && doc.preview){
                    root.firstPreviewMs=Date.now()-root.openedAt;
                    if(doc.pages.length!==12 || reader.contentHeight<reader.height*5)throw new Error("Pages are not laid out continuously");
                    root.input=eventFactory.createObject(control("pageInput").Window.window.contentItem);
                    root.pageOnePreview=doc.preview;root.phase=1;
                }else if(root.phase===1 && doc.previewFor(2)){
                    root.wheelStart=reader.contentY;
                    input.mouseWheel(reader,reader.width/2,reader.height/2,Qt.NoButton,Qt.NoModifier,0,-720,0);
                    root.phase=2;
                }else if(root.phase===2){
                    if(reader.contentY<=root.wheelStart)throw new Error("Ordinary wheel did not scroll the PDF");
                    if(doc.current<1 && root.scrollTicks++<12){input.mouseWheel(reader,reader.width/2,reader.height/2,Qt.NoButton,Qt.NoModifier,0,-720,0);return;}
                    if(doc.current<1)throw new Error("Scrolling did not cross pages: y="+reader.contentY+", page="+doc.current);
                    if(!doc.preview)return;
                    reader.cancelFlick();doc.current=2;root.phase=3;
                }else if(root.phase===3 && doc.current===2 && doc.preview && doc.operation===""){
                    editor.tool="text";var page=control("pageInput");click(page,page.width*0.2,page.height*0.1);
                    var label="Page Three Edit";for(var i=0;i<label.length;i++)if(!input.keyClickChar(label[i],Qt.NoModifier,0))throw new Error("Typing failed");input.keyClick(Qt.Key_Return,Qt.NoModifier,0);
                    if(doc.marks.length!==1 || doc.marks[0].page!==3)throw new Error("Edit was attached to the wrong scrolled page");
                    editor.tool="select";doc.selected=-1;root.phase=8;
                }else if(root.phase===8){
                    // Drag an unselected text object, then an already-selected
                    // shape and ink stroke while the page is taller than view.
                    moveObject(0);
                    doc.addMark({kind:"box",x:0.45,y:0.12,w:0.15,h:0.06,color:"#153355",size:2});
                    moveObject(1);
                    doc.selected=1;var page=control("pageInput"),mark=doc.marks[1],old=JSON.stringify(mark),history=doc.undoStack.length;
                    drag(page,(mark.x+mark.w)*page.width,(mark.y+mark.h)*page.height,40,48,true);
                    var resized=doc.marks[1];
                    if(Math.abs((resized.w-mark.w)*page.width-40)>2 || Math.abs((resized.h-mark.h)*page.height-48)>2)throw new Error("Resize did not follow the pointer");
                    if(doc.undoStack.length!==history+1)throw new Error("Resize should create one undo step");
                    doc.undo();if(JSON.stringify(doc.marks[1])!==old)throw new Error("Resize undo failed");
                    doc.selected=1;doc.removeMark();
                    doc.addMark({kind:"ink",points:[[0.45,0.12],[0.55,0.18]],color:"#153355",size:2});
                    moveObject(1);doc.selected=1;doc.removeMark();
                    root.dragScrollX=reader.contentX;root.dragScrollY=reader.contentY;root.phase=9;
                }else if(root.phase===9){
                    if(Math.abs(reader.contentX-root.dragScrollX)>1 || Math.abs(reader.contentY-root.dragScrollY)>1)throw new Error("Object release started PDF momentum");
                    var page=control("pageInput");
                    drag(page,page.width*0.8,page.height*0.25,0,-100,false);
                    root.phase=10;
                }else if(root.phase===10){
                    if(reader.contentY<=root.dragScrollY+20)throw new Error("Background drag no longer scrolls the PDF");
                    reader.cancelFlick();doc.current=0;root.phase=4;
                }else if(root.phase===4 && doc.current===0 && doc.preview){
                    if(doc.preview!==root.pageOnePreview || doc.marks[0].page!==3)throw new Error("Returning to a cached page lost state");
                    var p=reader.layouts[0],py=Math.min(reader.height/2,p.height*0.3),old=(reader.contentY+py-p.y)/p.height;
                    reader.zoomAt(doc.zoom*1.2,reader.width/2,py);p=reader.layouts[0];var next=(reader.contentY+py-p.y)/p.height;
                    if(Math.abs(next-old)>0.02)throw new Error("Zoom moved the PDF point under the cursor");
                    reader.contentY=reader.layouts[11].y;root.phase=5;
                }else if(root.phase===5 && doc.current===11 && doc.preview){
                    // Request export while background previews may still be running.
                    doc.exportDocument(root.testDir+"/reader-export.pdf",false,"");root.phase=6;
                }else if(root.phase===6 && doc.status.startsWith("Saved ")){
                    if(doc.dirty)throw new Error("Export did not save the document");
                    editor.close();root.phase=7;
                }else if(root.phase===7 && !doc.ready){
                    console.log("PASS: continuous reader, normal wheel across pages, nearby previews, zoom anchor, page-specific edits, object drag/resize without scrolling, gesture undo, background dragging, cached return, jump to page 12, queued export; first preview "+root.firstPreviewMs+" ms, peak "+root.peakCanvases+" live page canvases");check.stop();Qt.quit();
                }
            }catch(error){console.error("FAIL reader phase "+root.phase+": "+error);check.stop();Qt.quit();}
            finally{root.checking=false;}
        }
    }
}
