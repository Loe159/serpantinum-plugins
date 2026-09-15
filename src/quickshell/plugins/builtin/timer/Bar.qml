import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var host: null

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    readonly property var timer: host ? host.pluginInstance : null
    readonly property color accent: timer && timer.counting ? host.theme.green : (host ? host.theme.mauve : "#cba6f7")

    GridLayout {
        id: content
        anchors.centerIn: parent
        columns: host && host.vertical ? 1 : 2
        rows: host && host.vertical ? 2 : 1
        rowSpacing: host ? host.s(1) : 1
        columnSpacing: host ? host.s(6) : 6

        Text {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            text: timer ? timer.topbarIcon : "󰔛"
            font.family: "Iosevka Nerd Font"
            font.pixelSize: host ? host.s(host.compact ? 11 : 12) : 12
            color: root.accent

            Behavior on color { ColorAnimation { duration: 220 } }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            text: timer ? timer.topbarText : "05:00"
            font.family: host ? host.theme.fontFamily : "sans-serif"
            font.pixelSize: host ? host.s(host.compact ? 12 : 13) : 13
            font.weight: Font.Bold
            color: root.accent

            Behavior on color { ColorAnimation { duration: 220 } }
        }
    }
}
