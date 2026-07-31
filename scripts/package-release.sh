#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: package-release.sh TAG OUTPUT_DIR}"
output_dir="${2:?usage: package-release.sh TAG OUTPUT_DIR}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$output_dir/quickshell-quotas-widget-$tag.tar.gz"

mkdir -p -- "$output_dir"
tar -C "$repo_root" -czf "$archive" Quotas.qml QuotasPopup.qml get-quotas.sh
printf '%s\n' "$archive"
