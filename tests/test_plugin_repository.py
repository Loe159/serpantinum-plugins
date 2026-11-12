"""Regression tests for Serpantinum's mono- and multi-plugin installer."""
import importlib.util
import json
import pathlib
import shutil
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

    def test_pristine_unmanaged_plugin_is_adopted_with_persistent_backup(self):
        source_plugin = self.source / "ai-agents"
        self.plugin(source_plugin, "ai-agents", version="0.1.0")
        self.commit()
        legacy = self.target / "ai-agents"
        shutil.copytree(source_plugin, legacy)

        self.plugin(source_plugin, "ai-agents", version="0.1.2")
        self.plugin(self.source / "lpic-daily", "lpic-daily", version="0.1.4")
        self.commit()
        result = plugin_repo.sync_repository(str(self.source), self.target, 1)

        self.assertIn("ai-agents", result["updated"])
        self.assertIn("lpic-daily", result["installed"])
        self.assertEqual(json.loads((legacy / "plugin.json").read_text())["version"], "0.1.2")
        self.assertTrue(plugin_repo.metadata(legacy)["managed"])
        backups = list(self.target.glob("ai-agents.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(json.loads((backups[0] / "plugin.json").read_text())["version"], "0.1.0")
        self.assertEqual(plugin_repo.scan_plugins([(self.target, "user")], 1)["errors"], [])
        self.assertEqual(plugin_repo.sync_repository(str(self.source), self.target, 1)["unchanged"],
                         ["ai-agents", "lpic-daily"])

    def test_legacy_migration_rolls_back_on_later_install_failure(self):
        source_plugin = self.source / "ai-agents"
        self.plugin(source_plugin, "ai-agents", version="0.1.0")
        self.commit()
        old = self.target / "ai-agents"
        shutil.copytree(source_plugin, old)
        self.plugin(source_plugin, "ai-agents", version="0.1.2")
        self.plugin(self.source / "lpic-daily", "lpic-daily")
        self.commit()

        rename = pathlib.Path.rename

        def interrupt_second_install(path, target):
            if path.name == "lpic-daily" and path.parent.name == "staged":
                raise OSError("simulated installation error")
            return rename(path, target)

        with patch.object(pathlib.Path, "rename", interrupt_second_install):
            with self.assertRaisesRegex(OSError, "simulated"):
                plugin_repo.sync_repository(str(self.source), self.target, 1)

        self.assertEqual(json.loads((old / "plugin.json").read_text())["version"], "0.1.0")
        self.assertFalse((self.target / "lpic-daily").exists())
        self.assertEqual(list(self.target.glob("ai-agents.backup.*")), [])

    def test_matching_version_but_modified_unmanaged_plugin_stays_untouched(self):
        source_plugin = self.source / "ai-agents"
        self.plugin(source_plugin, "ai-agents", version="0.1.0")
        self.commit()
        legacy = self.target / "ai-agents"
        shutil.copytree(source_plugin, legacy)
        (legacy / "Plugin.qml").write_text("local user customization", encoding="utf-8")
        self.plugin(source_plugin, "ai-agents", version="0.1.2")
        self.commit()

        result = plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertEqual(result["updated"], [])
        self.assertIn("ai-agents (existing/unmanaged)", result["skipped"])
        self.assertEqual((legacy / "Plugin.qml").read_text(), "local user customization")
        self.assertFalse(list(self.target.glob("ai-agents.backup.*")))

    def test_pristine_unmanaged_monoplugin_can_be_adopted(self):
        self.plugin(self.source, "single", version="0.1.0")
        self.commit()
        legacy = self.target / "single"
        shutil.copytree(self.source, legacy, ignore=shutil.ignore_patterns(".git"))
        self.plugin(self.source, "single", version="0.1.2")
        self.commit()

        result = plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertEqual(result["updated"], ["single"])
        self.assertEqual(json.loads((legacy / "plugin.json").read_text())["version"], "0.1.2")
        self.assertEqual(len(list(self.target.glob("single.backup.*"))), 1)

    def test_runtime_bytecode_does_not_block_migration_or_refresh(self):
        self.plugin(self.source, "single", version="1")
        self.commit()
        legacy = self.target / "single"
        shutil.copytree(self.source, legacy, ignore=shutil.ignore_patterns(".git"))
        cache = legacy / "__pycache__/helper.cpython-314.pyc"
        cache.parent.mkdir()
        cache.write_bytes(b"generated at runtime")
        self.plugin(self.source, "single", version="2")
        self.commit()
        self.assertEqual(plugin_repo.sync_repository(str(self.source), self.target, 1)["updated"], ["single"])
        cache.parent.mkdir()
        cache.write_bytes(b"regenerated")
        self.assertEqual(plugin_repo.refresh(self.target, 1)["unchanged"], ["single"])
        # Files other than bytecode remain protected, even in cache directories.
        custom = cache.parent / "custom.py"
        custom.write_text("user code")
        self.assertIn("single (local modifications)", plugin_repo.refresh(self.target, 1)["skipped"])

    def test_explicit_replacement_backs_up_custom_files_and_only_selected_plugin(self):
        for identifier in ("single", "other"):
            self.plugin(self.source / identifier, identifier, version="2")
            self.plugin(self.target / identifier, identifier, version="custom")
        self.commit()
        old_digest = plugin_repo.digest(self.target / "single")
        result = plugin_repo.sync_repository(str(self.source), self.target, 1,
                                             replace_plugins=["single"])
        self.assertEqual(result["updated"], ["single"])
        self.assertIn("other (existing/unmanaged)", result["skipped"])
        backup, = self.target.glob("single.backup.*")
        self.assertEqual(plugin_repo.digest(backup), old_digest)
        self.assertEqual(plugin_repo.refresh(self.target, 1)["unchanged"], ["single"])

    def test_refresh_does_not_contact_sources_from_backups(self):
        backup = self.target / "single.backup.saved"
        self.plugin(backup, "single")
        (backup / plugin_repo.SOURCE_FILE).write_text(json.dumps({
            "managed": True, "url": "https://invalid.example/old-source"}))
        with patch.object(plugin_repo, "sync_repository") as sync:
            plugin_repo.refresh(self.target, 1)
        sync.assert_not_called()

    def test_unknown_explicit_replacement_aborts_before_installation(self):
        self.plugin(self.source, "single")
        self.commit()
        with self.assertRaisesRegex(ValueError, "Unknown replacement"):
            plugin_repo.sync_repository(str(self.source), self.target, 1,
                                        replace_plugins=["typo"])
        self.assertFalse((self.target / "single").exists())

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

    def test_optional_icon_image_valid_and_missing_rejected(self):
        self.plugin(self.source, "single")
        manifest = self.source / "plugin.json"
        data = json.loads(manifest.read_text())
        data["iconImage"] = "assets/lpi.svg"
        manifest.write_text(json.dumps(data), encoding="utf-8")
        icon = self.source / "assets/lpi.svg"
        icon.parent.mkdir(parents=True, exist_ok=True)
        icon.write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
        self.commit()

        result = plugin_repo.sync_repository(str(self.source), self.target, 1)
        self.assertEqual(result["installed"], ["single"])
        self.assertTrue((self.target / "single/assets/lpi.svg").is_file())

        data["iconImage"] = "../../outside.svg"
        manifest.write_text(json.dumps(data), encoding="utf-8")
        self.commit()
        with self.assertRaisesRegex(ValueError, "iconImage not found"):
            plugin_repo.sync_repository(str(self.source), self.path / "other-install", 1)

    def test_scan_ignores_backup_from_legacy_upgrade(self):
        # Regression: the old version was moved to lpic-daily.backup.TIMESTAMP.
        # The scanner previously overwrote the fresh 0.1.1 entry with 0.1.0.
        self.plugin(self.target / "lpic-daily", "lpic-daily", version="0.1.1")
        self.plugin(self.target / "lpic-daily.backup.20261021-0950", "lpic-daily", version="0.1.0")
        result = plugin_repo.scan_plugins([(self.target, "user")], 1)
        self.assertEqual(len(result["plugins"]), 1)
        self.assertEqual(result["plugins"][0]["version"], "0.1.1")
        self.assertEqual(result["errors"], [])

        process = subprocess.run([
            "python3", str(MODULE_PATH), "scan", "1", str(self.path / "missing"), str(self.target)
        ], check=True, capture_output=True, text=True)
        output = json.loads(process.stdout)
        self.assertEqual(output["plugins"][0]["version"], "0.1.1")

    def test_scan_canonical_name_wins_over_other_copy(self):
        # Also protect against copies that are not named like standard backups.
        self.plugin(self.target / "a-old-copy", "lpic-daily", version="0.1.0")
        self.plugin(self.target / "lpic-daily", "lpic-daily", version="0.1.1")
        result = plugin_repo.scan_plugins([(self.target, "user")], 1)
        self.assertEqual(len(result["plugins"]), 1)
        self.assertEqual(result["plugins"][0]["version"], "0.1.1")

    def test_scan_keeps_user_overrides_and_legacy_folder_names(self):
        builtin = self.path / "builtin"
        self.plugin(builtin / "timer", "serpantinum.timer", version="0.1.0")
        self.plugin(self.target / "timer", "serpantinum.timer", version="0.2.0")
        result = plugin_repo.scan_plugins([
            (builtin, "builtin"), (self.target, "user")
        ], 1)
        self.assertEqual(result["plugins"][0]["version"], "0.2.0")
        self.assertEqual(result["plugins"][0]["_source"], "user")

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
