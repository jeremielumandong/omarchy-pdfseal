import QtQuick
import qs.Commons
import qs.Ui
Rectangle {
    id:root
    property string value:""
    signal accepted(string text)
    signal dismissed()
    color:Qt.rgba(0,0,0,0.5)
    onVisibleChanged:if(visible){input.text=value;input.forceActiveFocus();}
    MouseArea{anchors.fill:parent}
    Rectangle {
        anchors.centerIn:parent;width:Math.min(parent.width-40,Style.space(450));height:Style.space(280)
        color:Color.background;border.color:Color.accent;radius:Style.cornerRadius
        Column {
            anchors.fill:parent;anchors.margins:20;spacing:12
            Text{text:"Comment";color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.subtitle}
            Rectangle {
                width:parent.width;height:Style.space(145);color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.07)
                TextEdit {id:input;objectName:"noteInput";anchors.fill:parent;anchors.margins:10;color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.body;wrapMode:TextEdit.Wrap;textFormat:TextEdit.PlainText;selectByMouse:true;Keys.onEscapePressed:root.dismissed()}
            }
            Row{spacing:8;Button{text:"Cancel";onClicked:root.dismissed()} Button{objectName:"saveNote";text:"Save comment";selected:true;enabled:input.text.trim()!=="";onClicked:root.accepted(input.text)}}
        }
    }
}
