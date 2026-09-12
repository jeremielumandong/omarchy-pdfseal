#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
bash "$plugin_dir/scripts/build.sh"
stage=$(mktemp -d /tmp/pdfseal-package.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/omarchy-pdfseal/bin" "$stage/omarchy-pdfseal/scripts"
cp "$plugin_dir"/*.qml "$plugin_dir/manifest.json" "$plugin_dir/README.md" "$plugin_dir/icon.svg" "$stage/omarchy-pdfseal/"
if [[ -d "$plugin_dir/assets" ]]; then cp -a "$plugin_dir/assets" "$stage/omarchy-pdfseal/"; fi
cp "$plugin_dir/bin/pdfseal-worker" "$stage/omarchy-pdfseal/bin/"
cp "$plugin_dir/bin/THIRD_PARTY_NOTICES.txt" "$stage/omarchy-pdfseal/bin/"
cp "$plugin_dir/scripts/install.py" "$plugin_dir/scripts/uninstall.py" "$stage/omarchy-pdfseal/scripts/"
if command -v omarchy >/dev/null; then omarchy plugin validate "$stage/omarchy-pdfseal"; fi
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$plugin_dir/manifest.json")
architecture=$(uname -m)
mkdir -p "$plugin_dir/release"
archive="$plugin_dir/release/omarchy-pdfseal-$version-linux-$architecture.tar.gz"
tar -czf "$archive" -C "$stage" omarchy-pdfseal
(cd "$plugin_dir/release" && sha256sum "$(basename "$archive")") > "$archive.sha256"
echo "Created $archive"
