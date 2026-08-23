import QtQuick
import QtQuick.Particles

Item {
    id: root
    property int stage

    Image {
        anchors.fill: parent
        source: "images/background.png"
        fillMode: Image.PreserveAspectCrop
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 0.65; color: "#00000000" }
            GradientStop { position: 1.0; color: "#0a1420aa" }
        }
    }

    ParticleSystem { id: ps }

    Emitter {
        anchors.fill: parent
        system: ps
        emitRate: 6
        lifeSpan: 4000
        size: 5
        endSize: 1
        velocity: AngleDirection { angle: 0; angleVariation: 360; magnitude: 0 }
        x: Math.random() * parent.width
        y: Math.random() * parent.height * 0.7
    }

    ImageParticle {
        system: ps
        source: "images/star.svg"
        alpha: 0.0
        alphaVariation: 0.9
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        Item {
            id: logoContainer
            anchors.centerIn: parent
            width: 340; height: 340

            Rectangle {
                anchors.centerIn: parent
                width: 320; height: 320
                radius: 160
                color: "transparent"
                border.color: "#01edd5"
                border.width: 2
                opacity: 0.25
            }

            Item {
                anchors.centerIn: parent
                width: 300; height: 300
                transform: Rotation { axis { x: 1; y: 0; z: 1 } angle: 72 }
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 8000
                    loops: Animation.Infinite
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 150
                    color: "transparent"
                    border.color: "#01edd5"
                    border.width: 3
                    opacity: 0.85
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 278; height: 278
                    radius: 139
                    color: "transparent"
                    border.color: "#40f5df"
                    border.width: 2
                    opacity: 0.55
                }
                Rectangle {
                    anchors.centerIn:(parent)
                    width: 256; height: 256
                    radius: 128
                    color: "transparent"
                    border.color: "#01edd5"
                    border.width: 1
                    opacity: 0.35
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 190; height: 190
                radius: 95
                color: "#0a1a2080"
                border.color: "#01edd5"
                border.width: 1
                opacity: 0.65
            }

            Item {
                anchors.centerIn: parent
                width: 170; height: 170

                Rectangle {
                    id: glow
                    anchors.centerIn: parent
                    width: 150; height: 150
                    radius: 75
                    color: "#01edd5"
                    opacity: glowAnim.value * 0.12
                }

                SequentialAnimation on running:true {
                    NumberAnimation { target:glowAnim; property:"value"; from:0.3; to:1; duration:2000; easing.type:Easing.InOutQuad }
                    NumberAnimation { target:glowAnim; property:"value"; from:1; to:0.3; duration:2000; easing.type:Easing.InOutQuad }
                }
                QtObject { id: glowAnim; property real value: 0.5 }

                Image {
                    id: logo
                    anchors.centerIn: parent
                    source: "images/shanilogo.png"
                    sourceSize.width: 140; sourceSize.height: 140
                    ParallelAnimation {
                        running: true
                        ScaleAnimator { target:logo; from:0; to:1; duration:900; easing.type:Easing.OutElastic }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: logoContainer.bottom
            anchors.topMargin: 28
            text: "SHANI"
            font.family: "Noto Sans"
            font.pixelSize: 30
            font.weight: Font.Light
            font.letterSpacing: 14
            color: "#d0f5ef"
            OpacityAnimator on opacity { from:0; to:0.8; duration:2000 }
        }
    }

    Item {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: 60; width: 240
        anchors.bottomMargin: 24

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 240; height: 3
            radius: 1.5
            color: "#ffffff25"
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: 3; width: pAnim.value
                radius: 1.5
                color: "#01edd5"
            }
        }
        NumberAnimation { id:pAnim; target:this; property:"value"; from:0; to:240; duration:3500; loops:Animation.Infinite; running:true; easing.type:Easing.InOutCubic }
        QtObject { id:pAnim; property real value: 0 }
    }

    OpacityAnimator {
        id: introAnimation; running:false; target:content
        from:0; to:1; duration:1000; easing.type:Easing.OutQuart
    }

    onStageChanged: if (stage == 1) introAnimation.running = true
}
