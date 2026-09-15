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

    function getPositionedWidget(moduleId) {
        if (PluginManager.isBarModuleId(moduleId)) return getPluginWidget(moduleId);
        return getWidget(moduleId);
    }

    function isPluginInCenter(moduleId) {
        for (let i = 0; i < centerArr.length; ++i) {
            const item = centerArr[i];
            if (Array.isArray(item)) {
                if (item.indexOf(moduleId) !== -1) return true;
            } else if (item === moduleId) {
                return true;
            }
        }
        return false;
    }

    function pluginTargetX(moduleId, widget) {
        // A standalone plugin placed in the center lane should visually be
        // centered as well. TopBarBase does not include dynamic plugin widths in
        // its static native width table, which otherwise pushes the plugin to
        // the right edge of the center lane.
        if (isPluginInCenter(moduleId) && !isModuleGrouped(moduleId)) {
            const w = widget && widget.targetWidth !== undefined ? widget.targetWidth : (widget ? widget.width : 0);
            return Math.round((root.width - w) / 2);
        }
        return root.getModuleX(moduleId, root.layoutState);
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
            targetX: root.pluginTargetX(moduleId, pluginBar)
            targetY: root.getModuleY(pluginBar)
            z: 10
        }
    }
}
