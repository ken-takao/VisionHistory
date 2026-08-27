#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# qdrant-edge has a large dependency graph. Keep Cargo intermediates outside
# the Xcode workspace so filesystem coordination/indexing is not held up.
TARGET_DIR="${EDGE_BRIDGE_TARGET_DIR:-/tmp/qdrant-edge-target-kioku-relay}"
OUTPUT_DIR="${BRIDGE_ROOT}/build"
XCFRAMEWORK="${OUTPUT_DIR}/EdgeBridge.xcframework"
RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-15.0}"

if ! command -v rustup >/dev/null 2>&1; then
    echo "rustup is required so Cargo can use the installed iOS standard libraries." >&2
    exit 1
fi

for required_target in aarch64-apple-ios aarch64-apple-ios-sim; do
    if ! rustup target list --installed --toolchain "${RUSTUP_TOOLCHAIN}" \
        | awk -v target="${required_target}" '$0 == target { found = 1 } END { exit !found }'; then
        echo "Missing Rust target ${required_target} for toolchain ${RUSTUP_TOOLCHAIN}." >&2
        echo "Install it with: rustup target add --toolchain ${RUSTUP_TOOLCHAIN} ${required_target}" >&2
        exit 1
    fi
done

# `rustup run` sets the toolchain override, but it does not replace an earlier
# Homebrew rustc/cargo in PATH on every installation. Resolve both binaries so
# Cargo and the iOS standard libraries always come from the same sysroot.
RUSTUP_CARGO="$(rustup which cargo --toolchain "${RUSTUP_TOOLCHAIN}")"
RUSTUP_RUSTC="$(rustup which rustc --toolchain "${RUSTUP_TOOLCHAIN}")"

mkdir -p "${OUTPUT_DIR}"

CARGO_TARGET_DIR="${TARGET_DIR}" \
IPHONEOS_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
RUSTC="${RUSTUP_RUSTC}" "${RUSTUP_CARGO}" build \
    --manifest-path "${BRIDGE_ROOT}/Cargo.toml" \
    --release \
    --target aarch64-apple-ios

CARGO_TARGET_DIR="${TARGET_DIR}" \
IPHONEOS_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
RUSTC="${RUSTUP_RUSTC}" "${RUSTUP_CARGO}" build \
    --manifest-path "${BRIDGE_ROOT}/Cargo.toml" \
    --release \
    --target aarch64-apple-ios-sim

if [[ -e "${XCFRAMEWORK}" ]]; then
    case "${XCFRAMEWORK}" in
        "${BRIDGE_ROOT}"/build/EdgeBridge.xcframework)
            rm -rf "${XCFRAMEWORK}"
            ;;
        *)
            echo "Refusing to remove unexpected path: ${XCFRAMEWORK}" >&2
            exit 1
            ;;
    esac
fi

xcodebuild -create-xcframework \
    -library "${TARGET_DIR}/aarch64-apple-ios/release/libedge_bridge.a" \
    -headers "${BRIDGE_ROOT}/include" \
    -library "${TARGET_DIR}/aarch64-apple-ios-sim/release/libedge_bridge.a" \
    -headers "${BRIDGE_ROOT}/include" \
    -output "${XCFRAMEWORK}"

echo "Built ${XCFRAMEWORK}"
