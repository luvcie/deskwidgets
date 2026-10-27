import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string command: ""
    property int intervalSeconds: 60
    property var windows: []
    property string status: "loading"
    property bool gotData: false

    function usageLevel(usedPercent) {
        if (usedPercent < 60) return "ok"
        if (usedPercent < 85) return "warn"
        return "high"
    }

    function windowLabel(mins) {
        if (mins >= 10080) return "weekly"
        if (mins >= 1440) return Math.round(mins / 1440) + "d"
        return Math.round(mins / 60) + "h"
    }

    function resetDate(s) {
        if (/^\d+$/.test(s)) return new Date(Number(s) * 1000)
        return new Date(s)
    }

    function fmtReset(d) {
        const mins = Math.max(0, Math.round((d.getTime() - Date.now()) / 60000))
        const days = Math.floor(mins / 1440)
        const h = Math.floor((mins % 1440) / 60)
        const m = mins % 60
        if (days > 0) return days + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    Process {
        id: proc
        command: root.command ? [root.command, "--json"] : []

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const reports = JSON.parse(text)
                    const codex = reports.find(r => r.provider === "codex")
                    if (!codex) throw new Error("no codex report")
                    root.windows = codex.windows
                    root.status = codex.status
                    root.gotData = true
                } catch (e) {
                    root.status = "error"
                }
            }
        }

        // a failed start (missing executable) never reaches the collector, so
        // running falling back to false is the only signal available
        onRunningChanged: {
            if (!running && !root.gotData) root.status = "error"
        }
    }

    function refresh() {
        root.gotData = false
        if (!root.command) {
            root.status = "unconfigured"
            return
        }
        if (proc.running) return
        proc.running = true
    }

    Timer {
        interval: root.intervalSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
