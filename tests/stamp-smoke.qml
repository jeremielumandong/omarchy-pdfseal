import QtQuick
import QtTest
import Quickshell

ShellRoot {
    id:root
    property int phase:0
    property int stampIndex:0
    property bool checking:false
    property var input:null
    property int zoomIndex:0
    readonly property var zooms:[0.5,1,2]
    readonly property string testDir:Quickshell.env("PDFSEAL_TEST_DIR")
    Component{id:eventFactory;TestEvent{}}
    Editor{id:editor}
    function find(item,name){if(item.objectName===name)return item;var children=item.children || [];for(var i=0;i<children.length;i++){var result=find(children[i],name);if(result)return result;}return null;}
    function control(name){for(var i=0;i<editor.data.length;i++){var item=editor.data[i];if(item.contentItem){var result=find(item.contentItem,name);if(result)return result;}}throw new Error("Missing "+name);}
    Connections {
        target:editor.document
        function onImagePrepared(asset){console.log("STAMP_SIZE "+JSON.stringify({width:asset.width,height:asset.height}));}
    }
    Timer{interval:300;running:true;onTriggered:{editor.open();editor.openedPdf(root.testDir+"/input.pdf");check.start();}}
    Timer {
        id:check;interval:150;repeat:true
        onTriggered:{
            if(root.checking)return;root.checking=true;
            try {
                var doc=editor.document;
                if(doc.error)throw new Error(doc.error);
                if(root.phase===0 && doc.preview && !doc.busy){
                    root.input=eventFactory.createObject(control("pageInput").Window.window.contentItem);
                    console.log("STAMP_DPR "+control("pageInput").Screen.devicePixelRatio);
                    doc.addMark({kind:"cover",x:0,y:0,w:1,h:1,color:"#ffffff",size:1});
                    editor.stampOptions=true;root.phase=1;
                }else if(root.phase===1){
                    var card=control("stamp-"+root.stampIndex);
                    card.Window.window.requestActivate();
                    if(!input.mouseClick(card,card.width/2,card.height/2,Qt.LeftButton,Qt.NoModifier,0))throw new Error("Stamp click failed");
                    root.phase=2;
                }else if(root.phase===2 && !doc.busy && !editor.stampOptions){
                    if(doc.marks.length!==root.stampIndex+2)throw new Error("Stamp was not placed");
                    var mark=doc.marks[root.stampIndex+1];
                    doc.moveMark(root.stampIndex+1,0.08+(root.stampIndex%2)*0.5-mark.x,0.25+Math.floor(root.stampIndex/2)*0.17-mark.y);
                    if(++root.stampIndex<8){editor.stampOptions=true;root.phase=1;}
                    else{doc.exportDocument(root.testDir+"/stamps.pdf",false,"");root.phase=3;}
                }else if(root.phase===3 && doc.status.startsWith("Saved ")){
                    doc.selected=-1;
                    console.log("STAMP_MARKS "+JSON.stringify(doc.marks.slice(1).map(function(m){return {x:m.x,y:m.y,w:m.w,h:m.h};})));
                    root.phase=4;
                }else if(root.phase===4){
                    control("pdfViewport").zoomAt(root.zooms[root.zoomIndex],0,0);root.phase=5;
                }else if(root.phase===5){
                    root.phase=6;
                    var page=control("pageInput").parent;
                    page.grabToImage(function(result){
                        if(!result.saveToFile(root.testDir+"/onscreen-"+root.zooms[root.zoomIndex]+".png"))throw new Error("Could not capture stamp rendering");
                        if(++root.zoomIndex<root.zooms.length)root.phase=4;
                        else{editor.close();root.phase=7;}
                    },Qt.size(Math.round(page.width*page.Screen.devicePixelRatio),Math.round(page.height*page.Screen.devicePixelRatio)));
                }else if(root.phase===7 && !doc.ready){
                    console.log("PASS: all eight stamps generated, placed and exported");check.stop();Qt.quit();
                }
            }catch(error){console.error("FAIL stamp phase "+root.phase+": "+error);check.stop();Qt.quit();}
            finally{root.checking=false;}
        }
    }
}
