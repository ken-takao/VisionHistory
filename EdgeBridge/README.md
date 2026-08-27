# EdgeBridge

`EdgeBridge` is a minimal C ABI static library around `qdrant-edge` 0.8.0 for
iOS. The engine remains in-process and file-backed; request and response data
crosses the ABI as UTF-8 JSON.

Qdrant Edge is beta. This bridge pins the crate version because its Rust API and
storage format may change.

## JSON API

All returned strings are owned by Rust and must be released with
`qeb_string_free`.

Create a new shard:

```json
{
  "path": "/absolute/app-container/path/edge-shard",
  "vector_size": 4,
  "distance": "cosine",
  "on_disk_payload": false,
  "on_disk_vectors": false,
  "open_existing": false,
  "max_search_threads": 2
}
```

Set `open_existing` to `true` on later app launches. The supplied vector
configuration must remain compatible with persisted data.

Upsert points (numeric IDs or UUID strings):

```json
{
  "points": [
    {
      "id": 1,
      "vector": [0.1, 0.2, 0.3, 0.4],
      "payload": {"text": "hello"}
    }
  ]
}
```

Query:

```json
{
  "vector": [0.1, 0.2, 0.3, 0.4],
  "limit": 10,
  "offset": 0,
  "with_payload": true,
  "with_vector": false
}
```

Flush uses `{}`. Success responses have `{"ok":true,"operation":"..."}`;
failures have `{"ok":false,"operation":"...","error":{"code":"...","message":"..."}}`.

## Build and test

Requirements used for this prototype:

- rustup-managed Rust with `aarch64-apple-ios` and
  `aarch64-apple-ios-sim` targets
- Xcode command-line tools

```sh
bash EdgeBridge/scripts/test.sh
bash EdgeBridge/scripts/build-xcframework.sh
```

The script deliberately resolves both Cargo and rustc through rustup. A
separately installed Homebrew `cargo`/`rustc` pair cannot see targets installed
in rustup's sysroot. Set `RUSTUP_TOOLCHAIN` if the targets belong to a toolchain
other than `stable`. Cargo intermediates are placed in
`/tmp/qdrant-edge-target-kioku-relay` to keep the large dependency tree outside
the Xcode workspace; override this with `EDGE_BRIDGE_TARGET_DIR`.
Native C dependencies use an iOS 15.0 deployment target by default; override
it with `MIN_IOS_VERSION` when the app requires a newer minimum.

The second command creates `EdgeBridge/build/EdgeBridge.xcframework` with
arm64 device and arm64 Apple-silicon Simulator slices.

## Xcode integration

1. Drag `EdgeBridge.xcframework` into the app target and select **Copy items if
   needed**.
2. In **Frameworks, Libraries, and Embedded Content**, choose **Do Not Embed**
   because this XCFramework contains static libraries.
3. Add `Swift/EdgeBridgeClient.swift` to the app target. `import EdgeBridge`
   resolves through the packaged Clang module map.
4. Store the shard under the app's Application Support directory, not in the
   read-only bundle. Exclude recreatable shards from backup if appropriate.
5. Call `flush()` when the app moves out of the active state. Run all bridge
   calls off the main actor and serialize `close()` against in-flight calls.

The bridge catches Rust panics at exported operation boundaries, validates
dimensions and bounded result counts, and never exposes Rust layout to Swift.
Passing an invalid pointer or racing `qeb_destroy` remains undefined behavior,
as with any C API.
