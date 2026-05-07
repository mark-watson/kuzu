/**
 * Kuzu Graph Database — TypeScript Demo Example
 * ================================================
 * This script demonstrates using Kuzu's C API from TypeScript
 * via koffi (a pure-JS FFI library).  It mirrors the queries in
 * example.py and example.lisp: creates a database, defines a
 * schema, loads CSV data, and runs several Cypher queries.
 *
 * Prerequisites:
 *   1. Build the shared library + CFFI wrapper:
 *        make release
 *        make cffi-wrapper
 *   2. Install Node dependencies:
 *        npm install
 *
 * Run:
 *     npx tsx example.ts
 */

import koffi from "koffi";
import * as fs from "fs";
import * as path from "path";

// ── Locate the shared libraries ────────────────────────────────────
const baseDir = __dirname;
const sharedExt = process.platform === "darwin" ? "dylib" : "so";
const libkuzuPath = path.join(
  baseDir, "build", "release", "src", `libkuzu.${sharedExt}`
);
const libkuzuCffiPath = path.join(
  baseDir, "build", "release", "src", `libkuzu_cffi.${sharedExt}`
);

// ── Struct definitions (mirrors c_api/kuzu.h) ──────────────────────
const KuzuDatabase = koffi.struct("kuzu_database", {
  _database: "void *",
});

const KuzuConnection = koffi.struct("kuzu_connection", {
  _connection: "void *",
});

const KuzuQueryResult = koffi.struct("kuzu_query_result", {
  _query_result: "void *",
  _is_owned_by_cpp: "bool",
});

const KuzuFlatTuple = koffi.struct("kuzu_flat_tuple", {
  _flat_tuple: "void *",
  _is_owned_by_cpp: "bool",
});

const KuzuValue = koffi.struct("kuzu_value", {
  _value: "void *",
  _is_owned_by_cpp: "bool",
});

const KuzuSystemConfig = koffi.struct("kuzu_system_config", {
  buffer_pool_size: "uint64_t",
  max_num_threads: "uint64_t",
  enable_compression: "bool",
  read_only: "bool",
  max_db_size: "uint64_t",
  auto_checkpoint: "bool",
  checkpoint_threshold: "uint64_t",
  ...(process.platform === "darwin" ? { thread_qos: "uint32_t" } : {}),
});

// ── Load libraries & bind functions ────────────────────────────────
const libkuzu = koffi.load(libkuzuPath);
const libkuzuCffi = koffi.load(libkuzuCffiPath);

// Disposable string type: koffi auto-converts the returned char* to
// a JS string, then calls kuzu_destroy_string to free the C memory.
const kuzu_destroy_string_fn = libkuzu.func(
  "void kuzu_destroy_string(void *str)"
);
const KuzuString = koffi.dispose(
  "KuzuString",
  "char *",
  kuzu_destroy_string_fn
);

// Pointer-based wrappers (from kuzu_cffi_wrapper.c)
const kuzu_default_system_config_ptr = libkuzuCffi.func(
  "void kuzu_default_system_config_ptr(_Out_ kuzu_system_config *out_config)"
);
const kuzu_database_init_ptr = libkuzuCffi.func(
  "int kuzu_database_init_ptr(const char *path, kuzu_system_config *cfg, _Out_ kuzu_database *out)"
);

// Direct C API bindings (all pointer-based, no struct-by-value)
const kuzu_database_destroy = libkuzu.func(
  "void kuzu_database_destroy(kuzu_database *db)"
);
const kuzu_connection_init = libkuzu.func(
  "int kuzu_connection_init(kuzu_database *db, _Out_ kuzu_connection *out)"
);
const kuzu_connection_destroy = libkuzu.func(
  "void kuzu_connection_destroy(kuzu_connection *conn)"
);
const kuzu_connection_query = libkuzu.func(
  "int kuzu_connection_query(kuzu_connection *conn, const char *query, _Out_ kuzu_query_result *out)"
);
const kuzu_query_result_destroy = libkuzu.func(
  "void kuzu_query_result_destroy(kuzu_query_result *qr)"
);
const kuzu_query_result_is_success = libkuzu.func(
  "bool kuzu_query_result_is_success(kuzu_query_result *qr)"
);
const kuzu_query_result_get_error_message = libkuzu.func(
  "KuzuString kuzu_query_result_get_error_message(kuzu_query_result *qr)"
);
const kuzu_query_result_has_next = libkuzu.func(
  "bool kuzu_query_result_has_next(kuzu_query_result *qr)"
);
const kuzu_query_result_get_next = libkuzu.func(
  "int kuzu_query_result_get_next(kuzu_query_result *qr, _Out_ kuzu_flat_tuple *out)"
);
const kuzu_query_result_to_string = libkuzu.func(
  "KuzuString kuzu_query_result_to_string(kuzu_query_result *qr)"
);
const kuzu_flat_tuple_get_value = libkuzu.func(
  "int kuzu_flat_tuple_get_value(kuzu_flat_tuple *tuple, uint64_t idx, _Out_ kuzu_value *out)"
);
const kuzu_value_to_string = libkuzu.func(
  "KuzuString kuzu_value_to_string(kuzu_value *value)"
);
// kuzu_get_version returns a static string — do NOT use KuzuString
// (would attempt to free static memory).
const kuzu_get_version = libkuzu.func("const char *kuzu_get_version()");

