import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
    id: root
    required property var document
    signal submitted(string source)
    signal dismissed()
    color: Qt.rgba(0,0,0,0.55)
    MouseArea { anchors.fill:parent }
    Rectangle {
        anchors.centerIn:parent
        width:Math.min(parent.width-40,Style.space(620))
        height:content.implicitHeight+Style.space(40)
        color:Color.background; border.color:Color.accent; radius:Style.cornerRadius
        Column {
            id:content
            anchors.centerIn:parent; width:parent.width-Style.space(40); spacing:Style.space(12)
            Text { text:"Stamps"; color:Color.foreground; font.family:Style.font.family; font.pixelSize:Style.font.title }
            Grid {
                width:parent.width; columns:2; spacing:Style.space(12)
                Repeater {
                    model: [
                        {label:"APPROVED",color:"#4f6b43"},{label:"REJECTED",color:"#cc3b25"},
                        {label:"REVIEWED",color:"#2f5e8c"},{label:"DRAFT",color:"#8d8676"},
                        {label:"CONFIDENTIAL",color:"#cc3b25"},{label:"FINAL",color:"#211d17"},
                        {label:"RECEIVED",color:"#2f5e8c",dated:true},{label:"APPROVED",color:"#4f6b43",dated:true}
                    ]
                    delegate: Rectangle {
                        id:card
                        required property var modelData
                        required property int index
                        objectName:"stamp-"+index
                        width:(parent.width-parent.spacing)/2; height:Style.space(100)
                        color:"white"; radius:4
                        Canvas {
                            id:stamp
                            width:1000; height:330
                            scale:Math.min((parent.width-Style.space(20))/width,(parent.height-Style.space(20))/height)
                            transformOrigin:Item.TopLeft
                            x:(parent.width-width*scale)/2
                            y:(parent.height-height*scale)/2
                            onPaint:{
                                var ctx=getContext("2d");ctx.reset();
                                ctx.strokeStyle=card.modelData.color;ctx.fillStyle=card.modelData.color;
                                ctx.lineJoin="round";ctx.lineWidth=12;
                                function rounded(x,y,w,h,r) {
                                    ctx.beginPath();ctx.moveTo(x+r,y);ctx.lineTo(x+w-r,y);ctx.quadraticCurveTo(x+w,y,x+w,y+r);
                                    ctx.lineTo(x+w,y+h-r);ctx.quadraticCurveTo(x+w,y+h,x+w-r,y+h);ctx.lineTo(x+r,y+h);
                                    ctx.quadraticCurveTo(x,y+h,x,y+h-r);ctx.lineTo(x,y+r);ctx.quadraticCurveTo(x,y,x+r,y);ctx.closePath();ctx.stroke();
                                }
                                rounded(8,8,984,314,32);ctx.lineWidth=4;rounded(28,28,944,274,16);
                                ctx.font="bold 120px 'Nimbus Sans'";
                                var size=Math.min(120,120*880/ctx.measureText(card.modelData.label).width);
                                ctx.font="bold "+size+"px 'Nimbus Sans'";ctx.textAlign="center";ctx.textBaseline="middle";
                                ctx.fillText(card.modelData.label,500,card.modelData.dated?130:165);
                                if(card.modelData.dated){ctx.font="52px 'Nimbus Mono PS'";ctx.fillText(Qt.formatDate(new Date(),"MMM d, yyyy"),500,245);}
                            }
                        }
                        MouseArea { anchors.fill:parent; enabled:!root.document.busy; cursorShape:Qt.PointingHandCursor; onClicked:root.submitted(stamp.toDataURL("image/png")) }
                    }
                }
            }
            Text { width:parent.width; text:root.document.error; visible:text!==""; color:Color.urgent; wrapMode:Text.WordWrap; font.family:Style.font.family; font.pixelSize:Style.font.bodySmall }
            Button { text:root.document.busy?"Preparing stamp…":"Cancel"; enabled:!root.document.busy; onClicked:root.dismissed() }
        }
    }
}
