#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}
test_dir=$(mktemp -d /tmp/pdfseal-stamps.XXXXXX)
trap 'rg "PASS|FAIL|ERROR|WARN|STAMP_DPR" "$test_dir/output.log" || true; rm -rf -- "$test_dir"' EXIT
for module in Commons Ui; do ln -s "$shell_dir/$module" "$test_dir/$module"; done
cp "$plugin_dir"/*.qml "$test_dir/"
cp -a "$plugin_dir/assets" "$test_dir/"
ln -s "$plugin_dir/bin" "$test_dir/bin"
cp "$plugin_dir/tests/stamp-smoke.qml" "$test_dir/shell.qml"
python3 "$plugin_dir/tests/make-fixture.py" "$test_dir/input.pdf"
PDFSEAL_TEST_DIR="$test_dir" timeout 45 quickshell -p "$test_dir" --no-color >"$test_dir/output.log" 2>&1
rg -q 'PASS: all eight stamps' "$test_dir/output.log"
pdftoppm -f 1 -l 1 -singlefile -scale-to 1600 -png "$test_dir/stamps.pdf" "$test_dir/exported"
if [[ -n ${1:-} ]]; then
    mkdir -p -- "$1"
    cp "$test_dir"/onscreen-*.png "$test_dir/exported.png" "$test_dir/stamps.pdf" "$1/"
fi
python3 "$plugin_dir/tests/stamp-smoke.py" "$test_dir"
if rg 'ERROR|TypeError|ReferenceError|Cannot assign|Cannot open:' "$test_dir/output.log"; then exit 1; fi