// ── Helpers ────────────────────────────────────────────────────────

/** Check that a C API call returned KuzuSuccess (0). */
function check(state: number, context: string): void {
  if (state !== 0) {
    throw new Error(`Kuzu error during ${context} (state=${state})`);
  }
}

/** Execute a Cypher statement. Returns the query-result object. */
function execute(
  conn: Record<string, unknown>,
  cypher: string
): Record<string, unknown> {
  const qr: Record<string, unknown> = {
    _query_result: null,
    _is_owned_by_cpp: false,
  };
  check(kuzu_connection_query(conn, cypher, qr), `query: ${cypher}`);
  if (!kuzu_query_result_is_success(qr)) {
    const msg = kuzu_query_result_get_error_message(qr) ?? "unknown";
    kuzu_query_result_destroy(qr);
    throw new Error(`Kuzu query error: ${msg}`);
  }
  return qr;
}

/**
 * Extract a single column value as a string from the current tuple.
 * Uses kuzu_value_to_string which works for any Kuzu type.
 */
function getValueStr(
  tuple: Record<string, unknown>,
  index: number,
  val: Record<string, unknown>
): string {
  check(kuzu_flat_tuple_get_value(tuple, index, val), `get_value ${index}`);
  return kuzu_value_to_string(val) as string;
}

// ── Main demo ──────────────────────────────────────────────────────

