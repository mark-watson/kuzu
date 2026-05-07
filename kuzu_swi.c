/*
 * kuzu_swi.c — SWI-Prolog foreign-language bridge to Kuzu C API
 * ==============================================================
 * Exposes the Kuzu graph database as Prolog predicates.
 *
 * Predicates:
 *   kuzu_version(-Version)
 *   kuzu_open_db(+Path, -Handle)
 *   kuzu_close_db(+Handle)
 *   kuzu_open_conn(+DbHandle, -ConnHandle)
 *   kuzu_close_conn(+ConnHandle)
 *   kuzu_query(+ConnHandle, +Cypher, -ResultHandle)
 *   kuzu_result_has_next(+ResultHandle)
 *   kuzu_result_next_row(+ResultHandle)
 *   kuzu_get_value(+ResultHandle, +ColIndex, -StringValue)
 *   kuzu_result_to_string(+ResultHandle, -String)
 *   kuzu_destroy_result(+ResultHandle)
 *
 * Build (macOS):
 *   swipl-ld -shared -o kuzu_swi kuzu_swi.c \
 *     -Isrc/include -Lbuild/release/src -lkuzu
 *
 * The resulting kuzu_swi.dylib / kuzu_swi.so is loaded in Prolog with:
 *   :- load_foreign_library('./kuzu_swi').
 */

#include <SWI-Prolog.h>
#include "c_api/kuzu.h"
#include <stdlib.h>
#include <string.h>

/* ---------- internal wrapper for result iteration ---------- */

typedef struct {
    kuzu_query_result result;
    kuzu_flat_tuple   tuple;
    kuzu_value        value;
} pl_query_result;

/* ---------- helpers ---------- */

/* Store a heap pointer as a Prolog int64. */
static int put_handle(term_t t, void *ptr) {
    return PL_unify_int64(t, (int64_t)(intptr_t)ptr);
}

/* Retrieve a heap pointer from a Prolog int64. */
static void *get_handle(term_t t) {
    int64_t v;
    if (!PL_get_int64(t, &v)) return NULL;
    return (void *)(intptr_t)v;
}

/* ---------- kuzu_version(-Version) ---------- */

static foreign_t pl_kuzu_version(term_t t_ver) {
    const char *v = kuzu_get_version();
    return PL_unify_atom_chars(t_ver, v);
}

/* ---------- kuzu_open_db(+Path, -Handle) ---------- */

static foreign_t pl_kuzu_open_db(term_t t_path, term_t t_handle) {
    char *path;
    if (!PL_get_chars(t_path, &path, CVT_ALL | REP_UTF8))
        return FALSE;

    kuzu_database *db = malloc(sizeof(kuzu_database));
    if (!db)
        return PL_resource_error("memory");

    kuzu_system_config cfg = kuzu_default_system_config();
    kuzu_state st = kuzu_database_init(path, cfg, db);
    if (st != KuzuSuccess) {
        free(db);
        return PL_warning("kuzu_open_db: kuzu_database_init failed (state=%d)", st);
    }

    return put_handle(t_handle, db);
}

/* ---------- kuzu_close_db(+Handle) ---------- */

static foreign_t pl_kuzu_close_db(term_t t_handle) {
    kuzu_database *db = get_handle(t_handle);
    if (!db) return FALSE;
    kuzu_database_destroy(db);
    free(db);
    return TRUE;
}

/* ---------- kuzu_open_conn(+DbHandle, -ConnHandle) ---------- */

static foreign_t pl_kuzu_open_conn(term_t t_db, term_t t_conn) {
    kuzu_database *db = get_handle(t_db);
    if (!db) return FALSE;

    kuzu_connection *conn = malloc(sizeof(kuzu_connection));
    if (!conn)
        return PL_resource_error("memory");

    kuzu_state st = kuzu_connection_init(db, conn);
    if (st != KuzuSuccess) {
        free(conn);
        return PL_warning("kuzu_open_conn: kuzu_connection_init failed (state=%d)", st);
    }

    return put_handle(t_conn, conn);
}

/* ---------- kuzu_close_conn(+ConnHandle) ---------- */

static foreign_t pl_kuzu_close_conn(term_t t_conn) {
    kuzu_connection *conn = get_handle(t_conn);
    if (!conn) return FALSE;
    kuzu_connection_destroy(conn);
    free(conn);
    return TRUE;
}

/* ---------- kuzu_query(+ConnHandle, +Cypher, -ResultHandle) ---------- */

