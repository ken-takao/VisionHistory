//! Minimal C ABI for embedding Qdrant Edge in an iOS application.
//!
//! Complex values cross the ABI as UTF-8 JSON. The shard itself remains an
//! opaque pointer owned by the caller. Every returned C string must be released
//! with [`qeb_string_free`].

use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::ptr;
use std::str::FromStr;

use qdrant_edge::{
    DEFAULT_VECTOR_NAME, Distance, EdgeConfig, EdgeShard, EdgeVectorParams, NamedQuery, PointId,
    PointInsertOperations, PointOperations, PointStruct, PointStructPersisted, QueryEnum,
    QueryRequestBuilder, ScoredPoint, ScoringQuery, UpdateOperation, VectorInternal,
    VectorStructInternal, WithPayloadInterface, WithVector,
};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Map, Value, json};

pub const QEB_OK: i32 = 0;
pub const QEB_INVALID_ARGUMENT: i32 = 1;
pub const QEB_ENGINE_ERROR: i32 = 2;
pub const QEB_PANIC: i32 = 3;

/// Opaque to C/Swift. Do not dereference this outside Rust.
pub struct EdgeBridgeHandle {
    shard: EdgeShard,
    path: String,
    vector_size: usize,
}

#[derive(Debug)]
struct BridgeError {
    status: i32,
    code: &'static str,
    message: String,
}

impl BridgeError {
    fn invalid_json(message: impl Into<String>) -> Self {
        Self {
            status: QEB_INVALID_ARGUMENT,
            code: "invalid_json",
            message: message.into(),
        }
    }

    fn invalid_argument(message: impl Into<String>) -> Self {
        Self {
            status: QEB_INVALID_ARGUMENT,
            code: "invalid_argument",
            message: message.into(),
        }
    }

    fn engine(message: impl Into<String>) -> Self {
        Self {
            status: QEB_ENGINE_ERROR,
            code: "engine_error",
            message: message.into(),
        }
    }

