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
    readonly property string testDir:Quickshell.env("PDFSEAL_TEST_DIR")
    Component{id:eventFactory;TestEvent{}}
    Editor{id:editor}
    function find(item,name){if(item.objectName===name)return item;var children=item.children || [];for(var i=0;i<children.length;i++){var result=find(children[i],name);if(result)return result;}return null;}
    function control(name){for(var i=0;i<editor.data.length;i++){var item=editor.data[i];if(item.contentItem){var result=find(item.contentItem,name);if(result)return result;}}throw new Error("Missing "+name);}
    function click(item,x,y){item.Window.window.requestActivate();if(!input.mouseClick(item,x,y,Qt.LeftButton,Qt.NoModifier,0))throw new Error("Pointer event failed");}
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
                    doc.current=0;root.phase=4;
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
                    console.log("PASS: continuous reader, normal wheel across pages, nearby previews, zoom anchor, page-specific edits, cached return, jump to page 12, queued export; first preview "+root.firstPreviewMs+" ms, peak "+root.peakCanvases+" live page canvases");check.stop();Qt.quit();
                }
            }catch(error){console.error("FAIL reader phase "+root.phase+": "+error);check.stop();Qt.quit();}
            finally{root.checking=false;}
        }
    }
}
