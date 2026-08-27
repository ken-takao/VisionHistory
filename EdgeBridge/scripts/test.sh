#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${EDGE_BRIDGE_TARGET_DIR:-/tmp/qdrant-edge-target-kioku-relay}"
RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"

if ! command -v rustup >/dev/null 2>&1; then
    echo "rustup is required to test EdgeBridge." >&2
    exit 1
fi

RUSTUP_CARGO="$(rustup which cargo --toolchain "${RUSTUP_TOOLCHAIN}")"
RUSTUP_RUSTC="$(rustup which rustc --toolchain "${RUSTUP_TOOLCHAIN}")"
RUSTUP_RUSTDOC="$(rustup which rustdoc --toolchain "${RUSTUP_TOOLCHAIN}")"

CARGO_TARGET_DIR="${TARGET_DIR}" \
RUSTC="${RUSTUP_RUSTC}" \
RUSTDOC="${RUSTUP_RUSTDOC}" \
"${RUSTUP_CARGO}" test --manifest-path "${BRIDGE_ROOT}/Cargo.toml"

"${RUSTUP_CARGO}" fmt --manifest-path "${BRIDGE_ROOT}/Cargo.toml" --check
