pragma ComponentBehavior: Bound

import qs.modules.common
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

    Process {
        id: fetchQuotasProcess
        command: [
            "bash", "-c",
            "API_URL=$(secret-tool lookup application quotas key quotasApiUrl) MANAGEMENT_KEY=$(secret-tool lookup application quotas key quotasManagementKey) ~/.bun/bin/bun run /home/ngukovskiy/.config/quickshell/ii/modules/ii/bar/get-quotas.ts"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (text.trim().length > 0) {
                        let parsed = JSON.parse(text);
                        root.quotasData = parsed;
                        root.avgRemaining = parsed.avgRemaining ?? 1.0;
                    }
                } catch (e) {
                    console.error("Failed to parse quotas JSON:\n", text);
                }
                root.isFetching = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    console.log("Quotas Widget Stderr:", text);
                }
            }
        }
        onExited: {
            root.isFetching = false;
        }
    }

    onPressed: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            if (!root.isFetching) {
                root.isFetching = true;
                fetchQuotasProcess.running = true;
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Quotas"),
                    Translation.tr("Refreshing quotas...")
                    , "-a", "Shell"
                ]);
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
