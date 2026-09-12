import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Flickable {
    id:root
    objectName:"pdfViewport"
    required property var document
    property string tool:"select"
    property string inkColor:"#153355"
    property real strokeSize:2
    property real textSize:18
    property string textFont:"sans"
    property string previewInk:""
    property var layouts:[]
    property var visiblePages:[]
    property var canvases:({})
    property real totalHeight:0
    property real paperWidth:0
    property bool selecting:false
    property bool layingOut:false
    readonly property var activeCanvas:document.page ? canvases[document.page.number] || null : null
    readonly property bool textEditing:activeCanvas ? activeCanvas.textEditing : false
    readonly property bool textDraftDirty:activeCanvas ? activeCanvas.textDraftDirty : false
    signal existingTextEditingStarted(real size)
    signal noteRequested(int index,real x,real y)
    signal colorPicked(string color)
    signal colorPickCancelled()
    signal textEditingStarted()
    clip:true
    contentWidth:Math.max(width,paperWidth+32)
    contentHeight:Math.max(height,totalHeight)
    boundsBehavior:Flickable.StopAtBounds
    flickableDirection:Flickable.AutoFlickDirection
    maximumFlickVelocity:6500
    Controls.ScrollBar.vertical:Controls.ScrollBar{}
    Controls.ScrollBar.horizontal:Controls.ScrollBar{}

    function finishText(save){if(activeCanvas)activeCanvas.finishText(save);}
    function beginText(index,x,y){if(activeCanvas)activeCanvas.beginText(index,x,y);}
    function focusPage(){if(activeCanvas)activeCanvas.forceActiveFocus();else forceActiveFocus();}
    function registerCanvas(number,canvas){var next=Object.assign({},canvases);next[number]=canvas;canvases=next;}
    function unregisterCanvas(number,canvas){if(canvases[number]!==canvas)return;var next=Object.assign({},canvases);delete next[number];canvases=next;}
    function pageAt(y){
        var low=0,high=layouts.length-1;
        while(low<high){var mid=Math.floor((low+high)/2);if(layouts[mid].y+layouts[mid].height+16<y)low=mid+1;else high=mid;}
        return Math.max(0,low);
    }
    function activate(number){
        var index=document.pages.findIndex(function(p){return p.number===number;});
        if(index<0 || index===document.current)return;
        finishText(true);selecting=true;document.current=index;selecting=false;
        refreshPreviews();
    }
    function rebuild(){
        if(width<=0 || layingOut)return;
        layingOut=true;
        var widest=1;
        document.pages.forEach(function(p){widest=Math.max(widest,p.rotation%180 ? p.height : p.width);});
        var scale=Math.max(0.05,(width-40)/widest)*document.zoom;
        var y=16;var next=[];
        document.pages.forEach(function(p){var sideways=p.rotation%180!==0;var w=(sideways ? p.height : p.width)*scale,h=(sideways ? p.width : p.height)*scale;next.push({page:p,y:y,width:w,height:h,scale:scale});y+=h+16;});
        layouts=next;paperWidth=widest*scale;totalHeight=y;
        layingOut=false;updateVisible();
    }
    function refreshPreviews(){
        if(!layouts.length)return;
        var indices=visiblePages.slice().sort(function(a,b){return Math.abs(a-root.document.current)-Math.abs(b-root.document.current);});
        document.requestPages(indices.map(function(i){return root.layouts[i].page.number;}));
    }
    function updateVisible(){
        if(layingOut || !layouts.length){if(!layouts.length)visiblePages=[];return;}
        var first=pageAt(Math.max(0,contentY)),last=pageAt(contentY+height);
        var next=[];for(var i=Math.max(0,first-1);i<=Math.min(layouts.length-1,last+1);i++)next.push(i);
        if(next.join(",")!==visiblePages.join(","))visiblePages=next;
        refreshPreviews();
    }
    function trackPage(){
        if(selecting || layingOut || !layouts.length)return;
        var index=pageAt(contentY+Math.min(height*0.4,180));
        activate(layouts[index].page.number);
        updateVisible();
    }
    function reveal(index){
        if(selecting || layingOut || !layouts[index])return;
        finishText(true);selecting=true;
        contentY=Math.max(0,Math.min(contentHeight-height,layouts[index].y-16));
        selecting=false;updateVisible();
    }
    function zoomAt(value,px,py){
        if(!document.loaded || document.busy || !layouts.length)return;
        finishText(true);
        var index=pageAt(contentY+py),before=layouts[index];
        var fy=(contentY+py-before.y)/Math.max(1,before.height);
        var fx=(contentX+px-(contentWidth-before.width)/2)/Math.max(1,before.width);
        selecting=true;document.zoom=Math.max(0.5,Math.min(5,value));rebuild();
        var after=layouts[index];
        contentY=Math.max(0,Math.min(contentHeight-height,after.y+fy*after.height-py));
        contentX=Math.max(0,Math.min(contentWidth-width,(contentWidth-after.width)/2+fx*after.width-px));
        selecting=false;updateVisible();
    }
    onContentYChanged:{updateVisible();if(!scrollSelection.running)scrollSelection.start();}
    onHeightChanged:updateVisible()
    onWidthChanged:rebuild()
    Component.onCompleted:rebuild()
    Timer{id:scrollSelection;interval:60;onTriggered:root.trackPage()}
    Connections {
        target:root.document
        function onPagesChanged(){root.rebuild();}
        function onCurrentChanged(){root.reveal(root.document.current);}
        function onZoomChanged(){root.rebuild();}
        function onDocumentReset(){root.selecting=true;root.contentY=0;root.contentX=0;root.rebuild();root.selecting=false;root.updateVisible();}
    }
    PinchHandler {
        id:pinch;objectName:"pdfPinch";target:null
        enabled:root.document.loaded && !root.document.busy
        acceptedDevices:PointerDevice.TouchPad | PointerDevice.TouchScreen
        property real startingZoom:1
        onActiveChanged:if(active){root.finishText(true);startingZoom=root.document.zoom;root.cancelFlick();}
        onActiveScaleChanged:if(active)root.zoomAt(startingZoom*activeScale,centroid.position.x,centroid.position.y)
    }
    WheelHandler {
        target:null;acceptedModifiers:Qt.ControlModifier
        acceptedDevices:PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel:function(event){var delta=event.angleDelta.y || event.pixelDelta.y;root.zoomAt(root.document.zoom*Math.exp(delta/600),event.x,event.y);event.accepted=true;}
    }
    Keys.onPressed:function(event){
        if(event.modifiers!==Qt.NoModifier)return;
        var step=event.key===Qt.Key_PageDown ? height*0.9 : event.key===Qt.Key_PageUp ? -height*0.9 : event.key===Qt.Key_Down ? 50 : event.key===Qt.Key_Up ? -50 : 0;
        if(step){contentY=Math.max(0,Math.min(contentHeight-height,contentY+step));event.accepted=true;}
    }
    Repeater {
        model:root.visiblePages
        delegate:Item {
            id:frame
            required property int modelData
            readonly property var geometry:root.layouts[modelData] || null
            x:(root.contentWidth-width)/2;y:geometry ? geometry.y : 0
            width:geometry ? geometry.width : 0;height:geometry ? geometry.height : 0
            Rectangle{anchors.fill:parent;color:"white";border.color:"#22000000"}
            Text{z:1;anchors.centerIn:parent;visible:page.pagePreview==="";text:frame.geometry ? "Page "+(frame.modelData+1)+"…" : "";color:"#777777";font.family:Style.font.family}
            PageCanvas {
                id:page
                anchors.centerIn:parent
                width:frame.geometry ? frame.geometry.page.width*frame.geometry.scale : 0
                height:frame.geometry ? frame.geometry.page.height*frame.geometry.scale : 0
                rotation:frame.geometry ? frame.geometry.page.rotation : 0
                document:root.document
                pageData:frame.geometry ? frame.geometry.page : null
                pagePreview:pageData ? root.document.previewFor(pageData.number) : ""
                tool:root.tool;inkColor:root.inkColor;strokeSize:root.strokeSize;textSize:root.textSize;textFont:root.textFont;previewInk:root.previewInk
                onPageActivated:function(number){root.activate(number);}
                onExistingTextEditingStarted:function(size){root.existingTextEditingStarted(size);}
                onNoteRequested:function(index,x,y){root.noteRequested(index,x,y);}
                onColorPicked:function(color){root.colorPicked(color);}
                onColorPickCancelled:root.colorPickCancelled()
                onTextEditingStarted:root.textEditingStarted()
                property int registeredPage:0
                property bool complete:false
                function registerPage(){if(registeredPage)root.unregisterCanvas(registeredPage,page);registeredPage=pageData ? pageData.number : 0;if(registeredPage)root.registerCanvas(registeredPage,page);}
                onPageDataChanged:if(complete)registerPage()
                Component.onCompleted:{complete=true;registerPage();}
                Component.onDestruction:if(registeredPage)root.unregisterCanvas(registeredPage,page)
            }
        }
    }
}
