import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../../"

Item {
    id: root

    width: 0
    height: 0

    property var pluginMetadata: ({})
    property string pluginDirectory: ""

    property int defaultSeconds: 5 * 60
    property int remainingSeconds: defaultSeconds
    property bool counting: false
    property bool panelVisible: false
    property string panelSection: "center"
    property string panelBarPosition: "top"
    property real panelBarThickness: 40
    property var panelScreen: null

    readonly property string topbarText: formatTime(remainingSeconds)
    readonly property string topbarIcon: "󰔛"
    readonly property color topbarColor: counting ? ThemeBackend.green : ThemeBackend.mauve

    function formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        return mins.toString().padStart(2, "0") + ":" + secs.toString().padStart(2, "0");
    }

    function syncPanelContext(host) {
        const pluginId = root.pluginMetadata && root.pluginMetadata.id
            ? root.pluginMetadata.id
            : "serpantinum.timer";
        const moduleId = PluginManager.barModuleId(pluginId);
        const section = host && host.barSection ? host.barSection : PluginManager.barModuleSection(moduleId);
        root.panelSection = section || "center";

        if (host && host.barWindow) {
            root.panelBarPosition = host.barWindow.barPosition || "top";
            root.panelBarThickness = host.barWindow.barHeight || 40;
            root.panelScreen = host.barWindow.screen || null;
            return;
        }

        const bar = Config.getSetting("bar", {});
        root.panelBarPosition = bar && bar.position ? bar.position : "top";
        root.panelBarThickness = bar && bar.height ? Number(bar.height) : 40;
        if (!root.panelScreen && Quickshell.screens && Quickshell.screens.length > 0) {
            root.panelScreen = Quickshell.screens[0];
        }
    }

    function activateBar(host) {
        syncPanelContext(host);
        panelVisible = !panelVisible;
    }

    function togglePanel() {
        if (!panelVisible) syncPanelContext(null);
        panelVisible = !panelVisible;
    }

    function showPanel() {
        syncPanelContext(null);
        panelVisible = true;
    }

    function hidePanel() {
        panelVisible = false;
    }

    function startTimer(seconds) {
        const parsed = Number(seconds);
        if (!isNaN(parsed) && parsed > 0) {
            remainingSeconds = Math.floor(parsed);
        }
        counting = remainingSeconds > 0;
    }

    function pauseTimer() {
        counting = false;
    }

    function resetTimer() {
        counting = false;
        remainingSeconds = defaultSeconds;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.counting && root.remainingSeconds > 0
        onTriggered: {
            root.remainingSeconds--;
            if (root.remainingSeconds <= 0) {
                root.remainingSeconds = 0;
                root.counting = false;
            }
        }
    }

    IpcHandler {
        target: "plugin-timer"

        function toggle(): void { root.togglePanel(); }
        function show(): void { root.showPanel(); }
        function hide(): void { root.hidePanel(); }

        function start(seconds: string): void {
            root.startTimer(seconds);
            root.showPanel();
        }

        function pause(): void { root.pauseTimer(); }
        function reset(): void { root.resetTimer(); }
    }

    PanelWindow {
        id: panel

        visible: root.panelVisible
        screen: root.panelScreen || ((Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null)
        color: "transparent"

        WlrLayershell.namespace: "serpantinum-plugin-timer"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: root.panelVisible ? panelCard : null
        }

        Rectangle {
            id: panelCard
            width: 360
            height: 210
            x: {
                const gap = 12;
                if (root.panelBarPosition === "left") {
                    return root.panelBarThickness + gap;
                }
                if (root.panelBarPosition === "right") {
                    return Math.max(gap, panel.width - width - root.panelBarThickness - gap);
                }
                if (root.panelSection === "left") return gap;
                if (root.panelSection === "right") return Math.max(gap, panel.width - width - gap);
                return Math.max(gap, (panel.width - width) / 2);
            }
            y: {
                const gap = 12;
                if (root.panelBarPosition === "top") {
                    return root.panelBarThickness + gap;
                }
                if (root.panelBarPosition === "bottom") {
                    return Math.max(gap, panel.height - height - root.panelBarThickness - gap);
                }
                if (root.panelSection === "left") return gap;
                if (root.panelSection === "right") return Math.max(gap, panel.height - height - gap);
                return Math.max(gap, (panel.height - height) / 2);
            }
            radius: Math.max(12, ThemeBackend.borderRadius * 2)
            color: ThemeBackend.base
            border.width: 1
            border.color: ThemeBackend.surface1

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                Text {
                    text: root.pluginMetadata.name || "Timer"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: root.formatTime(root.remainingSeconds)
                    color: ThemeBackend.text
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: 46
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Rectangle {
                        width: 96
                        height: 36
                        radius: Math.max(8, ThemeBackend.borderRadius)
                        color: ThemeBackend.mauve

                        Text {
                            anchors.centerIn: parent
                            text: root.counting ? "Pause" : "Start"
                            color: ThemeBackend.base
                            font.family: ThemeBackend.fontFamily
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.counting ? root.pauseTimer() : root.startTimer(root.remainingSeconds)
                        }
                    }

                    Rectangle {
                        width: 96
                        height: 36
                        radius: Math.max(8, ThemeBackend.borderRadius)
                        color: ThemeBackend.surface0

                        Text {
                            anchors.centerIn: parent
                            text: "Reset"
                            color: ThemeBackend.text
                            font.family: ThemeBackend.fontFamily
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resetTimer()
                        }
                    }

                    Rectangle {
                        width: 96
                        height: 36
                        radius: Math.max(8, ThemeBackend.borderRadius)
                        color: ThemeBackend.surface0

                        Text {
                            anchors.centerIn: parent
                            text: "Close"
                            color: ThemeBackend.text
                            font.family: ThemeBackend.fontFamily
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.hidePanel()
                        }
                    }
                }
            }
        }
    }
}
