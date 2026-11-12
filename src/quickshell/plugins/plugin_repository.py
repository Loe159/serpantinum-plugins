#!/usr/bin/env python3
"""Install and refresh independent Serpantinum plugins from Git repositories.

Untracked legacy installs are migrated only if identical to a known Git revision,
with the original retained as a backup. Tracked installs are replaced only when
their recorded content hash still matches, so user edits survive.
"""
import argparse
import datetime
import hashlib
import io
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid

SOURCE_FILE = ".serpantinum-source.json"


def generated_file(path):
    """Python bytecode is runtime output, not a plugin customization."""
    return "__pycache__" in path.parts and path.suffix == ".pyc"


def digest(folder):
    result = hashlib.sha256()
    for path in sorted(folder.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Symlinks are not supported: {path}")
        if not path.is_file() or path.name == SOURCE_FILE or ".git" in path.parts or generated_file(path):
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


def backup_directory(folder):
    return bool(re.search(r"(?:[.]backup(?:[.].*)?|[.]bak(?:[.].*)?|[-_]backup(?:[-_].*)?)$", folder.name, re.I))


def scan_plugins(roots, host_api):
    """Discover plugins; never let a backup shadow an active installation."""
    plugins = {}
    errors = []
    for root, source in roots:
        base = pathlib.Path(root).expanduser()
        if not base.is_dir():
            continue
        for manifest in sorted(base.glob("*/plugin.json")):
            folder = manifest.parent
            # A backup kept next to a plugin is not an installable plugin.
            if backup_directory(folder):
                continue
            try:
                data = json.loads(manifest.read_text(encoding="utf-8"))
                identifier = str(data.get("id") or folder.name).strip()
                if not identifier:
                    raise ValueError("missing plugin id")
                api = int(data.get("apiVersion", data.get("api_version", 1)))
                if api > host_api:
                    raise ValueError(f"requires plugin API {api}, host provides {host_api}")
                entry = valid_file(folder, data.get("entry") or "Plugin.qml", "entry")
                bar_entry = str(data.get("barEntry") or "").strip()
                if bar_entry:
                    valid_file(folder, bar_entry, "bar entry")
                settings_entry = str(data.get("settingsEntry") or "").strip()
                if settings_entry:
                    valid_file(folder, settings_entry, "settings entry")
                icon_image = str(data.get("iconImage") or "").strip()
                if icon_image:
                    valid_file(folder, icon_image, "icon image")
                bar_entries = data.get("barEntries") or []
                if not isinstance(bar_entries, list):
                    raise ValueError("barEntries must be an array")
                seen = set()
                for item in bar_entries:
                    if not isinstance(item, dict):
                        raise ValueError("barEntries items must be objects")
                    item_id = str(item.get("id") or "").strip()
                    item_entry = str(item.get("entry") or "").strip()
                    if not item_id or not item_entry:
                        raise ValueError("barEntries items require id and entry")
                    if item_id in seen:
                        raise ValueError(f"duplicate bar entry id: {item_id}")
                    seen.add(item_id)
                    valid_file(folder, item_entry, "bar entry")

                old = plugins.get(identifier)
                if old and old["_source"] == source:
                    # Real installation directory wins over duplicate copies.
                    # Keep legacy custom folder names if no canonical one exists.
                    old_is_canonical = pathlib.Path(old["_dir"]).name == identifier
                    new_is_canonical = folder.name == identifier
                    if old_is_canonical or not new_is_canonical:
                        if not old_is_canonical and not new_is_canonical:
                            errors.append({
                                "manifest": str(manifest),
                                "error": f"duplicate plugin id {identifier}; kept {old['_manifest']}",
                            })
                        continue

                data["id"] = identifier
                data["apiVersion"] = api
                data["entry"] = entry
                if bar_entry:
                    data["barEntry"] = bar_entry
                if settings_entry:
                    data["settingsEntry"] = settings_entry
                data["_dir"] = str(folder.resolve())
                data["_manifest"] = str(manifest.resolve())
                data["_source"] = source
                plugins[identifier] = data
            except Exception as exc:
                errors.append({"manifest": str(manifest), "error": str(exc)})
    return {"plugins": [plugins[key] for key in sorted(plugins)], "errors": errors}


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


def pristine_legacy_install(repo, source, dest, identifier):
    """Only adopt an untracked plugin if every file matches an upstream revision.

    Compare complete directory contents, not just the version in plugin.json.
    Never adopt a Git checkout, an install with source metadata, or symlinks.
    """
    if (dest / SOURCE_FILE).exists() or (dest / ".git").exists():
        return False
    try:
        installed = json.loads((dest / "plugin.json").read_text(encoding="utf-8"))
        version = installed.get("version")
        if installed.get("id") != identifier or not isinstance(version, str):
            return False
        installed_digest = digest(dest)
        relative = source.relative_to(repo)
        pathspec = relative.as_posix()
        manifest = "plugin.json" if pathspec == "." else pathspec + "/plugin.json"

        def git(*args, timeout=40):
            return subprocess.run(
                ["git", "-C", str(repo), *args],
                capture_output=True, timeout=timeout, check=False,
            )

        shallow = git("rev-parse", "--is-shallow-repository")
        if shallow.returncode != 0:
            return False
        if shallow.stdout.strip() == b"true":
            # Bound the amount of history fetched for legacy migration.
            fetched = git("fetch", "--deepen=40", "origin", timeout=100)
            if fetched.returncode != 0:
                return False
        history = git("rev-list", "-n", "40", "HEAD", "--", pathspec)
        if history.returncode != 0:
            return False

        for commit in history.stdout.decode("ascii").splitlines():
            prior = git("show", commit + ":" + manifest)
            if prior.returncode:
                continue
            try:
                old_manifest = json.loads(prior.stdout)
            except ValueError:
                continue
            if old_manifest.get("id") != identifier or old_manifest.get("version") != version:
                continue
            args = ["archive", "--format=tar", commit]
            if pathspec != ".":
                args.append(pathspec)
            archived = git(*args, timeout=100)
            if archived.returncode:
                continue
            files = []
            with tarfile.open(fileobj=io.BytesIO(archived.stdout), mode="r:") as bundle:
                for member in bundle:
                    if member.isdir():
                        continue
                    if not member.isfile():
                        files = []
                        break
                    path = pathlib.PurePosixPath(member.name)
                    if pathspec != ".":
                        path = path.relative_to(pathlib.PurePosixPath(pathspec))
                    if path.name == SOURCE_FILE or ".git" in path.parts or generated_file(path):
                        continue
                    entry = bundle.extractfile(member)
                    if entry is None:
                        files = []
                        break
                    files.append((path.as_posix().encode("utf-8"), entry.read()))
            if not files:
                continue
            old_digest = hashlib.sha256()
            for path, data in sorted(files):
                old_digest.update(len(path).to_bytes(8, "big"))
                old_digest.update(path)
                old_digest.update(len(data).to_bytes(8, "big"))
                old_digest.update(data)
            if old_digest.hexdigest() == installed_digest:
                return True
    except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError):
        return False
    return False


