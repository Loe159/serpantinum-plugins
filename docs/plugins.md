# Serpantinum plugin system (experimental)

This branch contains the first plugin-loader MVP for Serpantinum.

## Goals

The first version deliberately keeps the core shell unchanged. A plugin is discovered from a manifest and loaded as a QML entry point by `PluginHost`. Later iterations can add dedicated bar, panel, launcher and desktop-widget slots without coupling discovery to those surfaces.

## Plugin locations

Plugins are discovered from two roots:

1. Built-in plugins: `$QS_DIR/plugins/builtin/<plugin-id>/plugin.json`
2. User plugins: `${XDG_CONFIG_HOME:-~/.config}/serpantinum/plugins/<plugin-id>/plugin.json`

If the same `id` exists in both roots, the user plugin wins. This makes local development and overriding built-ins possible without modifying the built-in copy.

## Manifest

Minimal `plugin.json`:

```json
{
  "id": "author/example",
  "name": "Example",
  "version": "0.1.0",
  "apiVersion": 1,
  "entry": "Plugin.qml",
  "enabledByDefault": true
}
```

`apiVersion` must not be newer than `PluginManager.apiVersion`. The loader verifies that the declared entry file exists before exposing the plugin to `PluginHost`.

## Entry contract

The entry QML root must expose these properties:

```qml
property var pluginMetadata: ({})
property string pluginDirectory: ""
```

`PluginHost` fills them immediately after loading the component.

A plugin entry may create headless services, timers, IPC handlers or independent Wayland surfaces. Dedicated injection points for the Serpantinum bar and launcher are intentionally left for the next phase.

## Enable / disable

Plugins default to `enabledByDefault`. They can be overridden through the normal Serpantinum settings object:

```json
{
  "plugins": {
    "serpantinum.timer": {
      "enabled": false
    }
  }
}
```

The loader also understands optional `plugins.disabled` and `plugins.enabled` arrays.

## Built-in Timer smoke test

The MVP ships a tiny countdown timer plugin. It validates manifest discovery, dynamic QML loading, ThemeBackend access, an independent panel and IPC.

```bash
qs ipc call plugin-timer toggle
qs ipc call plugin-timer start 300
qs ipc call plugin-timer pause
qs ipc call plugin-timer reset
```

The panel intentionally does not integrate into the bar yet. The next milestone is a stable plugin API for `bar`, `panel`, `launcher` and shared service/state entries.

## Security

Plugins are trusted QML code and are **not sandboxed**. A plugin loaded by Serpantinum runs with the same user privileges as the shell and can use Quickshell APIs or spawn processes. Only install plugins whose source you trust.

## Current limitations

- No plugin store or updater.
- No dependency resolution.
- No permission model or sandbox.
- No hot reload beyond rescanning/reloading the shell.
- No stable Serpantinum UI import module for arbitrary external QML yet.
- No first-class bar, launcher or desktop-widget registration API yet.

These constraints are intentional for the MVP: validate discovery and loading first, then add extension points one at a time.
