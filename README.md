# Forked Copy of Kuzu Graph Database Updated to use uv

For original information see

https://github.com/kuzudb/kuzu/
> 
Original documentation:

     http://kuzudb.github.io/docs


## Python Development with `uv`

This project uses [`uv`](https://docs.astral.sh/uv/) for all Python workflows.
The native C++ library is built via CMake, and the Python bindings are packaged
so that `uv add kuzu` works from any project on your machine.

### Prerequisites

| Tool | Minimum Version | Install |
|------|----------------|---------|
| `uv` | 0.4+ | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| CMake | 3.15+ | `brew install cmake` (macOS) |
| C++20 compiler | Clang 15+ / GCC 11+ | Xcode CLT or system package |
| Python | 3.9+ | managed by `uv` or system |

### Quick Start — Build & Install

```bash
# 1. Build the C++ library + Python extension and install system-wide:
make python-install

# 2. Run the included demo:
python3 example.py
# — or —
uv run example.py
```
`make python-install` does two things:
1. **`make python`** — configures and builds the C++ engine + pybind11 bindings via CMake
2. **`uv pip install --system .`** — packages the built `.so` and Python sources into a wheel and installs it into your system Python

### Using Kuzu from Other Projects

Once installed via `make python-install`, kuzu is available system-wide:

```bash
# In any other project:
uv init --bare
uv add kuzu
uv run python -c "import kuzu; print(kuzu.version)"
```

Or reference the source tree directly (builds from source on first use):

```bash
uv add kuzu --path /path/to/kuzu
```

### Make Targets (Python)

| Target | Description |
|--------|-------------|
| `make python` | Build C++ engine + Python bindings (output in `tools/python_api/build/kuzu/`) |
| `make python-install` | Build + install into system Python via `uv pip install --system .` |
| `make python-debug` | Debug build of the Python bindings |
| `make pytest` | Run the Python test suite |
| `make pytest-venv` | Run tests inside a `uv`-managed virtualenv |

### Running `example.py`

The demo creates a temporary database, loads the bundled CSV data, and runs
several Cypher queries (listing nodes, traversals, shortest path):

```bash
uv run example.py
```

```
✓ Created Kuzu database at ./example_db
✓ Schema created (User, City, Follows, LivesIn)
✓ Loaded demo data from dataset/demo-db/csv
─── All Users ───────────────────────────────────────────
  Adam (age 30)  ·  Karissa (age 40)  ·  Noura (age 25)  ·  Zhang (age 50)
─── Shortest Path: Adam → Noura ─────────────────────────
  Path (2 hops): Adam → Zhang → Noura
✓ Cleaned up example_db. Done!
```

### Dev Workflow (Python API)

For working on the Python bindings themselves, the sub-Makefile in
`tools/python_api/` manages a local virtualenv via `uv`:

```bash
cd tools/python_api
make requirements   # uv venv + uv pip install -r requirements_dev.txt
make lint           # ruff + mypy
make format         # ruff format
make pytest         # run tests against the built extension
```

---

# Kuzu
Kuzu is an embedded graph database built for query speed and scalability. Kuzu is optimized for handling complex analytical workloads 
on very large databases and provides a set of retrieval features, such as a full text search and vector indices. Our core feature set includes:

- Flexible Property Graph Data Model and Cypher query language
- Embeddable, serverless integration into applications
- Native full text search and vector index
- Columnar disk-based storage
- Columnar sparse row-based (CSR) adjacency list/join indices
- Vectorized and factorized query processor
- Novel and very fast join algorithms
- Multi-core query parallelism
- Serializable ACID transactions
- Wasm (WebAssembly) bindings for fast, secure execution in the browser

Kuzu was initially developed by Kùzu Inc. It is available under a permissible license.

## License
Kuzu is licensed under the [MIT License](LICENSE).
