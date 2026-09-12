import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property color initialColor: "#153355"
    property real hue: 0.6
    property real saturation: 0.7
    property real value: 0.3
    readonly property color chosenColor: Qt.hsva(hue,saturation,value,1)
    readonly property string hexColor: hex(chosenColor)
    signal accepted(string color)
    signal dismissed()
    signal eyedropperRequested()
    function hex(color) {
        return "#"+[color.r,color.g,color.b].map(function(v){return Math.round(v*255).toString(16).padStart(2,"0");}).join("");
    }
    function setColor(color) {
        var r=color.r,g=color.g,b=color.b;
        var max=Math.max(r,g,b),min=Math.min(r,g,b),delta=max-min;
        var h=0;
        if (delta>0) {
            if (max===r) h=((g-b)/delta)%6;
            else if (max===g) h=(b-r)/delta+2;
            else h=(r-g)/delta+4;
            h=(h/6+1)%1;
        }
        hue=h; saturation=max ? delta/max : 0; value=max;
    }
    onVisibleChanged: if (visible) {setColor(initialColor);hexInput.text=hexColor;panel.forceActiveFocus();}
    onHexColorChanged: if (!hexInput.activeFocus) hexInput.text=hexColor
    Rectangle {anchors.fill:parent;color:Qt.rgba(0,0,0,0.35);MouseArea {anchors.fill:parent}}
    Rectangle {
        id: panel
        objectName: "colorPickerPanel"
        x: (root.width-width)/2
        y: (root.height-height)/2
        width: Math.min(root.width-30,Style.space(430))
        height: content.implicitHeight+Style.space(32)
        color: Color.background
        border.color: Color.accent
        radius: Style.cornerRadius
        Keys.onEscapePressed: root.dismissed()
        Column {
            id:content
            anchors.centerIn:parent
            width:parent.width-Style.space(32)
            spacing:Style.space(12)
            Item {
                width:parent.width;height:Style.space(30)
                Text {anchors.verticalCenter:parent.verticalCenter;text:"Color";color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.subtitle;font.bold:true}
                MouseArea {
                    objectName:"colorPickerDrag"
                    anchors.fill:parent
                    cursorShape:Qt.SizeAllCursor
                    drag.target:panel
                    drag.minimumX:0;drag.maximumX:root.width-panel.width
                    drag.minimumY:0;drag.maximumY:root.height-panel.height
                }
            }
            Row {
                width:parent.width
                spacing:Style.space(14)
                Rectangle {
                    id:shade
                    width:parent.width-Style.space(40)
                    height:Style.space(210)
                    color:Qt.hsva(root.hue,1,1,1)
                    Rectangle {
                        anchors.fill:parent
                        rotation:0
                        gradient:Gradient {orientation:Gradient.Horizontal;GradientStop {position:0;color:"white"} GradientStop {position:1;color:"transparent"}}
                    }
                    Rectangle {
                        anchors.fill:parent
                        gradient:Gradient {GradientStop {position:0;color:"transparent"} GradientStop {position:1;color:"black"}}
                    }
                    Rectangle {
                        x:root.saturation*parent.width-width/2;y:(1-root.value)*parent.height-height/2
                        width:12;height:12;radius:6;color:"transparent";border.color:"white";border.width:2
                        Rectangle {anchors.fill:parent;anchors.margins:-1;radius:7;color:"transparent";border.color:"#303030"}
                    }
                    MouseArea {
                        objectName:"colorShade"
                        anchors.fill:parent;cursorShape:Qt.CrossCursor
                        function choose(mouse) {root.saturation=Math.max(0,Math.min(1,mouse.x/width));root.value=1-Math.max(0,Math.min(1,mouse.y/height));}
                        onPressed:function(mouse){choose(mouse)}
                        onPositionChanged:function(mouse){if(pressed)choose(mouse)}
                    }
                }
                Rectangle {
                    width:Style.space(24);height:shade.height
                    gradient:Gradient {
                        GradientStop {position:0;color:"#ff0000"}
                        GradientStop {position:1/6;color:"#ffff00"}
                        GradientStop {position:2/6;color:"#00ff00"}
                        GradientStop {position:3/6;color:"#00ffff"}
                        GradientStop {position:4/6;color:"#0000ff"}
                        GradientStop {position:5/6;color:"#ff00ff"}
                        GradientStop {position:1;color:"#ff0000"}
                    }
                    Rectangle {x:-3;y:root.hue*parent.height-3;width:parent.width+6;height:6;color:"transparent";border.color:"white";border.width:2}
                    MouseArea {
                        objectName:"colorHue"
                        anchors.fill:parent
                        function choose(mouse){root.hue=Math.max(0,Math.min(0.999999,mouse.y/height));}
                        onPressed:function(mouse){choose(mouse)}
                        onPositionChanged:function(mouse){if(pressed)choose(mouse)}
                    }
                }
            }
            Row {
                width:parent.width;spacing:Style.space(10)
                Rectangle {width:Style.space(44);height:Style.space(34);color:root.chosenColor;border.color:Color.muted}
                TextField {
                    id:hexInput
                    objectName:"colorHex"
                    width:Style.space(145)
                    placeholderText:"#RRGGBB"
                    onTextChanged: if (activeFocus && /^#[0-9a-fA-F]{6}$/.test(text)) root.setColor(Qt.color(text))
                }
            }
            Button {objectName:"colorEyedropper";width:parent.width;text:"Eyedropper from PDF";onClicked:root.eyedropperRequested()}
            Row {
                spacing:Style.space(8)
                Button {text:"Cancel";onClicked:root.dismissed()}
                Button {objectName:"applyColor";text:"Use color";selected:true;onClicked:root.accepted(root.hexColor)}
            }
        }
    }
}
