#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST_LIB="${VALLEY_MANIFEST_LIB:-$SCRIPT_DIR/valley_manifest.sh}"
[ -r "$MANIFEST_LIB" ] || { echo "Valley manifest loader not found: $MANIFEST_LIB" >&2; exit 2; }
# shellcheck source=resources/valley_manifest.sh
source "$MANIFEST_LIB"
valley_manifest_init
VERSION=$(valley_manifest_get '.components.validator.bundle.version_current')
RELEASE_REF=$(valley_manifest_get '.components.validator.bundle.release_ref')
RELEASE_REPO=$(valley_manifest_get '.components.validator.bundle.release_repo')
ARTIFACT=$(valley_manifest_get '.components.validator.bundle.release_artifact')
ARTIFACT_SHA256=$(valley_manifest_get '.components.validator.bundle.release_artifact_sha256')
valley_require_sha256 "$ARTIFACT_SHA256" || { echo "Invalid Aristotle digest in VERSIONS.json." >&2; exit 2; }
URL="${RELEASE_REPO}/releases/download/${RELEASE_REF}/${ARTIFACT}"

for tool in curl sha256sum tar; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool missing: $tool" >&2; exit 1; }
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
archive="$tmpdir/$ARTIFACT"
curl -fL --retry 3 "$URL" -o "$archive"
printf '%s  %s\n' "$ARTIFACT_SHA256" "$archive" | sha256sum --check
tar -xzf "$archive" -C "$tmpdir"
source_dir="$tmpdir/aristotle-${VERSION}"
[ -x "$source_dir/bin/0gchaind" ] || { echo "Verified bundle lacks 0gchaind." >&2; exit 1; }
mkdir -p "$HOME/go/bin"
install -m 0755 "$source_dir/bin/0gchaind" "$HOME/go/bin/0gchaind"
echo "0gchaind from managed Aristotle $VERSION installed to $HOME/go/bin/0gchaind"
