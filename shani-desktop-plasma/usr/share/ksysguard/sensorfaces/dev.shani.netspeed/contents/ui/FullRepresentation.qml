/*
    SPDX-FileCopyrightText: 2026 Shani OS
    SPDX-License-Identifier: GPL-3.0-or-later

    Popup / desktop view: the same two lines at normal size.
*/
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.ksysguard.faces as Faces

Faces.SensorFace {
    id: root
    Layout.minimumWidth: Kirigami.Units.gridUnit * 6
    contentItem: Column {
        spacing: Kirigami.Units.smallSpacing
        Repeater {
            model: root.controller.highPrioritySensorIds.slice(0, 2)
            Rate {
                required property string modelData
                required property int index
                sensorId: modelData
                arrow: index === 0 ? "↓" : "↑"
                // scheme colours (legible in light and dark): down = positive, up = accent
                    arrowColor: index === 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.highlightColor
                updateRateLimit: root.controller.updateRateLimit
            }
        }
    }
}
