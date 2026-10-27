import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.UI
import qs.Widgets
import "core"

DraggableDesktopWidget {
    id: root

    defaultX: 40
    defaultY: 40

    property var pluginApi: null

    readonly property var defaults: DesktopWidgetRegistry.widgetMetadata["plugin:codex-usage"] ?? {}

    CodexUsageData {
        id: usageData
        command: root.widgetData?.command !== undefined ? root.widgetData.command : root.defaults.command ?? ""
        intervalSeconds: root.widgetData?.intervalSeconds !== undefined ? root.widgetData.intervalSeconds : root.defaults.intervalSeconds ?? 60
    }

    function levelColor(level) {
        if (level === "ok") return Color.mTertiary
        if (level === "warn") return Color.mPrimary
        return Color.mError
    }

    width: Math.round(230 * root.widgetScale)
    height: Math.round(150 * root.widgetScale)

    Column {
        anchors.fill: parent
        anchors.margins: Math.round(Style.marginL * root.widgetScale)
        spacing: Math.round(Style.marginM * root.widgetScale)

        Row {
            spacing: Math.round(6 * root.widgetScale)
            Rectangle {
                width: Math.round(8 * root.widgetScale)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: usageData.status === "ok" ? Color.mTertiary : usageData.status === "loading" ? Color.mOnSurfaceVariant : Color.mError
            }
            NText {
                text: usageData.status === "ok" ? "codex usage"
                    : usageData.status === "loading" ? "codex ..."
                    : usageData.status === "unconfigured" ? "codex (set the command in settings)"
                    : "codex (" + usageData.status + ")"
                pointSize: Style.fontSizeM
                color: Color.mOnSurface
                font.weight: Style.fontWeightBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Repeater {
            model: usageData.windows

            delegate: Column {
                spacing: Math.round(4 * root.widgetScale)

                Row {
                    spacing: Math.round(8 * root.widgetScale)
                    NText {
                        text: usageData.windowLabel(modelData.window_minutes)
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurfaceVariant
                        width: Math.round(52 * root.widgetScale)
                    }
                    NText {
                        text: Math.round(modelData.used_percent) + "% used"
                        pointSize: Style.fontSizeS
                        color: root.levelColor(usageData.usageLevel(modelData.used_percent))
                    }
                }

                Rectangle {
                    width: root.width - 2 * Math.round(Style.marginL * root.widgetScale)
                    height: Math.round(5 * root.widgetScale)
                    radius: height / 2
                    color: Qt.alpha(Color.mOnSurface, 0.12)

                    Rectangle {
                        width: parent.width * Math.min(modelData.used_percent, 100) / 100
                        height: parent.height
                        radius: height / 2
                        color: root.levelColor(usageData.usageLevel(modelData.used_percent))
                    }
                }

                NText {
                    text: "resets in " + usageData.fmtReset(usageData.resetDate(modelData.resets_at))
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                }
            }
        }
    }
}
