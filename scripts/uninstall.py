#!/usr/bin/env python3
"""Remove PDFSeal's plugin and desktop entry; exported PDFs are untouched."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--no-disable", action="store_true", help="Skip contacting the running shell")
args = parser.parse_args()
config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
plugin = config / "omarchy/plugins/arkane.pdfseal"
if plugin.exists():
    if plugin.is_symlink() or json.loads((plugin / "manifest.json").read_text())["id"] != "arkane.pdfseal":
        parser.error("The installed folder is not a PDFSeal plugin")
    if not args.no_disable:
        subprocess.run(["omarchy", "plugin", "disable", "arkane.pdfseal"], check=True)
    shutil.rmtree(plugin)
desktop = data / "applications/omarchy-pdfseal.desktop"
if desktop.is_file() and "Exec=omarchy-shell shell summon arkane.pdfseal {}" in desktop.read_text():
    desktop.unlink()
print("Removed PDFSeal. Exported PDFs and prior installation backups were preserved.")
