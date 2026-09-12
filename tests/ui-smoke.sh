#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}
test_dir=$(mktemp -d /tmp/pdfseal-ui-smoke.XXXXXX)
trap 'cat "$test_dir/output.log" 2>/dev/null; rm -rf -- "$test_dir"' EXIT
for module in Commons Ui; do
    ln -s "$shell_dir/$module" "$test_dir/$module"
done
cp "$plugin_dir"/*.qml "$test_dir/"
ln -s "$plugin_dir/bin" "$test_dir/bin"
cp "$plugin_dir/tests/ui-smoke.qml" "$test_dir/shell.qml"
python3 "$plugin_dir/tests/make-fixture.py" "$test_dir/input.pdf"
PDFSEAL_TEST_DIR="$test_dir" timeout 20 quickshell -p "$test_dir" --no-color >"$test_dir/output.log" 2>&1
rg -q 'PASS: PDFSeal widget' "$test_dir/output.log"
pdftotext "$test_dir/signed.pdf" - | rg -q 'Updated text'
if rg 'ERROR|TypeError|ReferenceError|Cannot assign|Cannot open:' "$test_dir/output.log"; then
    exit 1
fi
