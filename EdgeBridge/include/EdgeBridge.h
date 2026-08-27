#ifndef EDGE_BRIDGE_H
#define EDGE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EdgeBridgeHandle EdgeBridgeHandle;

enum EdgeBridgeStatus {
    QEB_OK = 0,
    QEB_INVALID_ARGUMENT = 1,
    QEB_ENGINE_ERROR = 2,
    QEB_PANIC = 3,
};

/**
 * Creates a Qdrant Edge shard from UTF-8 JSON and returns an opaque handle.
 * Returns NULL on failure. If non-NULL, out_response_json receives allocated
 * UTF-8 JSON that must be released with qeb_string_free.
 */
EdgeBridgeHandle *qeb_create(
    const char *request_json,
    char **out_response_json
);

int32_t qeb_upsert(
    EdgeBridgeHandle *handle,
    const char *request_json,
    char **out_response_json
);

int32_t qeb_query(
    EdgeBridgeHandle *handle,
    const char *request_json,
    char **out_response_json
);

int32_t qeb_flush(
    EdgeBridgeHandle *handle,
    const char *request_json,
    char **out_response_json
);

/** Last use of handle; it becomes invalid after this call. */
void qeb_destroy(EdgeBridgeHandle *handle);

/** Frees a response returned through out_response_json. */
void qeb_string_free(char *value);

/** Static bridge version string; do not free. */
const char *qeb_version(void);

#ifdef __cplusplus
}
#endif

#endif /* EDGE_BRIDGE_H */
