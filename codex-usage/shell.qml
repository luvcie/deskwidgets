import Quickshell
import Quickshell.Wayland
import QtQuick
import "core"

ShellRoot {
    id: shell

    property string usageCommand: ""
    property int usageIntervalSeconds: 60

    PanelWindow {
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-desktop-widget"
        color: "transparent"

        CodexUsageData {
            id: usageData
            command: shell.usageCommand
            intervalSeconds: shell.usageIntervalSeconds
        }

        Rectangle {
            id: card
            x: 40
            y: 40
            width: 260
            height: 172
            radius: 16
            color: "#d014181d"
            border.color: "#33ffffff"
            border.width: 1

            function levelColor(level) {
                if (level === "ok") return "#7ac97f"
                if (level === "warn") return "#e0b34a"
                return "#e0654a"
            }

            function statusColor() {
                if (usageData.status === "ok") return "#7ac97f"
                if (usageData.status === "loading") return "#9098a0"
                return "#e0654a"
            }

            function statusText() {
                if (usageData.status === "ok") return "codex usage"
                if (usageData.status === "loading") return "codex ..."
                if (usageData.status === "unconfigured") return "codex (set usageCommand in shell.qml)"
                return "codex (" + usageData.status + ")"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.OpenHandCursor
                onPositionChanged: (mouse) => {
                    if (mouse.buttons & Qt.LeftButton) {
                        card.x += mouse.x - card.width / 2
                        card.y += mouse.y - card.height / 2
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Row {
                    spacing: 6
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: card.statusColor()
                    }
                    Text {
                        text: card.statusText()
                        color: "#e8e8e8"
                        font.family: "FiraCode Nerd Font Mono"
                        font.pointSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Repeater {
                    model: usageData.windows

                    delegate: Column {
                        spacing: 4

                        Row {
                            spacing: 8
                            Text {
                                text: usageData.windowLabel(modelData.window_minutes)
                                color: "#9098a0"
                                font.family: "FiraCode Nerd Font Mono"
                                font.pointSize: 9
                                width: 52
                            }
                            Text {
                                text: Math.round(modelData.used_percent) + "% used"
                                color: card.levelColor(usageData.usageLevel(modelData.used_percent))
                                font.family: "FiraCode Nerd Font Mono"
                                font.pointSize: 9
                            }
                        }

                        Rectangle {
                            width: 228
                            height: 6
                            radius: 3
                            color: "#22ffffff"

                            Rectangle {
                                width: parent.width * Math.min(modelData.used_percent, 100) / 100
                                height: parent.height
                                radius: 3
                                color: card.levelColor(usageData.usageLevel(modelData.used_percent))
                            }
                        }

                        Text {
                            text: "resets in " + usageData.fmtReset(usageData.resetDate(modelData.resets_at))
                            color: "#9098a0"
                            font.family: "FiraCode Nerd Font Mono"
                            font.pointSize: 9
                        }
                    }
                }
            }
        }
    }
}
