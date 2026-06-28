#!/usr/bin/env bash
set -euo pipefail

version="${1:-v45.0.2}"
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

if [[ "$(uname -s)" == "Darwin" ]]; then
  require cargo
  require cmake
  require ninja
  require rustup
  require xcodebuild
  require xcrun
fi

mkdir -p "$work"
curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${version}" -o "$release_json"
mkdir -p "$root/Vendor/Wasmtime/${version}"
rm -rf \
  "$root/Vendor/Wasmtime/${version}/aarch64-macos" \
  "$root/Vendor/Wasmtime/${version}/x86_64-macos"
curl -fsSL "https://raw.githubusercontent.com/${repo}/${version}/LICENSE" \
  -o "$root/Vendor/Wasmtime/${version}/LICENSE"

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

release_asset_field() {
  local name="$1"
  local field="$2"
  python3 - "$release_json" "$name" "$field" <<'PY'
import json
import sys

release_path, name, field = sys.argv[1:]
with open(release_path, encoding="utf-8") as handle:
    release = json.load(handle)
for asset in release["assets"]:
    if asset["name"] == name:
        print(asset[field])
        raise SystemExit(0)
raise SystemExit(f"missing release asset: {name}")
PY
}

download_verified_asset() {
  local name="$1"
  local path="$2"
  local url expected actual

  url="$(release_asset_field "$name" browser_download_url)"
  expected="$(release_asset_field "$name" digest)"
  expected="${expected#sha256:}"

  curl -fL "$url" -o "$path"
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for ${name}" >&2
    echo "expected: ${expected}" >&2
    echo "actual:   ${actual}" >&2
    exit 1
  fi
}

