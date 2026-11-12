pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    width: 0
    height: 0
    visible: false

    readonly property int apiVersion: 1
    readonly property string barModulePrefix: "plugin:"
    readonly property string builtinPluginDir: Caching.qsDir + "/plugins/builtin"
    readonly property string reusablesDir: Caching.qsDir + "/reusables"
    readonly property string userPluginDir: {
        const xdgConfig = Quickshell.env("XDG_CONFIG_HOME");
        const configRoot = typeof xdgConfig === "string" && xdgConfig.trim() !== ""
            ? xdgConfig
            : Caching.home + "/.config";
        return configRoot + "/serpantinum/plugins";
    }

    property var plugins: []
    property int configRevision: 0
    readonly property var barPlugins: plugins.filter(p => root.supportsBar(p))
    readonly property var settingsPlugins: plugins.filter(p => root.supportsSettings(p))
    readonly property var barModules: { const revision = root.configRevision; return root.buildBarModules(plugins); }
    property var instances: ({})
    property bool scanning: false
    property string lastError: ""

    property bool installing: false
    property bool updating: false
    property string updateMessage: ""
    property bool installSucceeded: false
    property string installMessage: ""
    property string pendingInstallUrl: ""

    signal refreshed(int count)
    signal pluginLoaded(string pluginId)
    signal pluginFailed(string pluginId, string reason)
    signal installFinished(bool success, string message)

    // A manual refresh also checks tracked Git repositories for newly added plugins.
    // Startup and internal refreshes remain local and fast.
    function refreshFromGit() {
        if (installing || updating || scanning) return;
        updating = true;
        updateMessage = "Checking Git sources…";
        sourceUpdater.command = [
            "python3", Caching.qsDir + "/plugins/plugin_repository.py",
            "refresh", userPluginDir, apiVersion.toString()
        ];
        sourceUpdater.running = true;
    }

    // A metadata-only scan cannot recompile already loaded QML components.
    // A hard reload re-creates the plugin host and every Bar entry after Git sync.
    function activateUpdatedPlugins() {
        Qt.callLater(function() {
            try {
                Quickshell.reload(true);
            } catch (error) {
                console.warn("[plugins] reload failed: " + error);
                root.updateMessage += " · Restart Serpantinum to apply plugin code";
                root.refresh();
            }
        });
    }

    function refresh() {
        if (scanner.running) scanner.running = false;
        lastError = "";
        scanning = true;
        scanner.running = true;
    }

    function pluginById(pluginId) {
        for (let i = 0; i < plugins.length; ++i) {
            if (plugins[i].id === pluginId) return plugins[i];
        }
        return null;
    }

    function pluginSettings(pluginId) {
        const settings = Config.getSetting("plugins", {});
        if (!settings || typeof settings !== "object") return {};
        const value = settings[pluginId];
        return (value && typeof value === "object") ? value : {};
    }

    function updatePluginSetting(pluginId, key, value) {
        let all = Config.getSetting("plugins", {});
        if (!all || typeof all !== "object" || Array.isArray(all)) all = {};
        let current = all[pluginId];
        if (!current || typeof current !== "object" || Array.isArray(current)) current = {};
        current = Object.assign({}, current);
        current[key] = value;
        all = Object.assign({}, all);
        all[pluginId] = current;
        Config.setSetting("plugins", all);
    }

    function isEnabled(plugin) {
        if (!plugin) return false;
        const settings = Config.getSetting("plugins", {});
        if (settings && typeof settings === "object") {
            const perPlugin = settings[plugin.id];
            if (perPlugin && perPlugin.enabled !== undefined) return !!perPlugin.enabled;
            if (Array.isArray(settings.disabled) && settings.disabled.indexOf(plugin.id) !== -1) return false;
            if (Array.isArray(settings.enabled) && settings.enabled.length > 0) return settings.enabled.indexOf(plugin.id) !== -1;
        }
        return plugin.enabledByDefault !== false;
    }

    function setEnabled(pluginId, enabled) {
        updatePluginSetting(pluginId, "enabled", !!enabled);
    }

    function hasListItems(value) {
        return value !== null && value !== undefined
            && typeof value.length === "number" && value.length > 0;
    }

    function supportsBar(plugin) {
        return !!(plugin && ((typeof plugin.barEntry === "string" && plugin.barEntry.trim() !== "")
            || hasListItems(plugin.barEntries)));
    }

    function supportsSettings(plugin) {
        return !!(plugin && typeof plugin.settingsEntry === "string" && plugin.settingsEntry.trim() !== "");
    }

    function buildBarModules(pluginList) {
        const out = [];
        if (!Array.isArray(pluginList)) return out;
        for (let i = 0; i < pluginList.length; ++i) {
            const plugin = pluginList[i];
            if (!supportsBar(plugin)) continue;
            if (hasListItems(plugin.barEntries)) {
                for (let j = 0; j < plugin.barEntries.length; ++j) {
                    const entry = plugin.barEntries[j];
                    if (!entry || !entry.id || !entry.entry) continue;
                    if (entry.enabledSetting) {
                        const perPlugin = pluginSettings(plugin.id);
                        const enabled = perPlugin[entry.enabledSetting] !== undefined
                            ? !!perPlugin[entry.enabledSetting]
                            : entry.enabledByDefault !== false;
                        if (!enabled) continue;
                    }
                    out.push({ plugin: plugin, entry: entry, moduleId: barModulePrefix + plugin.id + ":" + entry.id });
                }
            } else {
                out.push({ plugin: plugin, entry: null, moduleId: barModulePrefix + plugin.id });
            }
        }
        return out;
    }

    function supportsTopbar(plugin) {
        return !!(plugin && typeof plugin.barEntry === "string" && plugin.barEntry.trim() !== "");
    }

    function barModuleId(pluginOrId) {
        const id = typeof pluginOrId === "string" ? pluginOrId : (pluginOrId ? pluginOrId.id : "");
        return id ? barModulePrefix + id : "";
    }

    function isBarModuleId(moduleId) {
        return typeof moduleId === "string" && moduleId.indexOf(barModulePrefix) === 0;
    }

    function pluginForBarModule(moduleId) {
        if (!isBarModuleId(moduleId)) return null;
        const raw = moduleId.substring(barModulePrefix.length);
        const separator = raw.indexOf(":");
        return pluginById(separator === -1 ? raw : raw.substring(0, separator));
    }

    function barEntryForModule(moduleId) {
        if (!isBarModuleId(moduleId)) return null;
        const raw = moduleId.substring(barModulePrefix.length);
        const separator = raw.indexOf(":");
        if (separator === -1) return null;
        const plugin = pluginById(raw.substring(0, separator));
        if (!plugin || !hasListItems(plugin.barEntries)) return null;
        const entryId = raw.substring(separator + 1);
        for (let i = 0; i < plugin.barEntries.length; ++i) {
            if (plugin.barEntries[i] && plugin.barEntries[i].id === entryId) return plugin.barEntries[i];
        }
        return null;
    }

    function entryUrl(plugin) {
        if (!plugin || !plugin._dir || !plugin.entry) return "";
        return encodeURI("file://" + plugin._dir + "/" + plugin.entry);
    }

    function barEntryUrl(plugin, entry) {
        if (!supportsBar(plugin) || !plugin._dir) return "";
        const path = entry && entry.entry ? entry.entry : plugin.barEntry;
        return path ? encodeURI("file://" + plugin._dir + "/" + path) : "";
    }

    function settingsEntryUrl(plugin) {
        if (!supportsSettings(plugin) || !plugin._dir) return "";
        return encodeURI("file://" + plugin._dir + "/" + plugin.settingsEntry);
    }

    function reusableUrl(fileName) {
        const safeName = String(fileName || "");
        if (safeName === "" || safeName.indexOf("/") !== -1 || safeName.indexOf("\\") !== -1) return "";
        // Old plugin API names continue to resolve after the upstream reusables refactor.
        const locations = {
            "ClickButton.qml": "buttons", "IconButton.qml": "buttons", "FillButton.qml": "buttons",
            "DeleteButton.qml": "buttons", "CanvasIconButton.qml": "buttons",
            "Toggle.qml": "inputs", "Switch.qml": "inputs", "Input.qml": "inputs",
            "Dropdown.qml": "inputs", "FilePicker.qml": "inputs", "ImagePicker.qml": "inputs",
            "PasswordInput.qml": "inputs", "SliderProgress.qml": "inputs", "LyricsPicker.qml": "inputs",
            "NumberSelector.qml": "inputs", "TimeSelector.qml": "inputs",
            "FlipIcon.qml": "display", "ImageBox.qml": "display", "LoaderIcon.qml": "display",
            "NotificationBox.qml": "display", "SystemUsageCard.qml": "display",
            "Draggable.qml": "behavior", "ScreenPositionSelector.qml": "behavior",
            "Reserved.qml": "layout", "SettingsRow.qml": "guide", "SettingsGroup.qml": "guide"
        };
        return encodeURI("file://" + reusablesDir + "/" + (locations[safeName] ? locations[safeName] + "/" : "") + safeName);
    }

    function arrayContainsModule(arr, moduleId) {
        if (!Array.isArray(arr)) return false;
        for (let i = 0; i < arr.length; ++i) {
            const item = arr[i];
            if (Array.isArray(item)) {
                if (arrayContainsModule(item, moduleId)) return true;
            } else if (item === moduleId) {
                return true;
            }
        }
        return false;
    }

    function moduleIsPlaced(moduleId) {
        return barModuleSection(moduleId) !== "";
    }

    function barModuleSection(moduleId) {
        const bar = Config.getSetting("bar", {});
        const modules = bar && bar.modules ? bar.modules : {};
        if (arrayContainsModule(modules.left || [], moduleId)) return "left";
        if (arrayContainsModule(modules.center || [], moduleId)) return "center";
        if (arrayContainsModule(modules.right || [], moduleId)) return "right";
        return "";
    }

    function removeModuleFromArray(arr, moduleId) {
        if (!Array.isArray(arr)) return [];
        let out = [];
        for (let i = 0; i < arr.length; ++i) {
            const item = arr[i];
            if (Array.isArray(item)) {
                let cleaned = removeModuleFromArray(item, moduleId);
                if (cleaned.length === 1) out.push(cleaned[0]);
                else if (cleaned.length > 1) out.push(cleaned);
            } else if (item !== moduleId) {
                out.push(item);
            }
        }
        return out;
    }

    function isTopbarEnabled(plugin) {
        if (!supportsBar(plugin)) return false;
        return moduleIsPlaced(barModuleId(plugin));
    }

    function setBarModuleEnabled(moduleId, enabled, preferredSection) {
        if (!isBarModuleId(moduleId)) return;
        const plugin = pluginForBarModule(moduleId);
        if (!plugin || !supportsBar(plugin)) return;

        let bar = Config.getSetting("bar", {});
        if (!bar || typeof bar !== "object" || Array.isArray(bar)) bar = {};
        let modules = bar.modules;
        if (!modules || typeof modules !== "object" || Array.isArray(modules)) {
            modules = { left: [], center: [], right: [] };
        } else {
            modules = JSON.parse(JSON.stringify(modules));
        }
        if (!Array.isArray(modules.left)) modules.left = [];
        if (!Array.isArray(modules.center)) modules.center = [];
        if (!Array.isArray(modules.right)) modules.right = [];

        if (enabled) {
            if (!arrayContainsModule(modules.left, moduleId)
                    && !arrayContainsModule(modules.center, moduleId)
                    && !arrayContainsModule(modules.right, moduleId)) {
                const section = preferredSection === "left" || preferredSection === "right"
                    ? preferredSection : "center";
                modules[section].push(moduleId);
            }
        } else {
            modules.left = removeModuleFromArray(modules.left, moduleId);
            modules.center = removeModuleFromArray(modules.center, moduleId);
            modules.right = removeModuleFromArray(modules.right, moduleId);
        }

        bar.modules = modules;
        Config.setSetting("bar", bar);
    }

    function setTopbarEnabled(pluginId, enabled) {
        const plugin = pluginById(pluginId);
        if (!plugin || !supportsBar(plugin)) return;

        setBarModuleEnabled(barModuleId(plugin), enabled, "center");
        updatePluginSetting(pluginId, "topbar", !!enabled);
        updatePluginSetting(pluginId, "barPlacementMigrated", true);
    }

    function migrateLegacyBarPlacements() {
        for (let i = 0; i < barPlugins.length; ++i) {
            const plugin = barPlugins[i];
            const perPlugin = pluginSettings(plugin.id);
            if (perPlugin.barPlacementMigrated === true) continue;

            const requested = perPlugin.topbar === true
                || (perPlugin.topbar === undefined && plugin.topbarByDefault === true);

            if (requested && !moduleIsPlaced(barModuleId(plugin))) {
                setTopbarEnabled(plugin.id, true);
            } else {
                updatePluginSetting(plugin.id, "barPlacementMigrated", true);
            }
        }
    }

    function registerInstance(pluginId, instance) {
        let next = Object.assign({}, instances);
        next[pluginId] = instance;
        instances = next;
    }

    function unregisterInstance(pluginId, instance) {
        if (!instances[pluginId]) return;
        if (instance !== undefined && instance !== null && instances[pluginId] !== instance) return;
        let next = Object.assign({}, instances);
        delete next[pluginId];
        instances = next;
    }

    function instanceById(pluginId) {
        return instances[pluginId] || null;
    }

    function installFromGit(url) {
        const trimmed = String(url || "").trim();
        if (installing) return;
        if (trimmed === "") {
            installSucceeded = false;
            installMessage = "Enter a Git repository URL";
            installFinished(false, installMessage);
            return;
        }
        pendingInstallUrl = trimmed;
        installSucceeded = false;
        installMessage = "Cloning plugin…";
        installing = true;
        installer.command = [
            "python3", Caching.qsDir + "/plugins/plugin_repository.py",
            "install", trimmed, userPluginDir, apiVersion.toString()
        ];
        installer.running = true;
    }

    function reportLoaded(pluginId) {
        console.log("[plugins] loaded " + pluginId);
        pluginLoaded(pluginId);
    }

    function reportFailed(pluginId, reason) {
        console.warn("[plugins] failed " + pluginId + ": " + reason);
        pluginFailed(pluginId, reason);
    }

    Process {
        id: scanner
        running: false
        command: ["python3", Caching.qsDir + "/plugins/plugin_repository.py", "scan", root.apiVersion.toString(), root.builtinPluginDir, root.userPluginDir]

        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                const raw = this.text.trim();
                if (raw === "") {
                    root.plugins = [];
                    root.lastError = "plugin scanner returned no data";
                    root.refreshed(0);
                    return;
                }
                try {
                    const result = JSON.parse(raw);
                    root.plugins = Array.isArray(result.plugins) ? result.plugins : [];
                    const errors = Array.isArray(result.errors) ? result.errors : [];
                    if (errors.length > 0) {
                        root.lastError = errors.map(e => e.manifest + ": " + e.error).join("\n");
                        console.warn("[plugins] scan warnings:\n" + root.lastError);
                    }
                    root.refreshed(root.plugins.length);
                    Qt.callLater(root.migrateLegacyBarPlacements);
                } catch (e) {
                    root.plugins = [];
                    root.lastError = "failed to parse scanner output: " + e;
                    console.warn("[plugins] " + root.lastError);
                    root.refreshed(0);
                }
            }
        }
        onExited: root.scanning = false
    }

    Process {
        id: sourceUpdater
        running: false
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(this.text.trim());
                    if (!result.ok) {
                        root.updateMessage = result.error || "Git refresh failed";
                    } else {
                        const changes = (result.installed || []).concat(result.updated || []);
                        const warnings = result.warnings || [];
                        const skipped = result.skipped || [];
                        root.updateMessage = changes.length
                            ? "Synced: " + changes.join(", ")
                            : "Git plugins already up to date";
                        if (skipped.length) root.updateMessage += " · Preserved: " + skipped.join(", ");
                        if (warnings.length) root.updateMessage += " · " + warnings.join(" · ");
                        if (changes.length) {
                            root.updateMessage += " · Reloading Serpantinum…";
                            root.updating = false;
                            root.activateUpdatedPlugins();
                            return;
                        }
                    }
                } catch (e) {
                    root.updateMessage = "Git refresh failed: " + String(e);
                }
                root.updating = false;
                root.refresh();
            }
        }
        onExited: {
            if (root.updating) {
                root.updating = false;
                root.updateMessage = "Git refresh interrupted";
                root.refresh();
            }
        }
    }

    Process {
        id: installer
        running: false
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                root.installing = false;
                try {
                    const result = JSON.parse(raw);
                    if (result.ok) {
                        root.installSucceeded = true;
                        const installed = result.installed || [];
                        const updated = result.updated || [];
                        const skipped = result.skipped || [];
                        const parts = [];
                        if (installed.length) parts.push("Installed: " + installed.join(", "));
                        if (updated.length) parts.push("Updated: " + updated.join(", "));
                        if (skipped.length) parts.push("Already present (unchanged): " + skipped.join(", "));
                        root.installMessage = parts.length ? parts.join(" · ") : "Plugins already up to date";
                        root.installFinished(true, root.installMessage);
                        if (installed.length || updated.length) root.activateUpdatedPlugins();
                        else root.refresh();
                    } else {
                        root.installSucceeded = false;
                        root.installMessage = result.error || "Plugin installation failed";
                        root.installFinished(false, root.installMessage);
                    }
                } catch (e) {
                    root.installSucceeded = false;
                    root.installMessage = raw !== "" ? raw : ("Plugin installation failed: " + e);
                    root.installFinished(false, root.installMessage);
                }
            }
        }
        onExited: root.installing = false
    }

    Connections {
        target: Config
        function onSettingsLoaded() { root.configRevision++; }
        function onRawSettingsChanged() { root.configRevision++; }
    }

    Component.onCompleted: Qt.callLater(root.refresh)
}
