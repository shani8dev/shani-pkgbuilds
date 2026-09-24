/*
    SPDX-FileCopyrightText: 2026 Shani OS
    SPDX-License-Identifier: GPL-3.0-or-later

    One compact rate line: a coloured arrow right beside the rate in short
    units (0k, 12k, 1.2M, 34M). The line reserves the width of its widest
    possible value ("888k") and right-aligns, so the panel never shifts as
    the rate changes and the arrow always sits next to its number.
*/
import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

QQC2.Label {
    id: line
    property string sensorId
    property color arrowColor
    property string arrow
    property int updateRateLimit

    Sensors.Sensor {
        id: sensor
        sensorId: line.sensorId
        updateRateLimit: line.updateRateLimit
    }

    // bytes per second -> short text; one decimal only below 10 of a unit
    function shortRate(v) {
        const units = ["B", "k", "M", "G", "T"]  // lowercase k: "0k", not "0K" which reads as "OK"
        let i = 0
        v = Math.max(0, Number(v) || 0)
        while (v >= 1000 && i < units.length - 1) { v /= 1024; i++ }
        if (i === 0) return "0k"            // sub-kilobyte: noise, not news
        return (v < 10 ? v.toFixed(1) : Math.round(v)) + units[i]
    }

    TextMetrics { id: widest; font: line.font; text: line.arrow + " 888k" }

    textFormat: Text.StyledText
    horizontalAlignment: Text.AlignRight
    verticalAlignment: Text.AlignVCenter
    width: Math.ceil(widest.width)
    text: "<font color='" + arrowColor + "'>" + arrow + "</font> " + shortRate(sensor.value)
}
