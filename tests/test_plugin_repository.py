"""Regression tests for Serpantinum's mono- and multi-plugin installer."""
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "src/quickshell/plugins/plugin_repository.py"
SPEC = importlib.util.spec_from_file_location("plugin_repository", MODULE_PATH)
plugin_repo = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(plugin_repo)


class RepoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = pathlib.Path(self.tmp.name)
        self.source = self.path / "source"
        self.target = self.path / "installed"
        self.source.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Plugin Tests")
        self.git("config", "user.email", "plugin-tests@example.invalid")

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.source), *args],
                       check=True, capture_output=True, text=True)

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture")

    def plugin(self, folder, identifier, version="1", valid=True):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "plugin.json").write_text(json.dumps({
            "id": identifier, "version": version, "apiVersion": 1,
            "entry": "Plugin.qml" if valid else "NoSuchFile.qml",
        }), encoding="utf-8")
        (folder / "Plugin.qml").write_text(
            "import QtQuick\nItem {}\n", encoding="utf-8"
        )

    def test_monoplugin_install_refresh_and_user_modifications(self):
        self.plugin(self.source, "single")
        self.commit()
        one = plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertEqual(one["installed"], ["single"])
        self.assertEqual(plugin_repo.sync_repository(str(self.source), self.target, 1)["unchanged"], ["single"])
        self.plugin(self.source, "single", version="2")
        self.commit()
        update = plugin_repo.refresh(self.target, 1)
        self.assertEqual(update["updated"], ["single"])
        self.assertEqual(json.loads((self.target / "single/plugin.json").read_text())["version"], "2")
        (self.target / "single/Plugin.qml").write_text("local edit", encoding="utf-8")
        self.plugin(self.source, "single", version="3")
        self.commit()
        refused = plugin_repo.refresh(self.target, 1)
        self.assertEqual(refused["updated"], [])
        self.assertTrue(any("local modifications" in x for x in refused["skipped"]))
        self.assertEqual((self.target / "single/Plugin.qml").read_text(), "local edit")

    def test_multi_plugin_adds_missing_without_overwriting_legacy(self):
        old = self.target / "ai-agents"
        self.plugin(old, "ai-agents", version="old-local")
        self.plugin(self.source / "ai-agents", "ai-agents", version="new")
        self.plugin(self.source / "lpic-daily", "lpic-daily")
        self.commit()
        added = plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertEqual(added["installed"], ["lpic-daily"])
        self.assertTrue(any("ai-agents" in x for x in added["skipped"]))
        self.assertEqual(json.loads((old / "plugin.json").read_text())["version"], "old-local")
        self.plugin(self.source / "third-plugin", "third-plugin")
        self.commit()
        refresh = plugin_repo.refresh(self.target, 1)
        self.assertEqual(refresh["installed"], ["third-plugin"])
        self.assertEqual(json.loads((old / "plugin.json").read_text())["version"], "old-local")

    def test_invalid_subplugin_aborts_without_partial_install(self):
        self.plugin(self.source / "valid", "valid")
        self.plugin(self.source / "invalid", "invalid", valid=False)
        self.commit()
        with self.assertRaisesRegex(ValueError, "entry not found"):
            plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertFalse((self.target / "valid").exists())

    def test_existing_unmanaged_mono_install_is_preserved(self):
        self.plugin(self.source, "single")
        self.commit()
        self.plugin(self.target / "single", "single", version="custom")
        result = plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertEqual(result["installed"], [])
        self.assertIn("single (existing/unmanaged)", result["skipped"])
        self.assertEqual(json.loads((self.target / "single/plugin.json").read_text())["version"], "custom")

    def test_api_version_validation(self):
        self.plugin(self.source, "single")
        data = json.loads((self.source / "plugin.json").read_text())
        data["apiVersion"] = 10
        (self.source / "plugin.json").write_text(json.dumps(data))
        self.commit()
        with self.assertRaisesRegex(ValueError, "requires API"):
            plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertFalse((self.target / "single").exists())

    def test_refresh_without_tracked_source(self):
        self.assertTrue(plugin_repo.refresh(self.target, 1)["warnings"])

    def test_source_failure_keeps_installed_plugin(self):
        self.plugin(self.source, "single")
        self.commit()
        plugin_repo.sync_repository(str(self.source), self.target, 1)
        meta = self.target / "single" / plugin_repo.SOURCE_FILE
        data = json.loads(meta.read_text())
        data["url"] = "/nonexistent/never-created-plugin-repository"
        meta.write_text(json.dumps(data))
        result = plugin_repo.refresh(self.target, 1)
        self.assertEqual(result["updated"], [])
        self.assertTrue(result["warnings"])
        self.assertTrue((self.target / "single/Plugin.qml").is_file())


if __name__ == "__main__":
    unittest.main()
