import QtQuick
import QtQuick.Layouts

Item {
    Row {
        BarGroup {
            id: leftCenterGroup

            Resources {
                alwaysShowAllResources: root.useShortenedForm === 2
                Layout.fillWidth: root.useShortenedForm === 2
            }

            Media {
                Layout.fillWidth: true
            }
        }
    }
}
