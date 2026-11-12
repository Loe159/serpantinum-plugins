import QtQuick
import QtQuick.Layouts
import "../../../"
import "../../../reusables"

Item {
    id: root

    property var pluginMetadata: ({})
    property string pluginDirectory: ""
    property var pluginInstance: null
    property var hostServices: null
    property var rootObj: null
    property int configRevision: 0

    function s(value) { return rootObj && rootObj.s ? rootObj.s(value) : value; }
    function pluginId() { return pluginMetadata && pluginMetadata.id ? pluginMetadata.id : "serpantinum.timer"; }
    function settings() { return PluginManager.pluginSettings(pluginId()); }
    function defaultMinutes() {
        const seconds = Number(settings().defaultSeconds || 300);
        return Math.max(1, Math.round(seconds / 60));
    }
    function setDefaultMinutes(minutes) {
        const seconds = Math.max(60, Number(minutes) * 60);
        PluginManager.updatePluginSetting(pluginId(), "defaultSeconds", seconds);
        if (pluginInstance) {
            const previous = pluginInstance.defaultSeconds;
            pluginInstance.defaultSeconds = seconds;
            if (!pluginInstance.counting && pluginInstance.remainingSeconds === previous)
                pluginInstance.remainingSeconds = seconds;
        }
        configRevision++;
    }
    function moduleId() { return PluginManager.barModuleId(pluginId()); }
    function inBar() { return PluginManager.moduleIsPlaced(moduleId()); }
    function setInBar(enabled) {
        PluginManager.setBarModuleEnabled(moduleId(), enabled, "center");
        configRevision++;
    }

    Connections {
        target: Config
        function onSettingsLoaded() { root.configRevision++; }
        function onRawSettingsChanged() { root.configRevision++; }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: root.s(8)
        contentWidth: width
        contentHeight: settingsCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: root.s(6)

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: barRow.implicitHeight + root.s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.4)

                RowLayout {
                    id: barRow
                    anchors.left: parent.left
                    anchors.leftMargin: root.s(14)
                    anchors.right: parent.right
                    anchors.rightMargin: root.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(12)

                    IconButton {
                        enabled: false
                        size: root.s(32)
                        Layout.preferredWidth: root.s(32)
                        Layout.preferredHeight: root.s(32)
                        Layout.alignment: Qt.AlignVCenter
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: "󰔛"
                        iconFontSize: root.s(16)
                        accentColor: ThemeBackend.surface0
                        textColor: "#ffffff"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.s(2)
                        Text {
                            text: "Show in the Bar"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(13)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: "Add or remove the Timer module from the center section"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: {
                            const dummy = root.configRevision;
                            return root.inBar();
                        }
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(val) { root.setInBar(val); }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: durationRow.implicitHeight + root.s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.4)

                RowLayout {
                    id: durationRow
                    anchors.left: parent.left
                    anchors.leftMargin: root.s(14)
                    anchors.right: parent.right
                    anchors.rightMargin: root.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(12)

                    IconButton {
                        enabled: false
                        size: root.s(32)
                        Layout.preferredWidth: root.s(32)
                        Layout.preferredHeight: root.s(32)
                        Layout.alignment: Qt.AlignVCenter
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: "󰅐"
                        iconFontSize: root.s(16)
                        accentColor: ThemeBackend.surface0
                        textColor: "#ffffff"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.s(2)
                        Text {
                            text: "Default duration"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(13)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: "Initial timer duration in minutes"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    NumberSelector {
                        id: minutesSelector
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitWidth: root.s(150)
                        implicitHeight: root.s(32)
                        from: 1
                        to: 1440
                        stepSize: 1
                        decimals: 0
                        suffix: " min"
                        value: {
                            const dummy = root.configRevision;
                            return root.defaultMinutes();
                        }
                        baseColor: ThemeBackend.surface0
                        accentColor: ThemeBackend.mauve
                        buttonColor: ThemeBackend.surface1
                        buttonTextColor: ThemeBackend.text
                        textColor: ThemeBackend.text
                        subTextColor: ThemeBackend.subtext0
                        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                        cornerRadius: ThemeBackend.borderRadius
                        fontFamily: ThemeBackend.fontFamily
                        fontPixelSize: root.s(11)
                        onTriggered: root.setDefaultMinutes(Math.round(value))
                    }
                }
            }
        }
    }
}
