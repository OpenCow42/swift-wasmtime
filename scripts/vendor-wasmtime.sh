#!/usr/bin/env bash
set -euo pipefail

version="${1:-v44.0.1}"
repo="bytecodealliance/wasmtime"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${TMPDIR:-/tmp}/swift-wasmtime-vendor-${version}"
release_json="${work}/release.json"
targets=(
  "aarch64-macos"
  "x86_64-macos"
  "aarch64-linux"
  "x86_64-linux"
  "aarch64-windows"
  "x86_64-windows"
)

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require curl
require python3
require shasum
require tar

mkdir -p "$work"
curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${version}" -o "$release_json"

asset_field() {
  local target="$1"
  local field="$2"
  local extension="$3"
  python3 - "$release_json" "$version" "$target" "$field" "$extension" <<'PY'
import json
import sys

release_path, version, target, field, extension = sys.argv[1:]
name = f"wasmtime-{version}-{target}-c-api.{extension}"
with open(release_path, encoding="utf-8") as handle:
    release = json.load(handle)
for asset in release["assets"]:
    if asset["name"] == name:
        print(asset[field])
        raise SystemExit(0)
raise SystemExit(f"missing release asset: {name}")
PY
}

for target in "${targets[@]}"; do
  if [[ "$target" == *"-windows" ]]; then
    extension="zip"
  else
    extension="tar.xz"
  fi

  archive="wasmtime-${version}-${target}-c-api.${extension}"
  url="$(asset_field "$target" browser_download_url "$extension")"
  expected="$(asset_field "$target" digest "$extension")"
  expected="${expected#sha256:}"
  archive_path="${work}/${archive}"
  extract_path="${work}/${target}"

  curl -fL "$url" -o "$archive_path"
  actual="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for ${archive}" >&2
    echo "expected: ${expected}" >&2
    echo "actual:   ${actual}" >&2
    exit 1
  fi

  rm -rf "$extract_path"
  mkdir -p "$extract_path"
  if [[ "$extension" == "zip" ]]; then
    python3 - "$archive_path" "$extract_path" <<'PY'
import sys
import zipfile
from pathlib import Path

archive_path, extract_path = sys.argv[1:]
root = Path(extract_path)
with zipfile.ZipFile(archive_path) as archive:
    for member in archive.infolist():
        parts = Path(member.filename).parts
        if len(parts) <= 1:
            continue
        destination = root.joinpath(*parts[1:])
        if member.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as source, destination.open("wb") as target:
                target.write(source.read())
PY
  else
    tar -xf "$archive_path" -C "$extract_path" --strip-components 1
  fi

  mkdir -p "$root/Vendor/Wasmtime/${version}/${target}/lib"
  if [[ "$target" == *"-windows" ]]; then
    cp "$extract_path/lib/wasmtime.lib" "$root/Vendor/Wasmtime/${version}/${target}/lib/wasmtime.lib"
    cp "$extract_path/lib/wasmtime.dll.lib" "$root/Vendor/Wasmtime/${version}/${target}/lib/wasmtime.dll.lib"
    cp "$extract_path/lib/wasmtime.dll" "$root/Vendor/Wasmtime/${version}/${target}/lib/wasmtime.dll"
  else
    cp "$extract_path/lib/libwasmtime.a" "$root/Vendor/Wasmtime/${version}/${target}/lib/libwasmtime.a"
  fi

  if [[ "$target" == "aarch64-macos" ]]; then
    rm -rf "$root/Sources/CWasmtime/include"
    mkdir -p "$root/Sources/CWasmtime/include"
    cp -R "$extract_path/include/." "$root/Sources/CWasmtime/include/"
    cat > "$root/Sources/CWasmtime/include/module.modulemap" <<'EOF'
module CWasmtime {
  header "wasmtime.h"
  export *
}
EOF
  fi
done

echo "Vendored Wasmtime ${version} C API artifacts."
