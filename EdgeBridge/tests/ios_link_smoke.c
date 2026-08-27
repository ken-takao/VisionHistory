#include "EdgeBridge.h"

#include <stddef.h>

int main(void) {
    const char *version = qeb_version();
    return version == NULL ? 1 : 0;
}
