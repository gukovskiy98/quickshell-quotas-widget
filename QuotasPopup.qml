pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar

StyledPopup {
    id: root
    property var quotasData: null

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 12

        ColumnLayout {
            id: rowsLayout
            spacing: 16
            Layout.fillWidth: true

            Repeater {
                model: (root.quotasData && root.quotasData.quotas) ? root.quotasData.quotas : []

                delegate: ColumnLayout {
                    id: accountColumn
                    required property var modelData
                    required property int index
                    property var quotaAccount: modelData

                    Layout.fillWidth: true
                    spacing: 10

                    StyledPopupHeaderRow {
                        icon: "dns"
                        label: accountColumn.quotaAccount && accountColumn.quotaAccount.name ? accountColumn.quotaAccount.name.replace(".json", "") : ""
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Repeater {
                            model: (accountColumn.quotaAccount && accountColumn.quotaAccount.groups) ? accountColumn.quotaAccount.groups : []
                            
                            delegate: ColumnLayout {
                                id: groupColumn
                                required property var modelData
                                property var quotaGroup: modelData
                                Layout.fillWidth: true
                                spacing: 4
                                
                                StyledText {
                                    text: (groupColumn.quotaGroup && groupColumn.quotaGroup.name) ? groupColumn.quotaGroup.name : ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: (groupColumn.quotaGroup && groupColumn.quotaGroup.items) ? groupColumn.quotaGroup.items : []

                                        delegate: ColumnLayout {
                                            id: itemColumn
                                            required property var modelData
                                            property var quotaItem: modelData
                                            Layout.fillWidth: true
                                            spacing: 2

                                            StyledPopupValueRow {
                                                Layout.fillWidth: true
                                                icon: (itemColumn.quotaItem && itemColumn.quotaItem.icon) ? itemColumn.quotaItem.icon : "pie_chart"
                                                label: (itemColumn.quotaItem && itemColumn.quotaItem.label) ? (itemColumn.quotaItem.label + ":") : ""
                                                value: (itemColumn.quotaItem && itemColumn.quotaItem.val) ? itemColumn.quotaItem.val : ""
                                            }

                                            StyledText {
                                                visible: Boolean(itemColumn.quotaItem && itemColumn.quotaItem.resetTime)
                                                text: "↳ " + ((itemColumn.quotaItem && itemColumn.quotaItem.resetPrefix) ? (itemColumn.quotaItem.resetPrefix + " ") : "Refresh in ") + ((itemColumn.quotaItem && itemColumn.quotaItem.resetTime) ? itemColumn.quotaItem.resetTime : "")
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnSurfaceVariant
                                                Layout.leftMargin: 28
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Separator between accounts
                    Rectangle {
                        visible: accountColumn.index < ((root.quotasData && root.quotasData.quotas) ? root.quotasData.quotas.length - 1 : 0)
                        Layout.fillWidth: true
                        height: 1
                        color: Appearance.colors.colOutlineVariant
                        Layout.topMargin: 4
                    }
                }
            }
        }

        StyledText {
            visible: !root.quotasData || !root.quotasData.quotas || root.quotasData.quotas.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("No quota data available")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Last refresh: %1").arg(root.quotasData && root.quotasData.lastUpdated ? root.quotasData.lastUpdated : "--:--")
            font {
                weight: Font.Medium
                pixelSize: Appearance.font.pixelSize.smaller
            }
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
