import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    spacing: Style.marginM
    width: 700

    property var pluginApi: null
    property var widgetSettings: null

    property string valueCommand: widgetSettings.data.command !== undefined ? widgetSettings.data.command : ""
    property int valueInterval: widgetSettings.data.intervalSeconds !== undefined ? widgetSettings.data.intervalSeconds : 60

    function saveSettings() {
        widgetSettings.data.command = valueCommand
        widgetSettings.data.intervalSeconds = valueInterval
        widgetSettings.save()
    }

    NTextInput {
        Layout.fillWidth: true
        label: "command"
        description: "path to the usage executable, run with --json"
        placeholderText: "/path/to/usage"
        text: valueCommand
        onEditingFinished: {
            valueCommand = text
            saveSettings()
        }
    }

    NSpinBox {
        Layout.fillWidth: true
        label: "refresh interval"
        description: "seconds between fetches"
        value: valueInterval
        from: 10
        to: 3600
        stepSize: 10
        suffix: "s"
        onValueModified: {
            valueInterval = value
            saveSettings()
        }
    }
}
