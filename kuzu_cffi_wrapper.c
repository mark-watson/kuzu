/*
 * kuzu_cffi_wrapper.c — Thin C wrappers for Kuzu functions that pass
 * structs by value, so CFFI can call them with plain pointers.
 *
 * Build:
 *   cc -shared -o build/release/src/libkuzu_cffi.dylib kuzu_cffi_wrapper.c \
 *      -Isrc/include -Lbuild/release/src -lkuzu
 */
#include "c_api/kuzu.h"

/* kuzu_database_init takes kuzu_system_config BY VALUE.
   This wrapper takes it BY POINTER so CFFI doesn't need libffi. */
kuzu_state kuzu_database_init_ptr(const char* database_path,
    const kuzu_system_config* config, kuzu_database* out_database) {
    return kuzu_database_init(database_path, *config, out_database);
}

/* kuzu_default_system_config returns a struct BY VALUE.
   This wrapper writes to a caller-provided pointer. */
void kuzu_default_system_config_ptr(kuzu_system_config* out_config) {
    *out_config = kuzu_default_system_config();
}
