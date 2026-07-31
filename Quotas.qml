pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool hovered: false
    implicitWidth: rowLayout.implicitWidth + 8
    implicitHeight: Appearance.sizes.barHeight

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    property var quotasData: null
    property real avgRemaining: 1.0
    property bool isFetching: false
    readonly property string quotaScriptPath: FileUtils.trimFileProtocol(`${Qt.resolvedUrl("get-quotas.sh")}`)
    property string pendingStdout: ""
    property string pendingStderr: ""

    Process {
        id: fetchQuotasProcess
        command: [root.quotaScriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.pendingStdout = text;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                root.pendingStderr = text;
            }
        }
        onExited: function(exitCode, exitStatus) {
            try {
                if (exitCode === 0) {
                    const parsed = JSON.parse(root.pendingStdout);
                    root.quotasData = parsed;
                    root.avgRemaining = parsed.avgRemaining ?? 1.0;
                } else {
                    const diagnostic = root.pendingStderr.trim();
                    if (diagnostic.length > 0) {
                        console.error("Quota fetch failed:", diagnostic);
                    } else {
                        console.error("Quota fetch failed with exit code", exitCode);
                    }
                }
            } catch (e) {
                console.error("Failed to parse quotas JSON:\n", root.pendingStdout, e);
            } finally {
                root.pendingStdout = "";
                root.pendingStderr = "";
                root.isFetching = false;
            }
        }
    }

    onPressed: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            if (!root.isFetching) {
                root.isFetching = true;
                fetchQuotasProcess.running = true;
                try {
                    Quickshell.execDetached(["notify-send",
                        Translation.tr("Quotas"),
                        Translation.tr("Refreshing quotas...")
                        , "-a", "Shell"
                    ]);
                } catch (e) {
                    console.error("Failed to launch quota refresh notification:", e);
                }
            }
            mouse.accepted = false
        }
    }

    Component.onCompleted: {
        root.isFetching = true;
        fetchQuotasProcess.running = true;
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            iconName: "pie_chart"
            percentage: root.avgRemaining
            warning: root.avgRemaining <= 0.15
            Layout.alignment: Qt.AlignVCenter
        }
    }

    QuotasPopup {
        id: quotasPopup
        hoverTarget: root
        quotasData: root.quotasData
    }
}
