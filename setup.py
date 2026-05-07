"""
Custom setuptools build for Kuzu Python bindings.

This setup.py builds the C++ native extension via CMake and packages
the resulting Python module for installation. It enables:
  - `uv pip install .`         (from this directory)
  - `uv add kuzu --path /path/to/kuzu`  (from any project)
"""

import multiprocessing
import os
import re
import shutil
import subprocess
import sys

from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext
from setuptools.command.build_py import build_py as _build_py

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _get_kuzu_version():
    """Extract the version from CMakeLists.txt."""
    cmake_file = os.path.join(BASE_DIR, "CMakeLists.txt")
    with open(cmake_file) as f:
        for line in f:
            if line.startswith("project(Kuzu VERSION"):
                raw_version = line.split(" ")[2].strip().rstrip(")")
                version_nums = raw_version.split(".")
                if len(version_nums) <= 3:
                    return raw_version
                else:
                    dev_suffix = version_nums[3]
                    version = ".".join(version_nums[:3])
                    version += ".dev%s" % dev_suffix
                    return version
    msg = "Could not find version in CMakeLists.txt"
    raise RuntimeError(msg)


class CMakeExtension(Extension):
    """A CMake-based extension module (no Python sources)."""

    def __init__(self, name, sourcedir=""):
        super().__init__(name, sources=[])
        self.sourcedir = os.path.abspath(sourcedir)


class CMakeBuild(build_ext):
    """Build the Kuzu C++ library + pybind11 bindings via Make/CMake."""

    def build_extension(self, ext):
        self.announce("Building Kuzu native Python extension via CMake...")

        env_vars = os.environ.copy()
        python_version = "%d.%d" % (sys.version_info.major, sys.version_info.minor)
        env_vars["PYBIND11_PYTHON_VERSION"] = python_version
        env_vars["PYTHON_EXECUTABLE"] = sys.executable

        if sys.platform == "darwin":
            archflags = os.getenv("ARCHFLAGS", "")
            if "arm64" in archflags:
                env_vars["CMAKE_OSX_ARCHITECTURES"] = "arm64"
            elif "x86_64" in archflags:
                env_vars["CMAKE_OSX_ARCHITECTURES"] = "x86_64"

            deploy_target = os.getenv("MACOSX_DEPLOYMENT_TARGET", "")
            if deploy_target:
                env_vars["CMAKE_OSX_DEPLOYMENT_TARGET"] = deploy_target

        try:
            num_cores = int(os.environ.get("NUM_THREADS", 0)) or multiprocessing.cpu_count()
        except Exception:
            num_cores = 4

        # Build native extension via the project Makefile
        full_cmd = ["make", "python", "NUM_THREADS=%d" % num_cores]
        self.announce("Running: %s" % " ".join(full_cmd))
        subprocess.run(full_cmd, cwd=BASE_DIR, check=True, env=env_vars)
        self.announce("Done building native extension.")

        # Copy the built extension into the setuptools output directory
        build_dir = os.path.join(BASE_DIR, "tools", "python_api", "build", "kuzu")
        dst = os.path.join(self.build_lib, "kuzu")
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(build_dir, dst)
        self.announce("Copied built extension to %s" % dst)


class BuildExtFirst(_build_py):
    """Ensure the C++ extension is built before collecting Python packages."""

    def run(self):
        self.run_command("build_ext")
        return super().run()


setup(
    name="kuzu",
    version=_get_kuzu_version(),
    ext_modules=[CMakeExtension(name="kuzu._kuzu", sourcedir=BASE_DIR)],
    packages=["kuzu"],
    package_dir={"kuzu": "tools/python_api/src_py"},
    cmdclass={
        "build_py": BuildExtFirst,
        "build_ext": CMakeBuild,
    },
)
