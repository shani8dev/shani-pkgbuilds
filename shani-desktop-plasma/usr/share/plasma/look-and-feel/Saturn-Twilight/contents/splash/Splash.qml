/*
    SPDX-FileCopyrightText: 2026 Shani OS
    SPDX-License-Identifier: GPL-3.0-or-later

    Saturn splash screen. Same glass language as the Saturn desktop
    (Utterly-Round Plasma style + Kvantum): the look's own wallpaper,
    blurred (baked by build-splash.py) and dimmed, a frosted glass
    disc with the orbiting Saturn ring and moon, and the SHANI logo.
    Progress is Chronos: Shani is the lord of time, so the session's start
    is drawn as an orbit sweeping round Saturn past twelve hour-ticks, in
    the logo's own red-to-amber.

    ksplashqml sets `stage` 1..6 while the session starts. Keep every
    property referenced here real: a single QML error (e.g. a Behavior on
    a read-only property) makes KSplash show nothing at all - check with
    tests/render-splash.py after any edit.
*/

import QtQuick
import QtQuick.Particles
import org.kde.kirigami as Kirigami

Rectangle {
    id: root
    color: "#0c0a14"
    property int stage

    // Fraction shown by the boot progress bar (stages 1..6).
    property real bootProgress: Math.max(0.08, Math.min(1.0, (stage + 1) / 7.0))
    Behavior on bootProgress {
        NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
    }

    // ---- the look's wallpaper, frosted like the shell's blurred glass ----
    // (blur baked into images/background.png by build-splash.py - no shader
    // effect on the boot path)
    Image {
        anchors.fill: parent
        source: "images/background.png"
        fillMode: Image.PreserveAspectCrop
    }
    // scrim: keeps the emblem and bar legible on the light wallpaper too
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.02, 0.02, 0.05, 0.30) }
            GradientStop { position: 0.55; color: Qt.rgba(0.02, 0.02, 0.05, 0.42) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.02, 0.05, 0.62) }
        }
    }

    // ---- faint drifting stars ----
    ParticleSystem { id: stars }
    Emitter {
        anchors.fill: parent
        system: stars
        emitRate: 6
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

        Item {
            id: emblem
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Kirigami.Units.gridUnit
            width: 300
            height: 300

            // coral glow breathing behind the logo
            property real pulse: 0.14
            Rectangle {
                anchors.centerIn: parent
                width: 200
                height: 200
                radius: width / 2
                color: "#ff7f50"
                opacity: emblem.pulse
            }
            SequentialAnimation {
                loops: Animation.Infinite
                running: Kirigami.Units.longDuration > 1
                NumberAnimation { target: emblem; property: "pulse"; from: 0.06; to: 0.22; duration: 2400; easing.type: Easing.InOutQuad }
                NumberAnimation { target: emblem; property: "pulse"; from: 0.22; to: 0.06; duration: 2400; easing.type: Easing.InOutQuad }
            }

            // frosted glass disc (same edge treatment as the shell's glass)
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
            }

            // orbiting Saturn ring
            Image {
                anchors.fill: parent
                source: "images/rings.svg"
                fillMode: Image.PreserveAspectFit
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 26000
                    loops: Animation.Infinite; running: true
                }
            }
            // orbiting moon
            Image {
                anchors.fill: parent
                source: "images/moon.svg"
                fillMode: Image.PreserveAspectFit
                RotationAnimator on rotation {
                    from: 0; to: -360; duration: 30000
                    loops: Animation.Infinite; running: true
                }
            }

            // Chronos: the orbit of time. Canvas, not QtQuick.Shapes - it
            // also draws on the software renderer ksplash falls back to.
            Canvas {
                id: orbit
                anchors.centerIn: parent
                width: parent.width + 56
                height: parent.height + 56
                property real progress: root.bootProgress
                onProgressChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    var c = width / 2, r = width / 2 - 6
                    ctx.reset()
                    ctx.lineCap = "round"
                    // the hours
                    for (var i = 0; i < 12; i++) {
                        var a = i * Math.PI / 6 - Math.PI / 2
                        var passed = i / 12 <= progress
                        ctx.strokeStyle = passed ? Qt.rgba(1, 0.62, 0.35, 0.85) : Qt.rgba(1, 1, 1, 0.22)
                        ctx.lineWidth = i % 3 === 0 ? 3 : 2
                        var r0 = r + (i % 3 === 0 ? 6 : 4), r1 = r + 12
                        ctx.beginPath()
                        ctx.moveTo(c + r0 * Math.cos(a), c + r0 * Math.sin(a))
                        ctx.lineTo(c + r1 * Math.cos(a), c + r1 * Math.sin(a))
                        ctx.stroke()
                    }
                    // the track, then time elapsed in the logo's gradient
                    ctx.lineWidth = 3
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.14)
                    ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke()
                    var g = ctx.createLinearGradient(0, 0, width, height)
                    g.addColorStop(0, "#ef4136"); g.addColorStop(1, "#fbb040")
                    ctx.strokeStyle = g
                    ctx.beginPath()
                    ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * progress)
                    ctx.stroke()
                }
            }

            // SHANI logo (carries the wordmark itself), elastic pop-in
            Image {
                anchors.centerIn: parent
                source: "images/shanilogo.png"
                sourceSize.width: 150
                sourceSize.height: 150
                fillMode: Image.PreserveAspectFit
                NumberAnimation on scale {
                    from: 0; to: 1; duration: 1000
                    easing.type: Easing.OutElastic
                }
            }
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: 800
        easing.type: Easing.OutQuart
    }

    onStageChanged: if (stage >= 1) introAnimation.running = true
    Component.onCompleted: introAnimation.running = true
}
