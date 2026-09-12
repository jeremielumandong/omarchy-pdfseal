#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
cargo build --release --locked --manifest-path "$plugin_dir/native/Cargo.toml"
mkdir -p "$plugin_dir/bin"
install -m 755 "$plugin_dir/native/target/release/pdfseal-worker" "$plugin_dir/bin/pdfseal-worker"
python3 "$plugin_dir/scripts/notices.py"
"$plugin_dir/bin/pdfseal-worker" --version
