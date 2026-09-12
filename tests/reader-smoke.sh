#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}
test_dir=$(mktemp -d /tmp/pdfseal-reader.XXXXXX)
trap 'cat "$test_dir/output.log" 2>/dev/null; rm -rf -- "$test_dir"' EXIT
for module in Commons Ui; do ln -s "$shell_dir/$module" "$test_dir/$module"; done
cp "$plugin_dir"/*.qml "$test_dir/"
cp -a "$plugin_dir/assets" "$test_dir/"
ln -s "$plugin_dir/bin" "$test_dir/bin"
cp "$plugin_dir/tests/reader-smoke.qml" "$test_dir/shell.qml"
python3 "$plugin_dir/tests/make-fixture.py" "$test_dir/input.pdf"
qpdf --empty --pages "$test_dir/input.pdf" 1-2,1-2,1-2,1-2,1-2,1-2 -- "$test_dir/twelve-pages.pdf"
PDFSEAL_TEST_DIR="$test_dir" timeout 45 quickshell -p "$test_dir" --no-color >"$test_dir/output.log" 2>&1
rg -q 'PASS: continuous reader' "$test_dir/output.log"
pdftotext -raw -f 3 -l 3 "$test_dir/reader-export.pdf" - | rg -q 'Page Three Edit'
if pdftotext -raw -f 1 -l 1 "$test_dir/reader-export.pdf" - | rg -q 'Page Three Edit'; then exit 1; fi
if rg 'ERROR|TypeError|ReferenceError|Cannot assign|Cannot open:' "$test_dir/output.log"; then exit 1; fi
