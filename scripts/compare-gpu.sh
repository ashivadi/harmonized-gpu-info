#!/bin/bash

# Diff harmonized GPU/system JSON files, similar to compare.sh for ec2 instances.
# Files already exist locally under harmonized_gpu_info/{gpus,systems}, so there's
# no download step - just resolve names/patterns to paths and vimdiff them.
#
# Usage:
#   ./compare-gpu.sh h100-sxm-80gb h200-sxm-141gb
#   ./compare-gpu.sh b200-sxm-hgx b300-sxm-hgx
#   ./compare-gpu.sh systems/hgx-b200 systems/hgx-b300
#   ./compare-gpu.sh gpus/a100-sxm4-40gb.json gpus/a100-sxm4-80gb.json
#   ./compare-gpu.sh '*a100*'          # glob: matches every a100 SKU, all opened together
#   ./compare-gpu.sh 'h200-*'          # glob: matches h200-sxm + h200-nvl

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$(dirname "$SCRIPT_DIR")"

# resolve one arg (exact name or glob pattern) to one or more file paths, printed one per line
resolve() {
    local name="${1%.json}"

    # exact match first (fast path, preserves old behavior/error message)
    for candidate in "$DATA_DIR/$name.json" "$DATA_DIR/gpus/$name.json" "$DATA_DIR/systems/$name.json"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done

    # no exact match - try as a glob pattern against gpus/ and systems/
    local matches=()
    shopt -s nullglob nocaseglob
    matches+=("$DATA_DIR"/gpus/$name.json)
    matches+=("$DATA_DIR"/systems/$name.json)
    shopt -u nullglob nocaseglob

    if [ "${#matches[@]}" -eq 0 ]; then
        echo "ERROR: could not find '$1' in gpus/ or systems/ (tried exact match and glob)" >&2
        exit 1
    fi

    printf '%s\n' "${matches[@]}"
}

files=()
for arg in "$@"; do
    while IFS= read -r path; do
        files+=("$path")
    done < <(resolve "$arg")
done

if [ "${#files[@]}" -lt 2 ]; then
    echo "ERROR: need at least 2 files to diff, found ${#files[@]}: ${files[*]}" >&2
    exit 1
fi

echo "Comparing ${#files[@]} file(s):" >&2
printf '  %s\n' "${files[@]}" >&2

vimdiff "${files[@]}"
