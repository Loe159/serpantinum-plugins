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
    readonly property string builtinPluginDir: Caching.qsDir + "/plugins/builtin"
    readonly property string userPluginDir: {
        const xdgConfig = Quickshell.env("XDG_CONFIG_HOME");
        return (xdgConfig !== "" ? xdgConfig : Caching.home + "/.config") + "/serpantinum/plugins";
    }

    property var plugins: []
    property bool scanning: false
    property string lastError: ""

    signal refreshed(int count)
    signal pluginLoaded(string pluginId)
    signal pluginFailed(string pluginId, string reason)

    function scannerScript() {
        return [
            "import json, pathlib, sys",
            "host_api = int(sys.argv[1])",
            "roots = [(sys.argv[2], 'builtin'), (sys.argv[3], 'user')]",
            "plugins = {}",
            "errors = []",
            "for root, source in roots:",
            "    base = pathlib.Path(root).expanduser()",
            "    if not base.is_dir():",
            "        continue",
            "    for manifest_path in sorted(base.glob('*/plugin.json')):",
            "        try:",
            "            data = json.loads(manifest_path.read_text(encoding='utf-8'))",
            "            plugin_id = str(data.get('id') or manifest_path.parent.name).strip()",
            "            if not plugin_id:",
            "                raise ValueError('missing plugin id')",
            "            api = int(data.get('apiVersion', data.get('api_version', 1)))",
            "            if api > host_api:",
            "                raise ValueError(f'requires plugin API {api}, host provides {host_api}')",
            "            entry = str(data.get('entry') or 'Plugin.qml')",
            "            entry_path = (manifest_path.parent / entry).resolve()",
            "            if not entry_path.is_file():",
            "                raise ValueError(f'entry not found: {entry}')",
            "            data['id'] = plugin_id",
            "            data['apiVersion'] = api",
            "            data['entry'] = entry",
            "            data['_dir'] = str(manifest_path.parent.resolve())",
            "            data['_manifest'] = str(manifest_path.resolve())",
            "            data['_source'] = source",
            "            plugins[plugin_id] = data",
            "        except Exception as exc:",
            "            errors.append({'manifest': str(manifest_path), 'error': str(exc)})",
            "result = {'plugins': [plugins[key] for key in sorted(plugins)], 'errors': errors}",
            "print(json.dumps(result, ensure_ascii=False))"
        ].join("\n");
    }

    function refresh() {
        if (scanner.running) {
            scanner.running = false;
        }
        lastError = "";
        scanning = true;
        scanner.running = true;
    }

    function pluginById(pluginId) {
        for (let i = 0; i < plugins.length; ++i) {
            if (plugins[i].id === pluginId) {
                return plugins[i];
            }
        }
        return null;
    }

    function isEnabled(plugin) {
        if (!plugin) return false;

        const settings = Config.getSetting("plugins", {});
        if (settings && typeof settings === "object") {
            const perPlugin = settings[plugin.id];
            if (perPlugin && perPlugin.enabled !== undefined) {
                return !!perPlugin.enabled;
            }

            if (Array.isArray(settings.disabled) && settings.disabled.indexOf(plugin.id) !== -1) {
                return false;
            }

            if (Array.isArray(settings.enabled) && settings.enabled.length > 0) {
                return settings.enabled.indexOf(plugin.id) !== -1;
            }
        }

        return plugin.enabledByDefault !== false;
    }

    function entryUrl(plugin) {
        if (!plugin || !plugin._dir || !plugin.entry) return "";
        return encodeURI("file://" + plugin._dir + "/" + plugin.entry);
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
        command: [
            "python3",
            "-c",
            root.scannerScript(),
            root.apiVersion.toString(),
            root.builtinPluginDir,
            root.userPluginDir
        ]

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
                } catch (e) {
                    root.plugins = [];
                    root.lastError = "failed to parse scanner output: " + e;
                    console.warn("[plugins] " + root.lastError);
                    root.refreshed(0);
                }
            }
        }

        onExited: {
            root.scanning = false;
        }
    }

    Component.onCompleted: Qt.callLater(root.refresh)
}
