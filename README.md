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

## C Shared Library (for Common Lisp, etc.)

Build `libkuzu` for use with CFFI-based language bindings:

```bash
make c-lib
make install PREFIX=./install
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
| `make c-lib` | Build the shared library for C/CL CFFI use |
| `make install` | Install built artifacts to `PREFIX` (default: `./install`) |
| `make clean` | Remove all build artifacts |

## License

Kuzu is licensed under the [MIT License](LICENSE).
