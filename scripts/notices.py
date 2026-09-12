#!/usr/bin/env python3
"""Collect Rust dependency license texts for the binary distribution."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
metadata = json.loads(subprocess.check_output([
    "cargo", "metadata", "--locked", "--offline", "--format-version", "1",
    "--manifest-path", str(root / "native/Cargo.toml"),
]))
sections = ["PDFSeal Rust dependency notices\n"]
for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"])):
    if package["name"] == "pdfseal-worker":
        continue
    directory = Path(package["manifest_path"]).parent
    sections.append(f'\n{"=" * 72}\n{package["name"]} {package["version"]}\n'
                    f'License: {package.get("license")}\nSource: {package.get("repository")}\n')
    files = [p for p in directory.iterdir()
             if p.is_file() and p.name.upper().startswith(("LICENSE", "COPYING", "UNLICENSE"))]
    if package.get("license_file"):
        license_file = directory / package["license_file"]
        if license_file.is_file() and license_file not in files:
            files.append(license_file)
    for path in sorted(files):
        sections.append(f"\n--- {path.name} ---\n{path.read_text(errors='replace')}\n")
(root / "bin/THIRD_PARTY_NOTICES.txt").write_text("".join(sections))
