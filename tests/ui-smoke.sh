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
if [[ -d "$plugin_dir/assets" ]]; then cp -a "$plugin_dir/assets" "$test_dir/"; fi
ln -s "$plugin_dir/bin" "$test_dir/bin"
cp "$plugin_dir/tests/ui-smoke.qml" "$test_dir/shell.qml"
python3 "$plugin_dir/tests/make-fixture.py" "$test_dir/input.pdf"
python3 "$plugin_dir/tests/make-form-fixture.py" "$test_dir/forms.pdf"
qpdf --encrypt test-password test-password 256 -- "$test_dir/input.pdf" "$test_dir/encrypted.pdf"
PDFSEAL_TEST_DIR="$test_dir" timeout 35 quickshell -p "$test_dir" --no-color >"$test_dir/output.log" 2>&1
rg -q 'PASS: PDFSeal widget' "$test_dir/output.log"
pdftotext "$test_dir/signed.pdf" - | rg -q 'Updated text'
pdffonts "$test_dir/signed.pdf" | rg -q 'Times-Roman'
pdftotext -raw "$test_dir/tools.pdf" - | rg -q 'Replacement line'
if [[ -n ${PDFSEAL_CAPTURE:-} ]]; then
    pdftoppm -f 1 -l 1 -singlefile -scale-to 1200 -png "$test_dir/signed.pdf" "$PDFSEAL_CAPTURE.export"
fi
if rg 'ERROR|TypeError|ReferenceError|Cannot assign|Cannot open:' "$test_dir/output.log"; then
    exit 1
fi
