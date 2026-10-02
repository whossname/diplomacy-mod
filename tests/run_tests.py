#!/usr/bin/env python3
"""Runs the Lua unit tests for the Diplomacy Mod gadget.

The BAR/Spring Lua sandbox has no package manager available in this
environment, so these tests run through `lupa` (an embedded Lua runtime for
Python) instead of a standalone `lua` binary. Install it once with:

    pip install lupa

Usage:
    python3 tests/run_tests.py
"""
import os
import sys

try:
    import lupa
except ImportError:
    sys.stderr.write(
        "lupa is required to run these tests. Install it with:\n"
        "    pip install lupa\n"
    )
    sys.exit(1)


def main():
    test_dir = os.path.dirname(os.path.abspath(__file__)) + os.sep
    spec_path = os.path.join(test_dir, "diplomacy_spec.lua")

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().TEST_DIR = test_dir

    with open(spec_path, "r") as f:
        spec_code = f.read()

    passed = lua.execute(spec_code)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
