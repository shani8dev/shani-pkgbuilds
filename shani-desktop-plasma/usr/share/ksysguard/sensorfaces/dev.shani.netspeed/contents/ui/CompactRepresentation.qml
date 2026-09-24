/*
    SPDX-FileCopyrightText: 2026 Shani OS
    SPDX-License-Identifier: GPL-3.0-or-later

    Panel view: download over upload in two lines, each exactly half the bar
    tall (font sized from the bar, so both lines always fit), as narrow as
    one short label.
*/
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.ksysguard.faces as Faces

Faces.CompactSensorFace {
    id: root

    readonly property real rowHeight: Math.floor(height / 2)
    readonly property int pixelSize: Math.max(7, Math.round(rowHeight * 0.8))

    Layout.minimumWidth: content.width
    Layout.preferredWidth: content.width
    Layout.maximumWidth: content.width

    contentItem: Item {
        Column {
            id: content
            anchors.centerIn: parent
            spacing: 0
            Repeater {
                model: root.controller.highPrioritySensorIds.slice(0, 2)
                Rate {
                    required property string modelData
                    required property int index
                    height: root.rowHeight
                    font.pixelSize: root.pixelSize
                    sensorId: modelData
                    arrow: index === 0 ? "↓" : "↑"
                    // scheme colours (legible in light and dark): down = positive, up = accent
                    arrowColor: index === 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.highlightColor
                    updateRateLimit: root.controller.updateRateLimit
                }
            }
        }
    }
}
