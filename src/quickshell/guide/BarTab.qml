import QtQuick
import "../"

BarTabBase {
    id: root

    function pluginAccent(plugin) {
        if (!plugin || !plugin.barColor) return ThemeBackend.mauve;
        const key = String(plugin.barColor).toLowerCase();
        if (key === "pink") return ThemeBackend.pink;
        if (key === "lavender") return ThemeBackend.lavender;
        if (key === "blue") return ThemeBackend.blue;
        if (key === "sapphire") return ThemeBackend.sapphire;
        if (key === "teal") return ThemeBackend.teal;
        if (key === "green") return ThemeBackend.green;
        if (key === "yellow") return ThemeBackend.yellow;
        if (key === "peach") return ThemeBackend.peach;
        if (key === "flamingo") return ThemeBackend.flamingo;
        if (key === "red") return ThemeBackend.red;
        return ThemeBackend.mauve;
    }

    // Keep plugin metadata separate from BarTabBase.getModuleInfo(). Shadowing
    // the base method makes the dynamically loaded Bar settings page unreliable.
    function getPluginModuleInfo(id) {
        const plugin = PluginManager.pluginForBarModule(id);
        return {
            "moduleId": id,
            "moduleLabel": plugin ? (plugin.barLabel || plugin.name || plugin.id) : id,
            "moduleIcon": plugin ? (plugin.barIcon || plugin.icon || "󰏗") : "󰏗",
            "moduleColor": colorToString(pluginAccent(plugin)),
            "isPlaceholder": false,
            "placeholderWidth": 0,
            "groupId": ""
        };
    }

    function modelContains(model, moduleId) {
        if (!model) return false;
        for (let i = 0; i < model.count; ++i) {
            const item = model.get(i);
            if (item && !item.isPlaceholder && item.moduleId === moduleId) return true;
        }
        return false;
    }

    function moduleExistsInEditor(moduleId) {
        return modelContains(getModel("left"), moduleId)
            || modelContains(getModel("center"), moduleId)
            || modelContains(getModel("right"), moduleId)
            || modelContains(getModel("available"), moduleId);
    }

    function syncPluginModules() {
        const available = getModel("available");
        if (!available) return;

        // Remove stale plugin cards from Available when a plugin disappears.
        for (let i = available.count - 1; i >= 0; --i) {
            const item = available.get(i);
            if (item && PluginManager.isBarModuleId(item.moduleId)
                    && PluginManager.pluginForBarModule(item.moduleId) === null) {
                available.remove(i, 1);
            }
        }

        const plugins = PluginManager.barPlugins;
        for (let i = 0; i < plugins.length; ++i) {
            const moduleId = PluginManager.barModuleId(plugins[i]);
            if (!moduleExistsInEditor(moduleId)) {
                available.append(getPluginModuleInfo(moduleId));
            }
        }
    }

    Connections {
        target: PluginManager
        function onRefreshed(count) { Qt.callLater(root.syncPluginModules); }
    }

    Connections {
        target: Config
        function onSettingsLoaded() { Qt.callLater(root.syncPluginModules); }
    }

    Connections {
        target: root
        function onVisibleChanged() {
            if (root.visible) Qt.callLater(root.syncPluginModules);
        }
    }

    Timer {
        interval: 1
        running: true
        repeat: false
        onTriggered: root.syncPluginModules()
    }
}
