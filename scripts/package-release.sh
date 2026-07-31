#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: package-release.sh TAG OUTPUT_DIR}"
output_dir="${2:?usage: package-release.sh TAG OUTPUT_DIR}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$output_dir/quickshell-quotas-widget-$tag.tar.gz"

mkdir -p -- "$output_dir"
tar -C "$repo_root" \
    --sort=name \
    --format=gnu \
    --mtime='@0' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mode=0644 \
    -cf - \
    Quotas.qml QuotasPopup.qml get-quotas.sh \
    | gzip -n >"$archive"
printf '%s\n' "$archive"