    fn panic() -> Self {
        Self {
            status: QEB_PANIC,
            code: "panic",
            message: "Rust panicked while processing the request".to_owned(),
        }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CreateRequest {
    path: String,
    #[serde(alias = "vectorSize")]
    vector_size: usize,
    #[serde(default = "default_distance")]
    distance: String,
    #[serde(default, alias = "onDiskPayload")]
    on_disk_payload: bool,
    #[serde(default, alias = "onDiskVectors")]
    on_disk_vectors: bool,
    /// When true, load compatible persisted data instead of failing if the
    /// shard already exists. This makes app relaunches possible without a
    /// second lifecycle function.
    #[serde(default, alias = "openExisting")]
    open_existing: bool,
    #[serde(default, alias = "maxSearchThreads")]
    max_search_threads: Option<usize>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct UpsertRequest {
    points: Vec<InputPoint>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct InputPoint {
    id: InputPointId,
    vector: Vec<f32>,
    #[serde(default = "empty_object")]
    payload: Value,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum InputPointId {
    Number(u64),
    String(String),
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct QueryRequest {
    vector: Vec<f32>,
    #[serde(default = "default_limit")]
    limit: usize,
    #[serde(default)]
    offset: usize,
    #[serde(default, alias = "scoreThreshold")]
    score_threshold: Option<f32>,
    #[serde(default = "default_true", alias = "withPayload")]
    with_payload: bool,
    #[serde(default, alias = "withVector")]
    with_vector: bool,
}

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct FlushRequest {}

fn default_distance() -> String {
    "cosine".to_owned()
}

fn default_limit() -> usize {
    10
}

fn default_true() -> bool {
    true
}

fn empty_object() -> Value {
    Value::Object(Map::new())
}

fn parse_distance(value: &str) -> Result<Distance, BridgeError> {
    match value.to_ascii_lowercase().as_str() {
        "cosine" => Ok(Distance::Cosine),
        "dot" => Ok(Distance::Dot),
        "euclid" | "euclidean" => Ok(Distance::Euclid),
        "manhattan" => Ok(Distance::Manhattan),
        _ => Err(BridgeError::invalid_argument(format!(
            "unsupported distance {value:?}; expected cosine, dot, euclid, or manhattan"
        ))),
    }
}

fn distance_name(distance: Distance) -> &'static str {
    match distance {
        Distance::Cosine => "cosine",
        Distance::Dot => "dot",
        Distance::Euclid => "euclid",
        Distance::Manhattan => "manhattan",
    }
}

fn validate_vector(vector: &[f32], expected_size: usize) -> Result<(), BridgeError> {
    if vector.len() != expected_size {
        return Err(BridgeError::invalid_argument(format!(
            "vector has {} dimensions; expected {expected_size}",
            vector.len()
        )));
    }
    if !vector.iter().all(|value| value.is_finite()) {
        return Err(BridgeError::invalid_argument(
            "vector values must all be finite",
        ));
    }
    Ok(())
}

fn input_point_id(id: InputPointId) -> Result<PointId, BridgeError> {
    match id {
        InputPointId::Number(value) => Ok(PointId::NumId(value)),
        InputPointId::String(value) => PointId::from_str(&value).map_err(|()| {
            BridgeError::invalid_argument(format!(
                "point id {value:?} is not an unsigned integer or UUID"
            ))
        }),
    }
}

unsafe fn parse_request<T: DeserializeOwned>(
    request_json: *const c_char,
) -> Result<T, BridgeError> {
    if request_json.is_null() {
        return Err(BridgeError::invalid_argument("request_json is null"));
    }

    // SAFETY: The C contract requires a valid, NUL-terminated string for the
    // duration of this call.
    let request = unsafe { CStr::from_ptr(request_json) };
    let request = request
        .to_str()
        .map_err(|error| BridgeError::invalid_json(format!("request is not UTF-8: {error}")))?;
    serde_json::from_str(request)
        .map_err(|error| BridgeError::invalid_json(format!("invalid request JSON: {error}")))
}

fn clear_output(out_response_json: *mut *mut c_char) {
    if !out_response_json.is_null() {
        // SAFETY: The caller supplied writable storage for one pointer.
        unsafe { *out_response_json = ptr::null_mut() };
    }
}

fn write_response(out_response_json: *mut *mut c_char, response: Value) {
    if out_response_json.is_null() {
        return;
    }

    let serialized = serde_json::to_string(&response).unwrap_or_else(|_| {
        "{\"ok\":false,\"operation\":\"bridge\",\"error\":{\"code\":\"serialization_error\",\"message\":\"failed to serialize response\"}}".to_owned()
    });
    let c_string = CString::new(serialized).expect("serialized JSON contains no NUL byte");
    // SAFETY: The caller owns this allocation until qeb_string_free.
    unsafe { *out_response_json = c_string.into_raw() };
}

fn success(operation: &str, fields: impl IntoIterator<Item = (&'static str, Value)>) -> Value {
    let mut object = Map::new();
    object.insert("ok".to_owned(), Value::Bool(true));
    object.insert("operation".to_owned(), Value::String(operation.to_owned()));
    for (key, value) in fields {
        object.insert(key.to_owned(), value);
    }
    Value::Object(object)
}

fn failure(operation: &str, error: &BridgeError) -> Value {
    json!({
        "ok": false,
        "operation": operation,
        "error": {
            "code": error.code,
            "message": error.message,
        }
    })
}

fn create_impl(request: CreateRequest) -> Result<(EdgeBridgeHandle, Value), BridgeError> {
    if request.path.trim().is_empty() {
        return Err(BridgeError::invalid_argument("path must not be empty"));
    }
    if !(1..=65_536).contains(&request.vector_size) {
        return Err(BridgeError::invalid_argument(
            "vector_size must be between 1 and 65536",
        ));
    }
    if request.max_search_threads == Some(0) {
        return Err(BridgeError::invalid_argument(
            "max_search_threads must be greater than zero when provided",
        ));
    }

    let distance = parse_distance(&request.distance)?;
    let vector_params = EdgeVectorParams::builder(request.vector_size, distance)
        .on_disk(request.on_disk_vectors)
        .build();
    let mut config = EdgeConfig::builder()
        .on_disk_payload(request.on_disk_payload)
        .vector(DEFAULT_VECTOR_NAME, vector_params);
    if let Some(max_search_threads) = request.max_search_threads {
        config = config.max_search_threads(max_search_threads);
    }
    let config = config.build();
    let path = Path::new(&request.path);
    let existed = path.join("edge_config.json").is_file();
    let shard = if request.open_existing {
        EdgeShard::load(path, Some(config))
    } else {
        EdgeShard::new(path, config)
    }
    .map_err(|error| BridgeError::engine(error.to_string()))?;

    let response = success(
        "create",
        [
            ("path", Value::String(request.path.clone())),
            ("vectorSize", json!(request.vector_size)),
            (
                "distance",
                Value::String(distance_name(distance).to_owned()),
            ),
            (
                "openedExisting",
                Value::Bool(existed && request.open_existing),
            ),
        ],
    );

    Ok((
        EdgeBridgeHandle {
            shard,
            path: request.path,
            vector_size: request.vector_size,
        },
        response,
    ))
}

fn upsert_impl(handle: &EdgeBridgeHandle, request: UpsertRequest) -> Result<Value, BridgeError> {
    if request.points.is_empty() {
        return Err(BridgeError::invalid_argument(
            "points must contain at least one point",
        ));
    }
    if request.points.len() > 10_000 {
        return Err(BridgeError::invalid_argument(
            "a single upsert is limited to 10000 points",
        ));
    }

    let upserted = request.points.len();
    let points: Vec<PointStructPersisted> = request
        .points
        .into_iter()
        .map(|point| {
            validate_vector(&point.vector, handle.vector_size)?;
            if !point.payload.is_object() {
                return Err(BridgeError::invalid_argument(
                    "point payload must be a JSON object",
                ));
            }
            let id = input_point_id(point.id)?;
            Ok(PointStruct::new(id, point.vector, point.payload).into())
        })
        .collect::<Result<_, BridgeError>>()?;

    handle
        .shard
        .update(UpdateOperation::PointOperation(
            PointOperations::UpsertPoints(PointInsertOperations::PointsList(points)),
        ))
        .map_err(|error| BridgeError::engine(error.to_string()))?;

    Ok(success("upsert", [("upserted", json!(upserted))]))
}

fn query_impl(handle: &EdgeBridgeHandle, request: QueryRequest) -> Result<Value, BridgeError> {
    validate_vector(&request.vector, handle.vector_size)?;
    if !(1..=1_000).contains(&request.limit) {
        return Err(BridgeError::invalid_argument(
            "limit must be between 1 and 1000",
        ));
    }
    if request.offset > 1_000_000 {
        return Err(BridgeError::invalid_argument(
            "offset must not exceed 1000000",
        ));
    }
    if request
        .score_threshold
        .is_some_and(|threshold| !threshold.is_finite())
    {
        return Err(BridgeError::invalid_argument(
            "score_threshold must be finite",
        ));
    }

    let mut builder = QueryRequestBuilder::new(request.limit)
        .query(ScoringQuery::Vector(QueryEnum::Nearest(NamedQuery {
            query: request.vector.into(),
            using: None,
        })))
        .offset(request.offset)
        .with_payload(WithPayloadInterface::Bool(request.with_payload))
        .with_vector(WithVector::Bool(request.with_vector));
    if let Some(score_threshold) = request.score_threshold {
        builder = builder.score_threshold(score_threshold);
    }

    let hits = handle
        .shard
        .query(builder.build())
        .map_err(|error| BridgeError::engine(error.to_string()))?
        .into_iter()
        .map(scored_point_json)
        .collect::<Vec<_>>();

    Ok(success("query", [("hits", Value::Array(hits))]))
}

fn scored_point_json(point: ScoredPoint) -> Value {
    let payload = point
        .payload
        .map(|payload| Value::Object(payload.0))
        .unwrap_or(Value::Null);
    let vector = point.vector.map(vector_json).unwrap_or(Value::Null);
    json!({
        "id": point.id,
        "score": point.score,
        "payload": payload,
        "vector": vector,
    })
}

fn vector_json(vector: VectorStructInternal) -> Value {
    match vector {
        VectorStructInternal::Single(values) => json!(values),
        VectorStructInternal::MultiDense(values) => {
            serde_json::to_value(VectorInternal::MultiDense(values)).unwrap_or(Value::Null)
        }
        VectorStructInternal::Named(vectors) => Value::Object(
            vectors
                .into_iter()
                .map(|(name, vector)| {
                    let value = serde_json::to_value(vector).unwrap_or(Value::Null);
                    (name, value)
                })
                .collect(),
        ),
    }
}

fn flush_impl(handle: &EdgeBridgeHandle, _request: FlushRequest) -> Result<Value, BridgeError> {
    handle
        .shard
        .flush()
        .map_err(|error| BridgeError::engine(error.to_string()))?;
    Ok(success(
        "flush",
        [("path", Value::String(handle.path.clone()))],
    ))
}

fn boundary_result<T>(work: impl FnOnce() -> Result<T, BridgeError>) -> Result<T, BridgeError> {
    catch_unwind(AssertUnwindSafe(work)).map_err(|_| BridgeError::panic())?
}

unsafe fn handle_ref<'a>(
    handle: *mut EdgeBridgeHandle,
) -> Result<&'a EdgeBridgeHandle, BridgeError> {
    // SAFETY: The caller must pass a live handle returned by qeb_create and
    // must not race this call with qeb_destroy.
    unsafe { handle.as_ref() }.ok_or_else(|| BridgeError::invalid_argument("handle is null"))
}

/// Creates a shard and returns an opaque handle. On failure returns NULL.
/// `out_response_json` receives a success or error object when non-NULL.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qeb_create(
    request_json: *const c_char,
    out_response_json: *mut *mut c_char,
) -> *mut EdgeBridgeHandle {
    clear_output(out_response_json);
    let result = boundary_result(|| {
        // SAFETY: Forwarding the C string contract of this exported function.
        let request = unsafe { parse_request::<CreateRequest>(request_json) }?;
        create_impl(request)
    });

    match result {
        Ok((handle, response)) => {
            write_response(out_response_json, response);
            Box::into_raw(Box::new(handle))
        }
        Err(error) => {
            write_response(out_response_json, failure("create", &error));
            ptr::null_mut()
        }
    }
}

/// Inserts or replaces points described by JSON.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qeb_upsert(
    handle: *mut EdgeBridgeHandle,
    request_json: *const c_char,
    out_response_json: *mut *mut c_char,
) -> i32 {
    clear_output(out_response_json);
    let result = boundary_result(|| {
        // SAFETY: Forwarding the pointer contracts of this exported function.
        let handle = unsafe { handle_ref(handle) }?;
        let request = unsafe { parse_request::<UpsertRequest>(request_json) }?;
        upsert_impl(handle, request)
    });
    finish_status("upsert", result, out_response_json)
}

/// Runs a nearest-neighbor query described by JSON.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qeb_query(
    handle: *mut EdgeBridgeHandle,
    request_json: *const c_char,
    out_response_json: *mut *mut c_char,
) -> i32 {
    clear_output(out_response_json);
    let result = boundary_result(|| {
        // SAFETY: Forwarding the pointer contracts of this exported function.
        let handle = unsafe { handle_ref(handle) }?;
        let request = unsafe { parse_request::<QueryRequest>(request_json) }?;
        query_impl(handle, request)
    });
    finish_status("query", result, out_response_json)
}

/// Forces WAL and segment data to stable storage. Pass `{}` as request JSON.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qeb_flush(
    handle: *mut EdgeBridgeHandle,
    request_json: *const c_char,
    out_response_json: *mut *mut c_char,
) -> i32 {
    clear_output(out_response_json);
    let result = boundary_result(|| {
        // SAFETY: Forwarding the pointer contracts of this exported function.
        let handle = unsafe { handle_ref(handle) }?;
        let request = unsafe { parse_request::<FlushRequest>(request_json) }?;
        flush_impl(handle, request)
    });
    finish_status("flush", result, out_response_json)
}