static foreign_t pl_kuzu_query(term_t t_conn, term_t t_cypher, term_t t_result) {
    kuzu_connection *conn = get_handle(t_conn);
    if (!conn) return FALSE;

    char *cypher;
    if (!PL_get_chars(t_cypher, &cypher, CVT_ALL | REP_UTF8))
        return FALSE;

    pl_query_result *qr = calloc(1, sizeof(pl_query_result));
    if (!qr)
        return PL_resource_error("memory");

    kuzu_state st = kuzu_connection_query(conn, cypher, &qr->result);
    if (st != KuzuSuccess) {
        free(qr);
        return PL_warning("kuzu_query: kuzu_connection_query failed (state=%d)", st);
    }

    if (!kuzu_query_result_is_success(&qr->result)) {
        char *msg = kuzu_query_result_get_error_message(&qr->result);
        PL_warning("kuzu_query: %s", msg ? msg : "unknown error");
        if (msg) kuzu_destroy_string(msg);
        kuzu_query_result_destroy(&qr->result);
        free(qr);
        return FALSE;
    }

    return put_handle(t_result, qr);
}

/* ---------- kuzu_result_has_next(+ResultHandle) ---------- */

static foreign_t pl_kuzu_result_has_next(term_t t_result) {
    pl_query_result *qr = get_handle(t_result);
    if (!qr) return FALSE;
    return kuzu_query_result_has_next(&qr->result) ? TRUE : FALSE;
}

/* ---------- kuzu_result_next_row(+ResultHandle) ---------- */

static foreign_t pl_kuzu_result_next_row(term_t t_result) {
    pl_query_result *qr = get_handle(t_result);
    if (!qr) return FALSE;

    kuzu_state st = kuzu_query_result_get_next(&qr->result, &qr->tuple);
    if (st != KuzuSuccess)
        return PL_warning("kuzu_result_next_row: get_next failed (state=%d)", st);

    return TRUE;
}

/* ---------- kuzu_get_value(+ResultHandle, +Index, -Value) ---------- */

static foreign_t pl_kuzu_get_value(term_t t_result, term_t t_index, term_t t_value) {
    pl_query_result *qr = get_handle(t_result);
    if (!qr) return FALSE;

    int64_t idx;
    if (!PL_get_int64(t_index, &idx))
        return FALSE;

    kuzu_state st = kuzu_flat_tuple_get_value(&qr->tuple, (uint64_t)idx, &qr->value);
    if (st != KuzuSuccess)
        return PL_warning("kuzu_get_value: get_value(%lld) failed (state=%d)", idx, st);

    char *s = kuzu_value_to_string(&qr->value);
    int ok = PL_unify_atom_chars(t_value, s ? s : "");
    if (s) kuzu_destroy_string(s);

    return ok;
}

/* ---------- kuzu_result_to_string(+ResultHandle, -String) ---------- */

static foreign_t pl_kuzu_result_to_string(term_t t_result, term_t t_str) {
    pl_query_result *qr = get_handle(t_result);
    if (!qr) return FALSE;

    char *s = kuzu_query_result_to_string(&qr->result);
    int ok = PL_unify_atom_chars(t_str, s ? s : "");
    if (s) kuzu_destroy_string(s);

    return ok;
}

/* ---------- kuzu_destroy_result(+ResultHandle) ---------- */

static foreign_t pl_kuzu_destroy_result(term_t t_result) {
    pl_query_result *qr = get_handle(t_result);
    if (!qr) return FALSE;
    kuzu_query_result_destroy(&qr->result);
    free(qr);
    return TRUE;
}

/* ---------- Registration ---------- */

install_t install_kuzu_swi(void) {
    PL_register_foreign("kuzu_version",          1, pl_kuzu_version,          0);
    PL_register_foreign("kuzu_open_db",           2, pl_kuzu_open_db,          0);
    PL_register_foreign("kuzu_close_db",          1, pl_kuzu_close_db,         0);
    PL_register_foreign("kuzu_open_conn",         2, pl_kuzu_open_conn,        0);
    PL_register_foreign("kuzu_close_conn",        1, pl_kuzu_close_conn,       0);
    PL_register_foreign("kuzu_query",             3, pl_kuzu_query,            0);
    PL_register_foreign("kuzu_result_has_next",   1, pl_kuzu_result_has_next,  0);
    PL_register_foreign("kuzu_result_next_row",   1, pl_kuzu_result_next_row,  0);
    PL_register_foreign("kuzu_get_value",         3, pl_kuzu_get_value,        0);
    PL_register_foreign("kuzu_result_to_string",  2, pl_kuzu_result_to_string, 0);
    PL_register_foreign("kuzu_destroy_result",    1, pl_kuzu_destroy_result,   0);
}
