import QtQuick
import "../"

Item {
    id: root

    width: 0
    height: 0

    property int configRevision: 0

    Connections {
        target: Config
        function onSettingsLoaded() { root.configRevision++ }
        function onRawSettingsChanged() { root.configRevision++ }
    }

    Repeater {
        model: PluginManager.plugins

        delegate: Loader {
            id: pluginLoader
            required property var modelData

            property var pluginData: modelData

            asynchronous: false
            active: {
                const dummy = root.configRevision;
                return PluginManager.isEnabled(pluginData);
            }
            source: active ? PluginManager.entryUrl(pluginData) : ""

            onActiveChanged: {
                if (!active) PluginManager.unregisterInstance(pluginData.id, item);
            }

            onItemChanged: {
                if (!item) PluginManager.unregisterInstance(pluginData.id);
            }

            onLoaded: {
                if (!item) {
                    PluginManager.reportFailed(pluginData.id, "entry loaded without a root object");
                    return;
                }

                try {
                    item.pluginMetadata = pluginData;
                    item.pluginDirectory = pluginData._dir;
                } catch (e) {
                    PluginManager.reportFailed(
                        pluginData.id,
                        "entry root must expose 'pluginMetadata' and 'pluginDirectory' properties: " + e
                    );
                    return;
                }

                PluginManager.registerInstance(pluginData.id, item);
                PluginManager.reportLoaded(pluginData.id);
            }

            onStatusChanged: {
                if (status === Loader.Error) {
                    PluginManager.unregisterInstance(pluginData.id);
                    PluginManager.reportFailed(pluginData.id, "QML loader error for " + source);
                }
            }

            Component.onDestruction: PluginManager.unregisterInstance(pluginData.id, item)
        }
    }
}
