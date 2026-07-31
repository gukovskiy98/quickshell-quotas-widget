#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for test_file in "$repo_root"/tests/test_*.bash; do
    bash "$test_file"
done
