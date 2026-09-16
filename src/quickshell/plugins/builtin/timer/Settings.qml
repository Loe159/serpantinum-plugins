import QtQuick
import QtQuick.Controls
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

    function s(value) {
        return rootObj && rootObj.s ? rootObj.s(value) : value;
    }

    function pluginId() {
        return pluginMetadata && pluginMetadata.id ? pluginMetadata.id : "serpantinum.timer";
    }

    function settings() {
        return PluginManager.pluginSettings(pluginId());
    }

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

    function moduleId() {
        return PluginManager.barModuleId(pluginId());
    }

    function inBar() {
        return PluginManager.moduleIsPlaced(moduleId());
    }

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
        contentWidth: width
        contentHeight: content.implicitHeight + root.s(56)
        clip: true

        ColumnLayout {
            id: content
            width: parent.width - root.s(56)
            x: root.s(28)
            y: root.s(28)
            spacing: root.s(18)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(3)

                Text {
                    text: "Timer"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(28)
                    font.weight: Font.Black
                    color: ThemeBackend.text
                }

                Text {
                    text: "Configure the built-in countdown timer"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(12)
                    color: ThemeBackend.subtext0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: root.s(72)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.55)
                border.width: 1
                border.color: ThemeBackend.surface1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(14)

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

                    CheckBox {
                        checked: {
                            const dummy = root.configRevision;
                            return root.inBar();
                        }
                        onToggled: root.setInBar(checked)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: root.s(82)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.55)
                border.width: 1
                border.color: ThemeBackend.surface1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(14)
                    spacing: root.s(12)

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

                    SpinBox {
                        id: minutesSpin
                        from: 1
                        to: 1440
                        editable: true
                        value: {
                            const dummy = root.configRevision;
                            return root.defaultMinutes();
                        }
                        onValueModified: root.setDefaultMinutes(value)
                    }
                }
            }
        }
    }
}
