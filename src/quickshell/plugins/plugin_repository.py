#!/usr/bin/env python3
"""Install and refresh independent Serpantinum plugins from Git repositories.

Untracked legacy installs are never overwritten. Tracked installs are replaced
only when their recorded content hash still matches, so user edits survive.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

SOURCE_FILE = ".serpantinum-source.json"


def digest(folder):
    result = hashlib.sha256()
    for path in sorted(folder.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Symlinks are not supported: {path}")
        if not path.is_file() or path.name == SOURCE_FILE or ".git" in path.parts:
            continue
        relative = path.relative_to(folder).as_posix().encode("utf-8")
        result.update(len(relative).to_bytes(8, "big"))
        result.update(relative)
        data = path.read_bytes()
        result.update(len(data).to_bytes(8, "big"))
        result.update(data)
    return result.hexdigest()


def valid_file(folder, name, label):
    name = str(name or "").strip()
    if not name:
        raise ValueError(f"{label} is required")
    target = (folder / name).resolve()
    if not target.is_relative_to(folder.resolve()) or not target.is_file():
        raise ValueError(f"{label} not found: {name}")
    return name


def manifests(repo, host_api):
    root_manifest = repo / "plugin.json"
    if root_manifest.is_file():
        paths = [root_manifest]
    else:
        paths = sorted(child / "plugin.json" for child in repo.iterdir()
                       if child.is_dir() and (child / "plugin.json").is_file())
    if not paths:
        raise ValueError("No plugin.json at repository root or in direct subfolders")
    found = {}
    for path in paths:
        folder = path.parent
        data = json.loads(path.read_text(encoding="utf-8"))
        identifier = str(data.get("id") or "").strip()
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]*", identifier):
            raise ValueError(f"Invalid plugin id in {path.relative_to(repo)}")
        if identifier in found:
            raise ValueError(f"Duplicate plugin id: {identifier}")
        api = int(data.get("apiVersion", data.get("api_version", 1)))
        if api > host_api:
            raise ValueError(f"{identifier} requires API {api}, host provides {host_api}")
        valid_file(folder, data.get("entry") or "Plugin.qml", f"{identifier} entry")
        if data.get("barEntry"):
            valid_file(folder, data["barEntry"], f"{identifier} barEntry")
        if data.get("settingsEntry"):
            valid_file(folder, data["settingsEntry"], f"{identifier} settingsEntry")
        if data.get("iconImage"):
            valid_file(folder, data["iconImage"], f"{identifier} iconImage")
        entries = data.get("barEntries", [])
        if not isinstance(entries, list):
            raise ValueError(f"{identifier} barEntries must be an array")
        seen = set()
        for entry in entries:
            if not isinstance(entry, dict) or not entry.get("id") or entry["id"] in seen:
                raise ValueError(f"{identifier} has invalid/duplicate barEntries")
            seen.add(entry["id"])
            valid_file(folder, entry.get("entry"), f"{identifier} bar entry")
        found[identifier] = folder
    return found


def metadata(folder):
    try:
        return json.loads((folder / SOURCE_FILE).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def clone(url, destination):
    result = subprocess.run(
        ["git", "clone", "--depth", "1", "--", url, str(destination)],
        capture_output=True, text=True, timeout=100, check=False,
    )
    if result.returncode:
        raise ValueError((result.stderr or result.stdout or "git clone failed").strip().splitlines()[-1])


def sync_repository(url, root, host_api):
    root.mkdir(parents=True, exist_ok=True)
    installed, updated, unchanged, skipped = [], [], [], []
    with tempfile.TemporaryDirectory(prefix=".plugin-sync-", dir=root) as temp_name:
        temp = pathlib.Path(temp_name)
        repo = temp / "repo"
        clone(url, repo)
        sources = manifests(repo, host_api)
        staged_root = temp / "staged"
        staged_root.mkdir()
        changes = []
        for identifier, folder in sources.items():
            dest = root / identifier
            if dest.is_symlink():
                skipped.append(identifier + " (symlink)")
                continue
            if dest.exists():
                saved = metadata(dest)
                if not saved or saved.get("url") != url or saved.get("managed") is not True:
                    skipped.append(identifier + " (existing/unmanaged)")
                    continue
                if digest(dest) != saved.get("digest"):
                    skipped.append(identifier + " (local modifications)")
                    continue
                if digest(dest) == digest(folder):
                    unchanged.append(identifier)
                    continue
            staged = staged_root / identifier
            shutil.copytree(folder, staged, ignore=shutil.ignore_patterns(".git"))
            fingerprint = digest(staged)
            (staged / SOURCE_FILE).write_text(json.dumps({
                "url": url, "managed": True, "digest": fingerprint
            }, ensure_ascii=False) + "\n", encoding="utf-8")
            changes.append((identifier, staged, dest))

        # All manifests and staged files are checked before touching installed dirs.
        backup_root = temp / "backup"
        backup_root.mkdir()
        processed = []
        try:
            for identifier, staged, dest in changes:
                backup = backup_root / identifier
                was_existing = dest.exists()
                if was_existing:
                    dest.rename(backup)
                try:
                    staged.rename(dest)
                except Exception:
                    if was_existing:
                        backup.rename(dest)
                    raise
                processed.append((dest, backup if was_existing else None))
                (updated if was_existing else installed).append(identifier)
        except Exception:
            for dest, backup in reversed(processed):
                if dest.exists():
                    shutil.rmtree(dest)
                if backup is not None:
                    backup.rename(dest)
            raise
    return {"installed": installed, "updated": updated,
            "unchanged": unchanged, "skipped": skipped}


def refresh(root, host_api):
    urls = set()
    if root.is_dir():
        for folder in root.iterdir():
            if not folder.is_dir() or folder.is_symlink():
                continue
            saved = metadata(folder)
            if saved and saved.get("managed") and saved.get("url"):
                urls.add(saved["url"])
    summary = {"installed": [], "updated": [], "unchanged": [],
               "skipped": [], "warnings": []}
    for url in sorted(urls):
        try:
            result = sync_repository(url, root, host_api)
            for key, values in result.items():
                summary[key].extend(values)
        except Exception as exc:
            summary["warnings"].append(f"{url}: {exc}")
    if not urls:
        summary["warnings"].append(
            "No tracked sources. Re-enter a Git URL once to discover new plugins."
        )
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "refresh"))
    parser.add_argument("args", nargs="+")
    args = parser.parse_args(argv)
    try:
        if args.action == "install":
            if len(args.args) != 3:
                parser.error("install requires url root host_api")
            url, path, api = args.args
            if not url.strip():
                raise ValueError("Enter a Git repository URL")
            result = sync_repository(url.strip(), pathlib.Path(path).expanduser(), int(api))
        else:
            if len(args.args) != 2:
                parser.error("refresh requires root host_api")
            path, api = args.args
            result = refresh(pathlib.Path(path).expanduser(), int(api))
        print(json.dumps({"ok": True, **result}, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
