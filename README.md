# Kuzu Graph Database (Fork — v0.11.2.dev2)

An embeddable property-graph database with Cypher query support.
This is a simplified fork focused on **Python** and **C library** builds.

Original project: <https://github.com/kuzudb/kuzu/>

## Prerequisites

| Tool | Minimum Version | Install |
|------|----------------|---------|
| `uv` | 0.4+ | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| CMake | 3.15+ | `brew install cmake` (macOS) |
| C++20 compiler | Clang 15+ / GCC 11+ | Xcode CLT or system package |
| Python | 3.9+ | managed by `uv` or system |

## Quick Start — Python

```bash
# Build C++ engine + Python bindings, install system-wide:
make python-install

# Run the demo:
uv run example.py
```

### Using Kuzu from other projects

Once installed, Kuzu is available system-wide:

```bash
uv init --bare
uv add kuzu
uv run python -c "import kuzu; print(kuzu.version)"
```

Or reference this source tree directly:

```bash
uv add kuzu --path /path/to/kuzu
```

## C Shared Library & Common Lisp

Build `libkuzu` and the CFFI wrapper for Common Lisp:

```bash
make c-lib
```

Run the Common Lisp demo (requires SBCL + Quicklisp with `cffi`):

```bash
sbcl --load example.lisp
```

The C header is at `src/include/c_api/kuzu.h`.

## Make Targets

| Target | Description |
|--------|-------------|
| `make release` | Build the core C++ engine (release mode) |
| `make debug` | Debug build |
| `make python` | Build C++ engine + Python bindings |
| `make python-install` | Build + install Python package via `uv pip install --system .` |
| `make pytest` | Run the Python test suite |
| `make c-lib` | Build shared library + CFFI wrapper for C/CL use |
| `make cffi-wrapper` | Build just the thin CL CFFI wrapper (requires `make release` first) |
| `make swi-prolog` | Build SWI-Prolog foreign library bridge |
| `make install` | Install built artifacts to `PREFIX` (default: `./install`) |
| `make clean` | Remove all build artifacts |


## TypeScript (FFI via koffi)

Run the TypeScript demo, which calls the C API directly using [koffi](https://koffi.dev/):

```bash
# Ensure the shared libraries are built first:
make c-lib

# Install Node dependencies (one-time):
npm install

# Run the demo:
npx tsx example.ts
```

## SWI-Prolog (Foreign Library Bridge)

Run the SWI-Prolog demo, which calls the C API through a foreign-language bridge:

```bash
# Build the core engine + Prolog bridge:
make swi-prolog

# Run the demo:
swipl example.pl
```

## License

Kuzu is licensed under the [MIT License](LICENSE).
