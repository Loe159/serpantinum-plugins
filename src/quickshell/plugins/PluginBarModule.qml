import QtQuick
import QtQuick.Layouts
import "../"

Rectangle {
    id: root

    property string moduleId: ""
    property var pluginData: null
    property var barWindow: null
    property bool vertical: false
    property bool isSolid: false
    property bool distinctPills: barWindow && barWindow.distinctPills !== undefined ? barWindow.distinctPills : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool layoutAnimationsEnabled: true
    property real targetX: 0
    property real targetY: 0

    readonly property var pluginInstance: pluginData ? PluginManager.instanceById(pluginData.id) : null
    readonly property var theme: ThemeBackend
    readonly property bool compact: isGrouped || (isSolid && distinctPills)
    readonly property bool hovered: hoverHandler.hovered
    readonly property bool isBottomBar: barWindow ? barWindow.barPosition === "bottom" : false
    readonly property string barSection: PluginManager.barModuleSection(moduleId)

    function s(value) {
        return barWindow && typeof barWindow.s === "function" ? barWindow.s(value) : Scaler.s(value);
    }

    function activate() {
        if (!pluginInstance) return;
        if (typeof pluginInstance.activateBar === "function") pluginInstance.activateBar(root);
        else if (typeof pluginInstance.togglePanel === "function") pluginInstance.togglePanel();
    }

    function pluginSetting(key, fallbackValue) {
        if (!pluginData) return fallbackValue;
        const settings = PluginManager.pluginSettings(pluginData.id);
        return settings && settings[key] !== undefined ? settings[key] : fallbackValue;
    }

    function setPluginSetting(key, value) {
        if (pluginData) PluginManager.updatePluginSetting(pluginData.id, key, value);
    }

    readonly property real horizontalPadding: s(compact ? 9 : 11)
    readonly property real verticalPadding: s(compact ? 4 : 5)
    readonly property real loadedImplicitWidth: contentLoader.item
        ? Math.max(contentLoader.item.implicitWidth || 0, contentLoader.item.width || 0)
        : 0
    readonly property real loadedImplicitHeight: contentLoader.item
        ? Math.max(contentLoader.item.implicitHeight || 0, contentLoader.item.height || 0)
        : 0

    readonly property real horizontalHeight: barWindow
        ? (isGrouped ? barWindow.barHeight - s(8) : ((isSolid && distinctPills) ? barWindow.barHeight - s(6) : barWindow.barHeight))
        : s(isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    readonly property real verticalWidth: Math.max(
        barWindow ? (isGrouped ? barWindow.barHeight - s(8) : ((isSolid && distinctPills) ? barWindow.barHeight - s(6) : barWindow.barHeight)) : s(30),
        loadedImplicitWidth + s(4)
    )

    property real targetWidth: moduleActive && contentLoader.status === Loader.Ready
        ? (vertical ? verticalWidth : loadedImplicitWidth + horizontalPadding * 2)
        : 0
    property real targetHeight: moduleActive && contentLoader.status === Loader.Ready
        ? (vertical ? loadedImplicitHeight + verticalPadding * 2 : horizontalHeight)
        : 0

    x: targetX
    y: targetY
    width: targetWidth
    height: targetHeight
    visible: moduleActive && (width > 0 || height > 0 || opacity > 0) && (!barWindow || !barWindow.positionChanging)
    opacity: visible ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    clip: true

    radius: ThemeBackend.borderRadius
    border.width: 0
    color: isGrouped
        ? "transparent"
        : (isSolid
            ? (distinctPills
                ? (hovered ? ThemeBackend.surface0 : Qt.darker(ThemeBackend.surface0, 1.15))
                : "transparent")
            : (hovered ? ThemeBackend.surface0 : ThemeBackend.base))

    Behavior on color { ColorAnimation { duration: 250 } }
    Behavior on width {
        enabled: !barWindow || !barWindow.positionChanging
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }
    Behavior on height {
        enabled: !barWindow || !barWindow.positionChanging
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        enabled: !barWindow || !barWindow.positionChanging
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }
    Behavior on x {
        enabled: root.layoutAnimationsEnabled
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }
    Behavior on y {
        enabled: root.layoutAnimationsEnabled
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        asynchronous: false
        active: root.pluginData !== null && root.moduleActive && PluginManager.isEnabled(root.pluginData)
        source: active ? PluginManager.barEntryUrl(root.pluginData) : ""

        onLoaded: {
            if (!item) return;
            try { item.host = root; } catch (e) {
                PluginManager.reportFailed(root.pluginData.id, "barEntry root must expose a 'host' property: " + e);
            }
        }

        onStatusChanged: {
            if (status === Loader.Error && root.pluginData) {
                PluginManager.reportFailed(root.pluginData.id, "barEntry QML loader error for " + source);
            }
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.moduleActive
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.moduleActive
        onTapped: root.activate()
    }

    transform: Translate {
        x: root.vertical ? (root.moduleActive ? 0 : (barWindow && barWindow.barPosition === "right" ? root.s(16) : -root.s(16))) : 0
        y: root.vertical ? 0 : (root.moduleActive ? 0 : (root.isBottomBar ? root.s(16) : -root.s(16)))
        Behavior on x { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
        Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
    }
}
