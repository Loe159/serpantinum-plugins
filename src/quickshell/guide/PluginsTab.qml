import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../"
import "../reusables"

Item {
    id: pluginsRoot

    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)
    property string installUrl: ""
    property int configRevision: 0

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    Connections {
        target: Config
        function onSettingsLoaded() { pluginsRoot.configRevision++ }
        function onRawSettingsChanged() { pluginsRoot.configRevision++ }
    }

    Connections {
        target: PluginManager
        function onRefreshed(count) { pluginsRoot.configRevision++ }
        function onInstallFinished(success, message) {
            if (success) pluginsRoot.installUrl = "";
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: rootObj.s(28)
        spacing: rootObj.s(18)

        RowLayout {
            Layout.fillWidth: true
            spacing: rootObj.s(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: rootObj.s(3)

                Text {
                    text: "Plugins"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(28)
                    font.weight: Font.Black
                    color: ThemeBackend.text
                }

                Text {
                    text: "Install and manage extensions loaded by Serpantinum"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(12)
                    color: ThemeBackend.subtext0
                }
            }

            Rectangle {
                implicitWidth: countText.implicitWidth + rootObj.s(20)
                implicitHeight: rootObj.s(30)
                radius: ThemeBackend.borderRadius
                color: ThemeBackend.surface0

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: PluginManager.plugins.length + (PluginManager.plugins.length === 1 ? " plugin" : " plugins")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(11)
                    font.weight: Font.Bold
                    color: ThemeBackend.subtext1
                }
            }

            ClickButton {
                implicitHeight: rootObj.s(32)
                buttonText: PluginManager.scanning ? "Scanning…" : "Refresh"
                buttonIcon: "󰑐"
                iconFontSize: rootObj.s(14)
                accentColor: ThemeBackend.surface0
                textColor: ThemeBackend.text
                enabled: !PluginManager.scanning && !PluginManager.installing
                onClicked: PluginManager.refresh()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: rootObj.s(112)
            radius: ThemeBackend.borderRadius
            color: Qt.alpha(ThemeBackend.surface0, 0.55)
            border.width: 1
            border.color: ThemeBackend.surface1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: rootObj.s(14)
                spacing: rootObj.s(10)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(10)

                    Text {
                        text: "󰏔"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: rootObj.s(18)
                        color: ThemeBackend.mauve
                    }

                    Text {
                        text: "Install from Git"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(14)
                        font.weight: Font.Bold
                        color: ThemeBackend.text
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "plugin.json must be at the repository root"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(10)
                        color: ThemeBackend.overlay1
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(10)

                    Input {
                        Layout.fillWidth: true
                        implicitHeight: rootObj.s(36)
                        text: pluginsRoot.installUrl
                        placeholderText: "https://github.com/user/serpantinum-plugin.git"
                        leadingIcon: "󰊢"
                        baseColor: ThemeBackend.base
                        borderColor: ThemeBackend.surface1
                        accentColor: ThemeBackend.blue
                        textColor: ThemeBackend.text
                        subTextColor: ThemeBackend.overlay1
                        isBusy: PluginManager.installing
                        onTextEdited: newText => pluginsRoot.installUrl = newText
                        onAccepted: {
                            if (!PluginManager.installing && pluginsRoot.installUrl.trim() !== "") {
                                PluginManager.installFromGit(pluginsRoot.installUrl)
                            }
                        }
                    }

                    ClickButton {
                        implicitWidth: rootObj.s(118)
                        implicitHeight: rootObj.s(36)
                        buttonText: PluginManager.installing ? "Installing…" : "Install"
                        buttonIcon: PluginManager.installing ? "󰑐" : "󰐕"
                        accentColor: PluginManager.installing ? ThemeBackend.surface1 : ThemeBackend.mauve
                        textColor: PluginManager.installing ? ThemeBackend.subtext0 : ThemeBackend.crust
                        enabled: !PluginManager.installing && pluginsRoot.installUrl.trim() !== ""
                        onClicked: PluginManager.installFromGit(pluginsRoot.installUrl)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: PluginManager.installMessage !== ""
                    text: PluginManager.installMessage
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(10)
                    color: PluginManager.installing
                        ? ThemeBackend.peach
                        : (PluginManager.installSucceeded ? ThemeBackend.green : ThemeBackend.red)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: pluginList
                anchors.fill: parent
                contentWidth: width
                contentHeight: pluginColumn.implicitHeight + rootObj.s(8)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: pluginList.moving || pluginList.movingVertically
                    width: rootObj.s(4)
                    contentItem: Rectangle {
                        implicitWidth: rootObj.s(4)
                        radius: rootObj.s(2)
                        color: ThemeBackend.surface2
                    }
                }

                ColumnLayout {
                    id: pluginColumn
                    width: pluginList.width - (pluginList.contentHeight > pluginList.height ? rootObj.s(8) : 0)
                    spacing: rootObj.s(10)

                    Repeater {
                        model: PluginManager.plugins

                        delegate: Rectangle {
                            id: pluginCard
                            required property var modelData
                            property var pluginData: modelData
                            property bool pluginEnabled: {
                                const dummy = pluginsRoot.configRevision;
                                return PluginManager.isEnabled(pluginData);
                            }
                            property bool topbarSupported: PluginManager.supportsTopbar(pluginData)
                            property bool topbarEnabled: {
                                const dummy = pluginsRoot.configRevision;
                                return PluginManager.isTopbarEnabled(pluginData);
                            }

                            Layout.fillWidth: true
                            implicitHeight: topbarSupported ? rootObj.s(116) : rootObj.s(86)
                            radius: ThemeBackend.borderRadius
                            color: pluginMouse.hovered
                                ? Qt.alpha(ThemeBackend.surface1, 0.62)
                                : Qt.alpha(ThemeBackend.surface0, 0.42)
                            border.width: 1
                            border.color: pluginEnabled ? Qt.alpha(ThemeBackend.mauve, 0.55) : ThemeBackend.surface1

                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            HoverHandler { id: pluginMouse }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: rootObj.s(13)
                                spacing: rootObj.s(8)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: rootObj.s(12)

                                    Rectangle {
                                        Layout.preferredWidth: rootObj.s(42)
                                        Layout.preferredHeight: rootObj.s(42)
                                        radius: ThemeBackend.borderRadius
                                        color: pluginCard.pluginEnabled ? Qt.alpha(ThemeBackend.mauve, 0.18) : ThemeBackend.surface0

                                        Text {
                                            anchors.centerIn: parent
                                            text: pluginCard.pluginData.icon || "󰏗"
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: rootObj.s(20)
                                            color: pluginCard.pluginEnabled ? ThemeBackend.mauve : ThemeBackend.overlay1
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: rootObj.s(8)

                                            Text {
                                                text: pluginCard.pluginData.name || pluginCard.pluginData.id
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(14)
                                                font.weight: Font.Bold
                                                color: ThemeBackend.text
                                            }

                                            Rectangle {
                                                implicitWidth: versionText.implicitWidth + rootObj.s(12)
                                                implicitHeight: rootObj.s(20)
                                                radius: rootObj.s(10)
                                                color: ThemeBackend.surface1

                                                Text {
                                                    id: versionText
                                                    anchors.centerIn: parent
                                                    text: "v" + (pluginCard.pluginData.version || "0")
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(9)
                                                    font.weight: Font.Bold
                                                    color: ThemeBackend.subtext0
                                                }
                                            }

                                            Rectangle {
                                                implicitWidth: sourceText.implicitWidth + rootObj.s(12)
                                                implicitHeight: rootObj.s(20)
                                                radius: rootObj.s(10)
                                                color: pluginCard.pluginData._source === "builtin"
                                                    ? Qt.alpha(ThemeBackend.blue, 0.16)
                                                    : Qt.alpha(ThemeBackend.green, 0.16)

                                                Text {
                                                    id: sourceText
                                                    anchors.centerIn: parent
                                                    text: pluginCard.pluginData._source === "builtin" ? "Built-in" : "User"
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(9)
                                                    font.weight: Font.Bold
                                                    color: pluginCard.pluginData._source === "builtin" ? ThemeBackend.blue : ThemeBackend.green
                                                }
                                            }

                                            Item { Layout.fillWidth: true }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: pluginCard.pluginData.description || pluginCard.pluginData.id
                                            elide: Text.ElideRight
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(10)
                                            color: ThemeBackend.subtext0
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: pluginCard.pluginData.id
                                            elide: Text.ElideRight
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: rootObj.s(9)
                                            color: ThemeBackend.overlay0
                                        }
                                    }

                                    Toggle {
                                        buttonText: pluginCard.pluginEnabled ? "Enabled" : "Disabled"
                                        checked: pluginCard.pluginEnabled
                                        accentColor: ThemeBackend.green
                                        baseColor: ThemeBackend.surface1
                                        handleColor: ThemeBackend.crust
                                        handleOffColor: ThemeBackend.overlay1
                                        textColor: ThemeBackend.text
                                        onToggled: checked => PluginManager.setEnabled(pluginCard.pluginData.id, checked)
                                    }
                                }

                                RowLayout {
                                    visible: pluginCard.topbarSupported
                                    Layout.fillWidth: true
                                    Layout.leftMargin: rootObj.s(54)
                                    spacing: rootObj.s(8)

                                    Text {
                                        text: "󰍜"
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: rootObj.s(13)
                                        color: ThemeBackend.blue
                                    }

                                    Text {
                                        text: "Show in top bar"
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                        font.weight: Font.Bold
                                        color: pluginCard.pluginEnabled ? ThemeBackend.subtext1 : ThemeBackend.overlay0
                                    }

                                    Item { Layout.fillWidth: true }

                                    Toggle {
                                        checked: pluginCard.topbarEnabled
                                        enabled: pluginCard.pluginEnabled
                                        accentColor: ThemeBackend.blue
                                        baseColor: ThemeBackend.surface1
                                        handleColor: ThemeBackend.crust
                                        handleOffColor: ThemeBackend.overlay1
                                        onToggled: checked => PluginManager.setTopbarEnabled(pluginCard.pluginData.id, checked)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: PluginManager.plugins.length === 0 && !PluginManager.scanning
                        Layout.fillWidth: true
                        implicitHeight: rootObj.s(100)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.surface0, 0.35)

                        Column {
                            anchors.centerIn: parent
                            spacing: rootObj.s(6)

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰏗"
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: rootObj.s(24)
                                color: ThemeBackend.overlay1
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "No plugins found"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(12)
                                color: ThemeBackend.subtext0
                            }
                        }
                    }

                    Text {
                        visible: PluginManager.lastError !== ""
                        Layout.fillWidth: true
                        Layout.topMargin: rootObj.s(4)
                        text: PluginManager.lastError
                        wrapMode: Text.Wrap
                        font.family: "JetBrains Mono"
                        font.pixelSize: rootObj.s(9)
                        color: ThemeBackend.red
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Plugins are trusted code and run with the same user privileges as Serpantinum. Install only repositories you trust."
            wrapMode: Text.Wrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(9)
            color: ThemeBackend.overlay0
        }
    }
}
