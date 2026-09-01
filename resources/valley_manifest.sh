#!/usr/bin/env bash

# Shared read-only manifest loader for Valley managed component sources.
# Callers may provide VALLEY_MANIFEST_PATH; otherwise a local checkout is used.
valley_manifest_init() {
    local library_dir
    if [ -z "${VALLEY_MANIFEST_PATH:-}" ]; then
        library_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
        VALLEY_MANIFEST_PATH="${library_dir}/../VERSIONS.json"
    fi

    if [ ! -r "$VALLEY_MANIFEST_PATH" ]; then
        echo "VERSIONS.json is required for this managed operation: $VALLEY_MANIFEST_PATH" >&2
        return 2
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is required to read VERSIONS.json." >&2
        return 2
    fi
    if ! jq -e '.network == "0g-mainnet" and (.schema_version | type == "string")' "$VALLEY_MANIFEST_PATH" >/dev/null 2>&1; then
        echo "VERSIONS.json is invalid or is not the 0G mainnet manifest." >&2
        return 2
    fi
    export VALLEY_MANIFEST_PATH
}

valley_manifest_get() {
    local query=$1 value
    value=$(jq -er "$query | select(. != null and . != \"\")" "$VALLEY_MANIFEST_PATH" 2>/dev/null) || {
        echo "Required VERSIONS.json field is missing: $query" >&2
        return 2
    }
    printf '%s\n' "$value"
}

valley_require_git_commit() {
    [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]
}

valley_require_sha256() {
    [[ "${1:-}" =~ ^[0-9a-f]{64}$ ]]
}