patch_apple_mobile_source() {
  local source_path="$1"

  python3 - "$source_path" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
replacements = {
    "crates/wasmtime/Cargo.toml": [
        (
            "[target.'cfg(target_vendor = \"apple\")'.dependencies]\n"
            "mach2 = { workspace = true, optional = true }\n",
            "[target.'cfg(any(target_os = \"macos\", target_os = \"ios\"))'.dependencies]\n"
            "mach2 = { workspace = true, optional = true }\n",
        ),
    ],
    "crates/wasmtime/src/runtime/vm/sys/unix/mod.rs": [
        (
            "#[cfg(all(has_native_signals, target_vendor = \"apple\"))]\n"
            "pub mod machports;\n",
            "#[cfg(all(has_native_signals, any(target_os = \"macos\", target_os = \"ios\")))]\n"
            "pub mod machports;\n",
        ),
    ],
    "crates/wasmtime/src/runtime/vm/sys/unix/traphandlers.rs": [
        (
            "    } else if #[cfg(target_vendor = \"apple\")] {\n",
            "    } else if #[cfg(any(target_os = \"macos\", target_os = \"ios\"))] {\n",
        ),
    ],
    "crates/wasmtime/src/runtime/vm/sys/unix/signals.rs": [
        (
            "assert!(!macos_use_mach_ports || !cfg!(target_vendor = \"apple\"));",
            "assert!(!macos_use_mach_ports || !cfg!(any(target_os = \"macos\", target_os = \"ios\")));",
        ),
    ],
    "vendor/iana-time-zone/Cargo.toml": [
        (
            "[target.'cfg(any(target_os = \"macos\", target_os = \"ios\"))'.dependencies.core-foundation-sys]\n",
            "[target.'cfg(any(target_os = \"macos\", target_os = \"ios\", target_os = \"tvos\"))'.dependencies.core-foundation-sys]\n",
        ),
    ],
    "vendor/iana-time-zone/Cargo.toml.orig": [
        (
            "[target.'cfg(any(target_os = \"macos\", target_os = \"ios\"))'.dependencies]\n",
            "[target.'cfg(any(target_os = \"macos\", target_os = \"ios\", target_os = \"tvos\"))'.dependencies]\n",
        ),
    ],
    "vendor/iana-time-zone/src/lib.rs": [
        (
            "#[cfg_attr(any(target_os = \"macos\", target_os = \"ios\"), path = \"tz_macos.rs\")]\n",
            "#[cfg_attr(any(target_os = \"macos\", target_os = \"ios\", target_os = \"tvos\"), path = \"tz_macos.rs\")]\n",
        ),
    ],
    "vendor/iana-time-zone/src/platform.rs": [
        (
            "    OpenBSD, Dragonfly, WebAssembly (browser), iOS, Illumos, Android, AIX, Solaris and Haiku.\",\n",
            "    OpenBSD, Dragonfly, WebAssembly (browser), iOS, tvOS, Illumos, Android, AIX, Solaris and Haiku.\",\n",
        ),
    ],
}

for relative_path, edits in replacements.items():
    path = root / relative_path
    text = path.read_text(encoding="utf-8")
    for old, new in edits:
        if old not in text:
            raise SystemExit(f"expected source text not found in {relative_path}")
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")

checksum_path = root / "vendor/iana-time-zone/.cargo-checksum.json"
if checksum_path.exists():
    checksum = json.loads(checksum_path.read_text(encoding="utf-8"))
    for relative_path in (
        "Cargo.toml",
        "Cargo.toml.orig",
        "src/lib.rs",
        "src/platform.rs",
    ):
        path = root / "vendor/iana-time-zone" / relative_path
        checksum["files"][relative_path] = hashlib.sha256(path.read_bytes()).hexdigest()
    checksum_path.write_text(
        json.dumps(checksum, separators=(",", ":")),
        encoding="utf-8",
    )
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

  if [[ "$target" == *"-macos" ]]; then
    continue
  fi

  mkdir -p "$root/Vendor/Wasmtime/${version}/${target}/lib"
  if [[ "$target" == *"-windows" ]]; then
    cp "$extract_path/lib/wasmtime.lib" "$root/Vendor/Wasmtime/${version}/${target}/lib/wasmtime.lib"
    cp "$extract_path/lib/wasmtime.dll.lib" "$root/Vendor/Wasmtime/${version}/${target}/lib/wasmtime.dll.lib"
    cp "$extract_path/lib/wasmtime.dll" "$root/Vendor/Wasmtime/${version}/${target}/lib/wasmtime.dll"
  else
    cp "$extract_path/lib/libwasmtime.a" "$root/Vendor/Wasmtime/${version}/${target}/lib/libwasmtime.a"
  fi
done

if [[ "$(uname -s)" == "Darwin" ]]; then
  source_archive="wasmtime-${version}-src.tar.gz"
  source_archive_path="${work}/${source_archive}"
  source_path="${work}/source"
  apple_install_root="${work}/apple-install"
  apple_universal_root="${work}/apple-universal"
  apple_xcframework="$root/Vendor/Wasmtime/${version}/Wasmtime.xcframework"

  download_verified_asset "$source_archive" "$source_archive_path"
  rm -rf "$source_path" "$apple_install_root" "$apple_universal_root" "$apple_xcframework"
  mkdir -p "$source_path" "$apple_install_root" "$apple_universal_root"
  tar -xzf "$source_archive_path" -C "$source_path" --strip-components 1

  patch_apple_mobile_source "$source_path"

  rustup target add \
    aarch64-apple-ios \
    aarch64-apple-ios-sim \
    x86_64-apple-ios \
    aarch64-apple-tvos \
    aarch64-apple-tvos-sim

  ios_deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"
  tvos_deployment_target="${TVOS_DEPLOYMENT_TARGET:-13.0}"
  export CARGO_PROFILE_RELEASE_STRIP="${CARGO_PROFILE_RELEASE_STRIP:-debuginfo}"
  export CARGO_PROFILE_RELEASE_PANIC="${CARGO_PROFILE_RELEASE_PANIC:-abort}"
  export CARGO_PROFILE_RELEASE_LTO="${CARGO_PROFILE_RELEASE_LTO:-true}"
  export RUSTFLAGS="${RUSTFLAGS:-} -C force-unwind-tables"

  ios_targets=(
    "aarch64-apple-ios"
    "aarch64-apple-ios-sim"
    "x86_64-apple-ios"
  )
  tvos_targets=(
    "aarch64-apple-tvos"
    "aarch64-apple-tvos-sim"
  )

  for target in "${ios_targets[@]}" "${tvos_targets[@]}"; do
    build_path="${work}/apple-build/${target}"
    install_path="${apple_install_root}/${target}"
    (
      if [[ "$target" == *"-tvos"* ]]; then
        unset IPHONEOS_DEPLOYMENT_TARGET
        export TVOS_DEPLOYMENT_TARGET="$tvos_deployment_target"
      else
        unset TVOS_DEPLOYMENT_TARGET
        export IPHONEOS_DEPLOYMENT_TARGET="$ios_deployment_target"
      fi

      cmake \
        -G Ninja \
        "$source_path/crates/c-api" \
        -B "$build_path" \
        -DCMAKE_BUILD_TYPE=Release \
        -DWASMTIME_TARGET="$target" \
        -DCMAKE_INSTALL_PREFIX="$install_path" \
        -DCMAKE_INSTALL_LIBDIR=lib
      cmake --build "$build_path" --target install
    )
  done

  mkdir -p \
    "$apple_universal_root/macos/lib" \
    "$apple_universal_root/ios-simulator/lib" \
    "$root/Vendor/Wasmtime/${version}"
  xcrun lipo -create \
    "$work/aarch64-macos/lib/libwasmtime.a" \
    "$work/x86_64-macos/lib/libwasmtime.a" \
    -output "$apple_universal_root/macos/lib/libwasmtime.a"
  xcrun lipo -create \
    "$apple_install_root/aarch64-apple-ios-sim/lib/libwasmtime.a" \
    "$apple_install_root/x86_64-apple-ios/lib/libwasmtime.a" \
    -output "$apple_universal_root/ios-simulator/lib/libwasmtime.a"

  xcodebuild -create-xcframework \
    -library "$apple_universal_root/macos/lib/libwasmtime.a" \
    -headers "$root/Sources/CWasmtime/include" \
    -library "$apple_install_root/aarch64-apple-ios/lib/libwasmtime.a" \
    -headers "$apple_install_root/aarch64-apple-ios/include" \
    -library "$apple_universal_root/ios-simulator/lib/libwasmtime.a" \
    -headers "$apple_install_root/aarch64-apple-ios-sim/include" \
    -library "$apple_install_root/aarch64-apple-tvos/lib/libwasmtime.a" \
    -headers "$apple_install_root/aarch64-apple-tvos/include" \
    -library "$apple_install_root/aarch64-apple-tvos-sim/lib/libwasmtime.a" \
    -headers "$apple_install_root/aarch64-apple-tvos-sim/include" \
    -output "$apple_xcframework"
else
  echo "Skipping Apple XCFramework vendoring; building those slices requires macOS and Xcode." >&2
fi

echo "Vendored Wasmtime ${version} C API artifacts."
