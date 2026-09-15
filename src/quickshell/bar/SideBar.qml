import QtQuick
import "../"

SideBarBase {
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

    function getH(moduleId) {
        if (PluginManager.isBarModuleId(moduleId)) {
            const pluginWidget = getPluginWidget(moduleId);
            return pluginWidget && pluginWidget.moduleActive
                ? (pluginWidget.targetHeight !== undefined ? pluginWidget.targetHeight : pluginWidget.height)
                : 0;
        }
        if (moduleId === "left" || moduleId === "top") return hLeft;
        if (moduleId === "workspaces") return hWorkspaces;
        if (moduleId === "focus") return hFocus;
        if (moduleId === "media") return hMedia;
        if (moduleId === "vis") return hVis;
        if (moduleId === "tray") return hTray;
        if (moduleId === "sysmon") return hSysmon;
        if (moduleId === "kb") return hKb;
        if (moduleId === "wifi") return hWifi;
        if (moduleId === "bt") return hBt;
        if (moduleId === "vol") return hVol;
        if (moduleId === "bat") return hBat;
        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return hTimedate;
        if (moduleId === "info" || moduleId === "indicator" || moduleId === "indicators" || moduleId === "record") return hInfo;
        if (moduleId === "weather") return hWeather;
        return 0;
    }

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
            vertical: true
            isSolid: root.isSolid || root.isFill
            distinctPills: root.distinctPills
            moduleActive: root.isModuleActive(moduleId) && PluginManager.isEnabled(pluginData)
            isGrouped: root.isModuleGrouped(moduleId)
            layoutAnimationsEnabled: root.layoutAnimationsEnabled
            targetX: root.getModuleX(pluginBar)
            targetY: root.getModuleY(moduleId, root.layoutState)
            z: 10
        }
    }
}
