#!/bin/bash
# Run the offline unit tests (no game needed).
cd "$(dirname "$0")/../tests" && python3 run_tests.py "$@"