function main(): void {
  const dbPath = "example_db_ts";

  // Clean up any previous run
  if (fs.existsSync(dbPath)) {
    fs.rmSync(dbPath, { recursive: true, force: true });
  }

  console.log(`Kuzu version: ${kuzu_get_version()}\n`);

  // ── Create database and connection ─────────────────────────────
  const cfg: Record<string, unknown> = {};
  kuzu_default_system_config_ptr(cfg);

  const db: Record<string, unknown> = { _database: null };
  check(kuzu_database_init_ptr(dbPath, cfg, db), "database_init");
  console.log(`✓ Created Kuzu database at ./${dbPath}\n`);

  const conn: Record<string, unknown> = { _connection: null };
  check(kuzu_connection_init(db, conn), "connection_init");

  // ── Define schema ──────────────────────────────────────────────
  for (const ddl of [
    "CREATE NODE TABLE User(name STRING, age INT64, PRIMARY KEY (name))",
    "CREATE NODE TABLE City(name STRING, population INT64, PRIMARY KEY (name))",
    "CREATE REL TABLE Follows(FROM User TO User, since INT64)",
    "CREATE REL TABLE LivesIn(FROM User TO City)",
  ]) {
    kuzu_query_result_destroy(execute(conn, ddl));
  }
  console.log("✓ Schema created (User, City, Follows, LivesIn)\n");

  // ── Load data from bundled CSV files ───────────────────────────
  const csvDir = path.join(baseDir, "dataset", "demo-db", "csv");
  for (const stmt of [
    `COPY User FROM "${csvDir}/user.csv"`,
    `COPY City FROM "${csvDir}/city.csv"`,
    `COPY Follows FROM "${csvDir}/follows.csv"`,
    `COPY LivesIn FROM "${csvDir}/lives-in.csv"`,
  ]) {
    kuzu_query_result_destroy(execute(conn, stmt));
  }
  console.log(`✓ Loaded demo data from ${csvDir}\n`);

  // Reusable tuple and value structs for row iteration
  const tuple: Record<string, unknown> = {
    _flat_tuple: null,
    _is_owned_by_cpp: false,
  };
  const val: Record<string, unknown> = {
    _value: null,
    _is_owned_by_cpp: false,
  };

  // ── Query 1: List all users ────────────────────────────────────
  console.log("─── All Users ───────────────────────────────────────────");
  {
    const qr = execute(
      conn,
      "MATCH (u:User) RETURN u.name AS name, u.age AS age ORDER BY u.name"
    );
    while (kuzu_query_result_has_next(qr)) {
      check(kuzu_query_result_get_next(qr, tuple), "get_next");
      const name = getValueStr(tuple, 0, val);
      const age = getValueStr(tuple, 1, val);
      console.log(`  ${name} (age ${age})`);
    }
    kuzu_query_result_destroy(qr);
  }
  console.log();

  // ── Query 2: Who follows whom? ─────────────────────────────────
  console.log("─── Follow Relationships ────────────────────────────────");
  {
    const qr = execute(
      conn,
      "MATCH (a:User)-[f:Follows]->(b:User) " +
        "RETURN a.name AS follower, b.name AS followee, f.since AS since " +
        "ORDER BY f.since"
    );
    while (kuzu_query_result_has_next(qr)) {
      check(kuzu_query_result_get_next(qr, tuple), "get_next");
      const follower = getValueStr(tuple, 0, val);
      const followee = getValueStr(tuple, 1, val);
      const since = getValueStr(tuple, 2, val);
      console.log(`  ${follower} → ${followee} (since ${since})`);
    }
    kuzu_query_result_destroy(qr);
  }
  console.log();

  // ── Query 3: Where does everyone live? ─────────────────────────
  console.log("─── Residence ───────────────────────────────────────────");
  {
    const qr = execute(
      conn,
      "MATCH (u:User)-[:LivesIn]->(c:City) " +
        "RETURN u.name AS person, c.name AS city, c.population AS pop " +
        "ORDER BY u.name"
    );
    while (kuzu_query_result_has_next(qr)) {
      check(kuzu_query_result_get_next(qr, tuple), "get_next");
      const person = getValueStr(tuple, 0, val);
      const city = getValueStr(tuple, 1, val);
      const pop = Number(getValueStr(tuple, 2, val)).toLocaleString();
      console.log(`  ${person} lives in ${city} (pop. ${pop})`);
    }
    kuzu_query_result_destroy(qr);
  }
  console.log();

  // ── Query 4: 2-hop follows from Adam ───────────────────────────
  console.log("─── 2-Hop Follows from Adam ─────────────────────────────");
  {
    const qr = execute(
      conn,
      "MATCH (a:User)-[:Follows]->(b:User)-[:Follows]->(c:User) " +
        "WHERE a.name = 'Adam' " +
        "RETURN a.name AS start, b.name AS mid, c.name AS dest"
    );
    while (kuzu_query_result_has_next(qr)) {
      check(kuzu_query_result_get_next(qr, tuple), "get_next");
      const s = getValueStr(tuple, 0, val);
      const m = getValueStr(tuple, 1, val);
      const d = getValueStr(tuple, 2, val);
      console.log(`  ${s} → ${m} → ${d}`);
    }
    kuzu_query_result_destroy(qr);
  }
  console.log();

  // ── Query 5: Shortest path ─────────────────────────────────────
  // Recursive-rel types are complex to destructure via the C API,
  // so we use the built-in to_string for display.
  console.log("─── Shortest Path: Adam → Noura ─────────────────────────");
  {
    const qr = execute(
      conn,
      "MATCH p = (a:User)-[:Follows* SHORTEST 1..10]->(b:User) " +
        "WHERE a.name = 'Adam' AND b.name = 'Noura' " +
        "RETURN nodes(p), length(p) AS hops"
    );
    console.log(kuzu_query_result_to_string(qr));
    kuzu_query_result_destroy(qr);
  }

  // ── Cleanup ────────────────────────────────────────────────────
  kuzu_connection_destroy(conn);
  kuzu_database_destroy(db);

  if (fs.existsSync(dbPath)) {
    fs.rmSync(dbPath, { recursive: true, force: true });
  }
  console.log(`✓ Cleaned up ${dbPath}. Done!`);
}

main();
