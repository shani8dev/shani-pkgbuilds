import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root
    width: Screen.width
    height: Screen.height

    // Background - Saturn wallpaper
    Image {
        anchors.fill: parent
        source: "images/background.png"
        fillMode: Image.PreserveAspectCrop
    }

    // Subtle dark overlay for text readability
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 0.6; color: "#00000000" }
            GradientStop { position: 1.0; color: "#1a0f14cc" }
        }
    }

    // Saturn accent ring (decorative)
    Item {
        anchors.centerIn: parent
        width: 300; height: 300
        opacity: 0.08

        Item {
            anchors.centerIn: parent
            width: 280; height: 300
            transform: Rotation { axis { x: 1; y: 0; z: 0 } angle: 72 }
            RotationAnimator on rotation { from: 0; to: 360; duration: 20000; loops: Animation.Infinite }

            Rectangle { anchors.fill: parent; radius: 150; color: "transparent"; border.color: "#ff7f50"; border.width: 2; opacity: 0.3 }
            Rectangle { anchors.centerIn: parent; width: 260; height: 260; radius: 130; color: "transparent"; border.color: "#ff6e3c"; border.width: 1.5; opacity: 0.4 }
            Rectangle { anchors.centerIn: parent; width: 240; height: 240; radius: 120; color: "transparent"; border.color: "#ffb088"; border.width: 1; opacity: 0.25 }
        }
    }

    // Main content
    Column {
        anchors.centerIn: parent
        spacing: 24

        // Logo
        Image {
            source: "images/shanilogo.png"
            width: 180; height: 180
            sourceSize.width: 180; sourceSize.height: 180

            // Frosted glass frame
            Rectangle {
                anchors.centerIn: parent
                width: 220; height: 220
                radius: 110
                color: "#1a0f1480"
                border.color: "#ff7f50"
                border.width: 1
                opacity: 0.7
                layer.enabled: true
                layer.effect: FastBlur { radius: 16; transparentBorder: true }
            }

            ScaleAnimator {
                target: parent
                from: 0; to: 1; duration: 1000
                easing.type: Easing.OutElastic
            }
        }

        // Title
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "SHANI"
            font.family: "Noto Sans"
            font.pixelSize: 36
            font.weight: Font.Light
            font.letterSpacing: 16
            color: "#ffe4d4"
            opacity: 0
            OpacityAnimator on opacity { from: 0; to: 0.9; duration: 1500 }
        }

        // Subtitle
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Shani OS")
            font.family: "Noto Sans"
            font.pixelSize: 16
            font.weight: Font.Light
            font.letterSpacing: 8
            color: "#c4a898"
            opacity: 0
            OpacityAnimator on opacity { from: 0; to: 0.7; duration: 2000 }
        }

        // Login form
        PlasmaComponents.TextField {
            id: usernameField
            width: 320
            height: 48
            placeholderText: qsTr("Username")
            font.pixelSize: 14
            background: Rectangle {
                implicitWidth: 320; implicitHeight: 48
                radius: 8
                color: "#1a0f14cc"
                border.color: "#ff7f50"
                border.width: 1.5
                layer.enabled: true
                layer.effect: FastBlur { radius: 8; transparentBorder: true }
            }
            placeholderTextColor: "#8a8a8a"
            color: "#ffe4d4"
            selectionColor: "#ff7f50"
            font.family: "Noto Sans"
            font.pixelSize: 14
            padding: 12
        }

        PlasmaComponents.PasswordField {
            id: passwordField
            width: 320
            height: 48
            placeholderText: qsTr("Password")
            font.pixelSize: 14
            background: Rectangle {
                implicitWidth: 320; implicitHeight: 48
                radius: 8
                color: "#1a0f14cc"
                border.color: "#ff7f50"
                border.width: 1.5
                layer.enabled: true
                layer.effect: FastBlur { radius: 8; transparentBorder: true }
            }
            placeholderTextColor: "#8a8a8a"
            color: "#ffe4d4"
            selectionColor: "#ff7f50"
            font.family: "Noto Sans"
            font.pixelSize: 14
            padding: 12
        }

        // Login button
        PlasmaComponents.Button {
            width: 320
            height: 48
            text: qsTr("Login")
            font.family: "Noto Sans"
            font.pixelSize: 16
            font.weight: Font.Medium
            background: Rectangle {
                implicitWidth: 320; implicitHeight: 48
                radius: 8
                color: "#ff7f50"
                border.color: "#ff7f50"
                border.width: 2
            }
            contentItem: Text {
                text: parent.text
                font: parent.font
                color: "#1a0f14"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: {
                // Login logic handled by SDDM
            }
        }

        // Session selector
        PlasmaComponents.ComboBox {
            id: sessionCombo
            width: 320
            height: 40
            model: ["Plasma", "Plasma (Wayland)"]
            font.pixelSize: 13
            background: Rectangle {
                implicitWidth: 320; implicitHeight: 40
                radius: 6
                color: "#1a0f14cc"
                border.color: "#ff7f50"
                border.width: 1.5
            }
            contentItem: Text {
                text: modelData
                font.family: "Noto Sans"
                font.pixelSize: 13
                color: "#ffe4d4"
                padding: 8
            }
        }

        // Power buttons
        Row {
            spacing: 16
            PlasmaComponents.Button {
                text: qsTr("Shutdown")
                background: Rectangle { color: "transparent"; border.color: "#ff7f50"; border.width: 1.5; radius: 6 }
                contentItem: Text { text: parent.text; color: "#ff7f50"; font.family: "Noto Sans"; font.pixelSize: 13 }
                onClicked: Qt.quit()
            }
            PlasmaComponents.Button {
                text: qsTr("Reboot")
                background: Rectangle { color: "transparent"; border.color: "#ff7f50"; border.width: 1.5; radius: 6 }
                contentItem: Text { text: parent.text; color: "#ff7f50"; font.family: "Noto Sans"; font.pixelSize: 13 }
            }
        }
    }
}