def sync_repository(url, root, host_api, *, replace_plugins=()):
    """Explicit replacement retains the complete previous install as a backup.

    Automatic refresh never opts into replacement of customized installations.
    """
    root.mkdir(parents=True, exist_ok=True)
    installed, updated, unchanged, skipped = [], [], [], []
    legacy_adoptions = set()
    with tempfile.TemporaryDirectory(prefix=".plugin-sync-", dir=root) as temp_name:
        temp = pathlib.Path(temp_name)
        repo = temp / "repo"
        clone(url, repo)
        sources = manifests(repo, host_api)
        unknown = set(replace_plugins) - sources.keys()
        if unknown:
            raise ValueError("Unknown replacement plugin ids: " + ", ".join(sorted(unknown)))
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
                if identifier in replace_plugins:
                    legacy_adoptions.add(identifier)
                elif not saved or saved.get("url") != url or saved.get("managed") is not True:
                    if pristine_legacy_install(repo, folder, dest, identifier):
                        legacy_adoptions.add(identifier)
                    else:
                        skipped.append(identifier + " (existing/unmanaged)")
                        continue
                elif digest(dest) != saved.get("digest"):
                    skipped.append(identifier + " (local modifications)")
                    continue
                elif digest(dest) == digest(folder):
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
                persistent_backup = identifier in legacy_adoptions
                if persistent_backup:
                    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
                    backup = root / f"{identifier}.backup.{stamp}-{uuid.uuid4().hex[:8]}"
                if was_existing:
                    dest.rename(backup)
                try:
                    staged.rename(dest)
                except Exception:
                    if was_existing:
                        backup.rename(dest)
                    raise
                # Rollback must restore either kind of backup on later failures.
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
            if not folder.is_dir() or folder.is_symlink() or backup_directory(folder):
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
    parser.add_argument("action", choices=("install", "refresh", "scan"))
    parser.add_argument("args", nargs="+")
    parser.add_argument("--replace-plugin", action="append", default=[], metavar="ID",
                        help="explicitly replace this plugin, keeping a persistent backup (install only)")
    args = parser.parse_args(argv)
    if args.replace_plugin and args.action != "install":
        parser.error("--replace-plugin requires install")
    try:
        if args.action == "scan":
            if len(args.args) != 3:
                parser.error("scan requires host_api builtin_dir user_dir")
            api, builtin, user = args.args
            print(json.dumps(
                scan_plugins([(builtin, "builtin"), (user, "user")], int(api)),
                ensure_ascii=False,
            ))
            return 0
        if args.action == "install":
            if len(args.args) != 3:
                parser.error("install requires url root host_api")
            url, path, api = args.args
            if not url.strip():
                raise ValueError("Enter a Git repository URL")
            result = sync_repository(url.strip(), pathlib.Path(path).expanduser(), int(api),
                                     replace_plugins=args.replace_plugin)
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
