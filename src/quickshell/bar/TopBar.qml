import QtQuick
import "../"

TopBarBase {
    id: root

    property int pluginRevision: 0

    Connections {
        target: PluginManager
        function onRefreshed(count) { root.pluginRevision++ }
        function onPluginLoaded(pluginId) { root.pluginRevision++ }
        function onPluginFailed(pluginId, reason) { root.pluginRevision++ }
    }

    function getPluginWidget(moduleId) {
        const revision = root.pluginRevision;
        for (let i = 0; i < pluginModules.count; ++i) {
            const item = pluginModules.itemAt(i);
            if (item && item.moduleId === moduleId) return item;
        }
        return null;
    }

    // Override the native width resolver. Base TopBar calculations call this
    // method as well, so plugin modules participate in layout, grouping,
    // collision avoidance and the dynamic bar background exactly like natives.
    function getW(moduleId) {
        if (PluginManager.isBarModuleId(moduleId)) {
            const pluginWidget = getPluginWidget(moduleId);
            return pluginWidget && pluginWidget.moduleActive
                ? (pluginWidget.targetWidth !== undefined ? pluginWidget.targetWidth : pluginWidget.width)
                : 0;
        }
        if (moduleId === "left") return wLeft;
        if (moduleId === "workspaces") return wWorkspaces;
        if (moduleId === "focus") return wFocus;
        if (moduleId === "media") return wMedia;
        if (moduleId === "vis") return wVis;
        if (moduleId === "tray") return wTray;
        if (moduleId === "sysmon") return wSysmon;
        if (moduleId === "kb") return wKb;
        if (moduleId === "wifi") return wWifi;
        if (moduleId === "bt") return wBt;
        if (moduleId === "vol") return wVol;
        if (moduleId === "bat") return wBat;
        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return wTimedate;
        if (moduleId === "info" || moduleId === "indicator" || moduleId === "indicators" || moduleId === "record") return wInfo;
        if (moduleId === "weather") return wWeather;
        return 0;
    }

    // Group backgrounds ask the bar for the positioned item. Use the inherited
    // getWidget() for native modules and our dynamic registry for plugins.
    function getPositionedWidget(moduleId) {
        if (PluginManager.isBarModuleId(moduleId)) return getPluginWidget(moduleId);
        return getWidget(moduleId);
    }

    Repeater {
        id: pluginModules
        model: PluginManager.barPlugins

        onItemAdded: function(index, item) { root.pluginRevision++; }
        onItemRemoved: function(index, item) { root.pluginRevision++; }

        delegate: PluginBarModule {
            id: pluginBar
            required property var modelData

            pluginData: modelData
            moduleId: PluginManager.barModuleId(modelData)
            barWindow: root.barWindow
            vertical: false
            isSolid: root.isSolid || root.isFill
            distinctPills: root.distinctPills
            moduleActive: root.isModuleActive(moduleId) && PluginManager.isEnabled(pluginData)
            isGrouped: root.isModuleGrouped(moduleId)
            layoutAnimationsEnabled: root.layoutAnimationsEnabled
            targetX: root.getModuleX(moduleId, root.layoutState)
            targetY: root.getModuleY(pluginBar)
            z: 10
        }
    }
}
