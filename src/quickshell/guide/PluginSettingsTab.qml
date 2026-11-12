import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../"

Item {
    id: root

    required property var rootObj
    required property int tabIndex
    required property int subTabIndex
    required property string pluginId

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex && rootObj.currentSubTab === subTabIndex

    readonly property var pluginData: PluginManager.pluginById(pluginId)

    Loader {
        id: settingsLoader
        anchors.fill: parent
        asynchronous: false
        source: root.pluginData ? PluginManager.settingsEntryUrl(root.pluginData) : ""

        onLoaded: {
            if (!item || !root.pluginData) return;

            if (item.pluginMetadata !== undefined) item.pluginMetadata = root.pluginData;
            if (item.pluginDirectory !== undefined) item.pluginDirectory = root.pluginData._dir || "";
            if (item.rootObj !== undefined) item.rootObj = root.rootObj;
            if (item.pluginInstance !== undefined) item.pluginInstance = PluginManager.instanceById(root.pluginId);
            if (item.hostServices !== undefined) {
                item.hostServices = {
                    config: Config,
                    pluginManager: PluginManager,
                    theme: ThemeBackend,
                    scaler: Scaler,
                    caching: Caching
                };
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.pluginData || !PluginManager.supportsSettings(root.pluginData) || settingsLoader.status === Loader.Error
        spacing: rootObj.s(8)

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: settingsLoader.status === Loader.Error ? "Unable to load plugin settings" : "No settings available"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(16)
            font.weight: Font.Bold
            color: ThemeBackend.text
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.pluginData ? root.pluginData.name : root.pluginId
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(11)
            color: ThemeBackend.subtext0
        }
    }
}
