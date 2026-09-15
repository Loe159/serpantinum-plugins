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
    property var instances: ({})
    property bool scanning: false
    property string lastError: ""

    property bool installing: false
    property bool installSucceeded: false
    property string installMessage: ""
    property string pendingInstallUrl: ""

    signal refreshed(int count)
    signal pluginLoaded(string pluginId)
    signal pluginFailed(string pluginId, string reason)
    signal installFinished(bool success, string message)

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

    function installerScript() {
        return [
            "import json, pathlib, re, shutil, subprocess, sys, tempfile",
            "url = sys.argv[1].strip()",
            "root = pathlib.Path(sys.argv[2]).expanduser()",
            "host_api = int(sys.argv[3])",
            "tmp = None",
            "try:",
            "    if not url:",
            "        raise ValueError('Enter a Git repository URL')",
            "    root.mkdir(parents=True, exist_ok=True)",
            "    tmp = pathlib.Path(tempfile.mkdtemp(prefix='.plugin-install-', dir=str(root)))",
            "    repo = tmp / 'repo'",
            "    proc = subprocess.run(['git', 'clone', '--depth', '1', '--', url, str(repo)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)",
            "    if proc.returncode != 0:",
            "        detail = (proc.stderr or proc.stdout or 'git clone failed').strip().splitlines()[-1]",
            "        raise ValueError(detail)",
            "    manifest = repo / 'plugin.json'",
            "    if not manifest.is_file():",
            "        raise ValueError('plugin.json must be at the repository root')",
            "    data = json.loads(manifest.read_text(encoding='utf-8'))",
            "    plugin_id = str(data.get('id') or '').strip()",
            "    if not plugin_id:",
            "        raise ValueError('plugin.json is missing id')",
            "    api = int(data.get('apiVersion', data.get('api_version', 1)))",
            "    if api > host_api:",
            "        raise ValueError(f'plugin requires API {api}, host provides {host_api}')",
            "    entry = str(data.get('entry') or 'Plugin.qml')",
            "    if not (repo / entry).is_file():",
            "        raise ValueError(f'entry not found: {entry}')",
            "    dirname = re.sub(r'[^A-Za-z0-9._-]+', '-', plugin_id).strip('-') or 'plugin'",
            "    dest = root / dirname",
            "    if dest.exists():",
            "        raise ValueError(f'{plugin_id} is already installed')",
            "    shutil.rmtree(repo / '.git', ignore_errors=True)",
            "    shutil.move(str(repo), str(dest))",
            "    print(json.dumps({'ok': True, 'id': plugin_id, 'path': str(dest)}))",
            "except Exception as exc:",
            "    print(json.dumps({'ok': False, 'error': str(exc)}))",
            "finally:",
            "    if tmp is not None:",
            "        shutil.rmtree(tmp, ignore_errors=True)"
        ].join("\n");
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

    function supportsTopbar(plugin) {
        if (!plugin) return false;
        if (plugin.barEntry) return true;
        if (Array.isArray(plugin.capabilities) && plugin.capabilities.indexOf("topbar") !== -1) return true;
        return plugin.topbar === true;
    }

    function isTopbarEnabled(plugin) {
        if (!plugin || !supportsTopbar(plugin)) return false;
        const perPlugin = pluginSettings(plugin.id);
        if (perPlugin.topbar !== undefined) return !!perPlugin.topbar;
        return plugin.topbarByDefault === true;
    }

    function setTopbarEnabled(pluginId, enabled) {
        updatePluginSetting(pluginId, "topbar", !!enabled);
    }

    function entryUrl(plugin) {
        if (!plugin || !plugin._dir || !plugin.entry) return "";
        return encodeURI("file://" + plugin._dir + "/" + plugin.entry);
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
        installer.command = ["python3", "-c", installerScript(), trimmed, userPluginDir, apiVersion.toString()];
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
        command: ["python3", "-c", root.scannerScript(), root.apiVersion.toString(), root.builtinPluginDir, root.userPluginDir]

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
        onExited: root.scanning = false
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
                        root.installMessage = "Installed " + result.id;
                        root.installFinished(true, root.installMessage);
                        root.refresh();
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

    Component.onCompleted: Qt.callLater(root.refresh)
}
