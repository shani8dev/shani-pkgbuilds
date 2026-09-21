/*
    SPDX-FileCopyrightText: 2026 Shani OS
    SPDX-License-Identifier: GPL-3.0-or-later

    Saturn splash screen, rebuilt on the proven Avalon-Splash structure
    (xkain / GPLv3) so it is guaranteed to render.  Saturn-specific:
    SHANI branding, coral accent (#ff7f50), translucent glass emblem,
    orbiting Saturn rings + moon, starfield, and a coral progress bar.
*/

import QtQuick
import QtQuick.Particles
import org.kde.kirigami as Kirigami

Image {
    id: root
    source: "images/background.png"
    property int stage

    // Fraction shown by the boot progress bar.
    property real bootProgress: Math.max(0.08, Math.min(1.0, (stage + 1) / 7.0))
    Behavior on progress {
        NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
    }

    // Keep the lower band readable for the progress bar.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 0.70; color: "#00000000" }
            GradientStop { position: 1.0; color: "#04060a99" }
        }
    }

    // Subtle starfield.
    ParticleSystem { id: stars }

    Emitter {
        anchors.fill: parent
        system: stars
        emitRate: 5
        lifeSpan: 5000
        size: 4
        endSize: 1
        velocity: AngleDirection { angle: 0; angleVariation: 360; magnitude: 0 }
    }

    ImageParticle {
        system: stars
        source: "images/star.svg"
        alpha: 0.35
        alphaVariation: 0.6
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        // ---- translucent glass emblem (more translucent) ----
        Item {
            id: emblem
            anchors.centerIn: parent
            width: 340
            height: 340

            // soft coral glow that breathes behind the logo
            property real pulse: 0.12

            Rectangle {
                id: glow
                anchors.centerIn: parent
                width: 190
                height: 190
                radius: width / 2
                color: "#ff7f50"
                opacity: emblem.pulse
            }

            SequentialAnimation {
                loops: Animation.Infinite
                running: Kirigami.Units.longDuration > 1
                NumberAnimation {
                    target: emblem
                    property: "pulse"
                    from: 0.04
                    to: 0.18
                    duration: 2400
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: emblem
                    property: "pulse"
                    from: 0.18
                    to: 0.04
                    duration: 2400
                    easing.type: Easing.InOutQuad
                }
            }

            // translucent glass disc
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(0.03, 0.05, 0.07, 0.18)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)
            }

            // orbiting Saturn ring
            Item {
                id: orbitRings
                anchors.fill: parent
                Image {
                    anchors.fill: parent
                    source: "images/rings.svg"
                    fillMode: Image.PreserveAspectFit
                }
                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 26000
                    loops: Animation.Infinite
                    running: true
                }
            }

            // orbiting moon
            Item {
                anchors.fill: parent
                Image {
                    anchors.fill: parent
                    source: "images/moon.svg"
                    fillMode: Image.PreserveAspectFit
                }
                RotationAnimator on rotation {
                    from: 0
                    to: -360
                    duration: 30000
                    loops: Animation.Infinite
                    running: true
                }
            }

            // SHANI logo, elastic pop-in
            Image {
                id: logo
                anchors.centerIn: parent
                source: "images/shanilogo.png"
                sourceSize.width: 140
                sourceSize.height: 140
                fillMode: Image.PreserveAspectFit

                NumberAnimation on scale {
                    from: 0
                    to: 1
                    duration: 1000
                    easing.type: Easing.OutElastic
                }
            }
        }

        // ---- wordmark ----
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: emblem.bottom
            anchors.topMargin: 22
            text: "SHANI"
            color: "white"
            font.family: "Noto Sans"
            font.pixelSize: 28
            font.weight: Font.Light
            font.letterSpacing: 14
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.5)
        }
    }

    // ---- boot progress bar ----
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        width: 280
        height: 4

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.18)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: height / 2
            color: "#ff7f50"
            width: parent.width * root.bootProgress
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: 1000
        easing.type: Easing.OutQuart
    }

    function reveal() {
        introAnimation.running = true
    }

    onStageChanged: if (stage >= 1) reveal()
    Component.onCompleted: reveal()
}
