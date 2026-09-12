#!/usr/bin/env python3
"""Install the prebuilt native plugin without root or source compilation."""
import argparse
import hashlib
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

PLUGIN_ID = "arkane.pdfseal"


def stage_runtime(staged):
    """Give changed QML fresh URLs even if the shell retains its component cache."""
    names = sorted(p.name for p in staged.iterdir() if p.suffix == '.qml' or p.name in ('bin', 'assets'))
    fingerprint = hashlib.sha256()
    for name in names:
        entry = staged / name
        files = sorted(entry.rglob('*')) if entry.is_dir() else [entry]
        for path in files:
            if path.is_file():
                fingerprint.update(str(path.relative_to(staged)).encode())
                fingerprint.update(b'\0')
                fingerprint.update(path.read_bytes())
    runtime = staged / ('app-' + fingerprint.hexdigest()[:16])
    runtime.mkdir()
    for name in names:
        entry = staged / name
        if entry.is_dir():
            shutil.copytree(entry, runtime / name)
        else:
            shutil.copy2(entry, runtime / name)
    manifest_path = staged / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['entryPoints']['barWidget'] = runtime.name + '/Widget.qml'
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    return runtime


def ensure_editor_saved():
    result = subprocess.run(['hyprctl', '-j', 'clients'], check=True, capture_output=True, text=True, timeout=5)
    for client in json.loads(result.stdout):
        title = client.get('title', '')
        if client.get('class') == 'org.quickshell' and title.endswith('PDFSeal') and title.startswith('• '):
            raise RuntimeError('Export and close your unsaved PDFSeal document before updating.')


def enable_plugin():
    # rescanPlugins starts asynchronous discovery; its IPC reply arrives before
    # the registry necessarily contains a newly installed plugin.
    subprocess.run(["omarchy-shell", "shell", "rescanPlugins"], check=True, timeout=15)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        result = subprocess.run(
            ["omarchy", "plugin", "list", "--json"],
            check=True, capture_output=True, text=True, timeout=5,
        )
        if any(plugin.get("id") == PLUGIN_ID for plugin in json.loads(result.stdout)):
            subprocess.run(["omarchy", "plugin", "enable", PLUGIN_ID], check=True, timeout=15)
            return
        time.sleep(0.2)
    raise RuntimeError("PDFSeal was installed, but Omarchy has not discovered it yet. "
                       "Run: omarchy-shell shell rescanPlugins && omarchy plugin enable arkane.pdfseal")


def install():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-enable", action="store_true", help="Copy files without contacting the running shell")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    worker = source / "bin/pdfseal-worker"
    if not worker.is_file():
        parser.error("Missing bin/pdfseal-worker. Run bash scripts/build.sh first, or use a release archive.")
    if not args.no_enable:
        for program in ("omarchy", "omarchy-shell"):
            if not shutil.which(program):
                parser.error(f"Missing {program}. PDFSeal requires the Omarchy shell.")
    for program in ("qpdf", "pdftoppm"):
        if not shutil.which(program):
            parser.error(f"Missing {program}. Install the qpdf and poppler packages.")
    subprocess.run([str(worker), "--version"], check=True, stdout=subprocess.DEVNULL)
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    destination = config / "omarchy/plugins" / PLUGIN_ID
    if destination.exists() and not args.no_enable:
        ensure_editor_saved()
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Stage outside the discovery directory; the shell never sees partial QML.
    with tempfile.TemporaryDirectory(prefix="pdfseal-install-", dir=config) as scratch:
        staged = Path(scratch) / PLUGIN_ID
        staged.mkdir()
        for name in [p.name for p in source.glob('*.qml')] + ["manifest.json", "README.md", "icon.svg"]:
            shutil.copy2(source / name, staged / name)
        if (source / 'assets').is_dir():
            shutil.copytree(source / 'assets', staged / 'assets')
        (staged / "bin").mkdir()
        shutil.copy2(worker, staged / "bin/pdfseal-worker")
        notices = source / "bin/THIRD_PARTY_NOTICES.txt"
        if notices.is_file():
            shutil.copy2(notices, staged / "bin/THIRD_PARTY_NOTICES.txt")
        (staged / "scripts").mkdir()
        shutil.copy2(source / "scripts/uninstall.py", staged / "scripts/uninstall.py")
        stage_runtime(staged)
        if shutil.which("omarchy"):
            subprocess.run(["omarchy", "plugin", "validate", str(staged)], check=True)
        backup = None
        if destination.exists():
            if destination.is_symlink() or json.loads((destination / "manifest.json").read_text())["id"] != PLUGIN_ID:
                parser.error(f"Refusing to replace an unrelated folder: {destination}")
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
            backup = state / "omarchy-pdfseal/backups" / stamp
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(destination), str(backup))
        try:
            staged.rename(destination)
        except Exception:
            if backup:
                shutil.move(str(backup), str(destination))
            raise
    applications = data / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    icon = str(destination / "icon.svg").replace("\\", "\\\\").replace("\n", "\\n")
    (applications / "omarchy-pdfseal.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=PDFSeal\n"
        "Comment=Native local PDF signing and annotation\n"
        "Exec=omarchy-shell shell summon arkane.pdfseal {}\n"
        f"Icon={icon}\nTerminal=false\nCategories=Office;\n"
        "Keywords=PDF;Sign;Annotate;Compress;\n"
    )
    print(f"Installed PDFSeal to {destination}")
    if args.no_enable:
        print("Enable with: omarchy-shell shell rescanPlugins && omarchy plugin enable arkane.pdfseal")
    else:
        enable_plugin()


if __name__ == "__main__":
    install()
