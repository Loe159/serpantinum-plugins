import QtQuick
import "."
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

    function getModuleInfo(id) {
        if (PluginManager.isBarModuleId(id)) {
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

        let labels = {
            "left": I18n.t("guide.bar.modules.actions"),
            "workspaces": I18n.t("guide.bar.modules.workspaces"),
            "focus": I18n.t("guide.bar.modules.focus"),
            "timedate": I18n.t("guide.bar.modules.timedate"),
            "info": I18n.t("guide.bar.modules.info"),
            "weather": I18n.t("guide.bar.modules.weather"),
            "media": I18n.t("guide.bar.modules.media"),
            "vis": I18n.t("guide.bar.modules.vis"),
            "tray": I18n.t("guide.bar.modules.tray"),
            "sysmon": I18n.t("guide.bar.modules.sysmon"),
            "kb": I18n.t("guide.bar.modules.keyboard"),
            "wifi": I18n.t("guide.bar.modules.network"),
            "bt": I18n.t("guide.bar.modules.bluetooth"),
            "vol": I18n.t("guide.bar.modules.volume"),
            "bat": I18n.t("guide.bar.modules.battery")
        };
        let icons = {
            "left": "󰍜",
            "workspaces": "󰮯",
            "focus": "󰈈",
            "timedate": "󰃰",
            "info": "󰋼",
            "weather": "󰖐",
            "media": "󰎈",
            "vis": "󰝚",
            "tray": "󱊞",
            "sysmon": "󰍛",
            "kb": "󰌌",
            "wifi": "󰤨",
            "bt": "󰂲",
            "vol": "󰕾",
            "bat": "󰁹"
        };
        let colors = {
            "left": ThemeBackend.blue,
            "workspaces": ThemeBackend.mauve,
            "focus": ThemeBackend.teal,
            "timedate": ThemeBackend.peach,
            "info": ThemeBackend.red,
            "weather": ThemeBackend.yellow,
            "media": ThemeBackend.green,
            "vis": ThemeBackend.mauve,
            "tray": ThemeBackend.yellow,
            "sysmon": ThemeBackend.mauve,
            "kb": ThemeBackend.text,
            "wifi": ThemeBackend.blue,
            "bt": ThemeBackend.mauve,
            "vol": ThemeBackend.peach,
            "bat": ThemeBackend.green
        };
        return {
            "moduleId": id,
            "moduleLabel": labels[id] || id,
            "moduleIcon": icons[id] || "󰅂",
            "moduleColor": colorToString(colors[id] || ThemeBackend.text),
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
                available.append(getModuleInfo(moduleId));
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