fn finish_status(
    operation: &str,
    result: Result<Value, BridgeError>,
    out_response_json: *mut *mut c_char,
) -> i32 {
    match result {
        Ok(response) => {
            write_response(out_response_json, response);
            QEB_OK
        }
        Err(error) => {
            let status = error.status;
            write_response(out_response_json, failure(operation, &error));
            status
        }
    }
}

/// Flushes through `EdgeShard::drop` and releases an opaque handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qeb_destroy(handle: *mut EdgeBridgeHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: The pointer was allocated by Box::into_raw in qeb_create and
        // ownership is transferred exactly once to this function.
        drop(unsafe { Box::from_raw(handle) });
    }));
}

/// Releases a response string returned through `out_response_json`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qeb_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    // SAFETY: The pointer was returned by CString::into_raw in write_response
    // and ownership is transferred exactly once to this function.
    drop(unsafe { CString::from_raw(value) });
}

/// Returns a static UTF-8/NUL-terminated bridge version string. Do not free it.
#[unsafe(no_mangle)]
pub extern "C" fn qeb_version() -> *const c_char {
    c"0.1.0".as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe fn take_response(response: *mut c_char) -> Value {
        assert!(!response.is_null());
        // SAFETY: Test only passes live strings returned by this module.
        let text = unsafe { CStr::from_ptr(response) }
            .to_str()
            .unwrap()
            .to_owned();
        // SAFETY: Transfer the allocation back exactly once.
        unsafe { qeb_string_free(response) };
        serde_json::from_str(&text).unwrap()
    }

    #[test]
    fn ffi_round_trip_create_upsert_query_flush() {
        let directory = tempfile::tempdir().unwrap();
        let create = CString::new(
            json!({
                "path": directory.path(),
                "vector_size": 4,
                "distance": "dot"
            })
            .to_string(),
        )
        .unwrap();
        let mut response = ptr::null_mut();
        // SAFETY: All pointers remain valid for each call.
        let handle = unsafe { qeb_create(create.as_ptr(), &mut response) };
        assert!(!handle.is_null(), "{}", unsafe { take_response(response) });
        let created = unsafe { take_response(response) };
        assert_eq!(created["ok"], true);

        let upsert = CString::new(
            json!({
                "points": [
                    {"id": 1, "vector": [1.0, 0.0, 0.0, 0.0], "payload": {"label": "one"}},
                    {"id": 2, "vector": [0.0, 1.0, 0.0, 0.0], "payload": {"label": "two"}}
                ]
            })
            .to_string(),
        )
        .unwrap();
        response = ptr::null_mut();
        let status = unsafe { qeb_upsert(handle, upsert.as_ptr(), &mut response) };
        assert_eq!(status, QEB_OK, "{}", unsafe { take_response(response) });
        let upserted = unsafe { take_response(response) };
        assert_eq!(upserted["upserted"], 2);

        let query = CString::new(
            json!({
                "vector": [1.0, 0.0, 0.0, 0.0],
                "limit": 2,
                "with_payload": true
            })
            .to_string(),
        )
        .unwrap();
        response = ptr::null_mut();
        let status = unsafe { qeb_query(handle, query.as_ptr(), &mut response) };
        assert_eq!(status, QEB_OK, "{}", unsafe { take_response(response) });
        let queried = unsafe { take_response(response) };
        assert_eq!(queried["hits"][0]["id"], 1);
        assert_eq!(queried["hits"][0]["payload"]["label"], "one");

        let flush = CString::new("{}").unwrap();
        response = ptr::null_mut();
        let status = unsafe { qeb_flush(handle, flush.as_ptr(), &mut response) };
        assert_eq!(status, QEB_OK, "{}", unsafe { take_response(response) });
        let flushed = unsafe { take_response(response) };
        assert_eq!(flushed["ok"], true);

        // SAFETY: Last use of the live handle.
        unsafe { qeb_destroy(handle) };
    }
}
