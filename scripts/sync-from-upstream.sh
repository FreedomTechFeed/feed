#!/bin/sh
# sync-from-upstream.sh — re-vendor runtime files/ and re-pin PKG_HASH/PKG_VERSION
# for a given upstream tollgate-module-basic-go release tag.
#
# Usage:
#   scripts/sync-from-upstream.sh <tag>      # e.g. v0.5.0
#   scripts/sync-from-upstream.sh 0.5.0      # leading 'v' is optional
#
# What it does:
#   1. Downloads the source tarball for <tag> from codeload.github.com.
#   2. Computes its sha256 and updates PKG_HASH in net/tollgate-wrt/Makefile.
#   3. Sets PKG_VERSION (stripped of a leading 'v').
#   4. Re-vendors upstream packaging/files/ into net/tollgate-wrt/files/.
#
# After running, review the diff and commit. The generated captive-portal-site
# assets (HTML/CSS/JS/PNG) are large and change every upstream release — that
# is expected; re-commit them wholesale.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$REPO_ROOT/net/tollgate-wrt/Makefile"
FILES_DIR="$REPO_ROOT/net/tollgate-wrt/files"
UPSTREAM="OpenTollGate/tollgate-module-basic-go"

TAG="${1:-}"
if [ -z "$TAG" ]; then
	echo "Usage: $0 <tag>   (e.g. v0.5.0)" >&2
	exit 1
fi

# PKG_VERSION has no leading 'v'; the tarball URL adds it back via v$(PKG_VERSION).
PKG_VERSION="${TAG#v}"
URL="https://codeload.github.com/${UPSTREAM}/tar.gz/v${PKG_VERSION}"

for dep in curl tar sha256sum; do
	command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: missing tool: $dep" >&2; exit 1; }
done
[ -f "$MAKEFILE" ] || { echo "ERROR: $MAKEFILE not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading $URL"
TARBALL="$WORK/source.tar.gz"
curl -fsSL -o "$TARBALL" "$URL"
HASH="$(sha256sum "$TARBALL" | awk '{print $1}')"
echo "==> sha256 = $HASH"

echo "==> Extracting packaging/files/ from tarball"
EXTRACT_TOP="${UPSTREAM#*/}-${PKG_VERSION}"   # tollgate-module-basic-go-0.5.0
mkdir -p "$WORK/extract"
tar -xzf "$TARBALL" -C "$WORK/extract"

SRC_FILES="$WORK/extract/$EXTRACT_TOP/packaging/files"
if [ ! -d "$SRC_FILES" ]; then
	echo "ERROR: packaging/files/ not found in tarball (looked for $SRC_FILES)" >&2
	echo "       Has the upstream layout changed?" >&2
	exit 1
fi

echo "==> Re-vendorings into net/tollgate-wrt/files/"
rm -rf "$FILES_DIR"
mkdir -p "$FILES_DIR"
cp -a "$SRC_FILES/." "$FILES_DIR/"
find "$FILES_DIR" -type f | wc -l | awk '{printf "    %d files copied\n", $1}'

echo "==> Updating Makefile (PKG_VERSION=$PKG_VERSION, PKG_HASH=$HASH)"
# Replace only the PKG_VERSION / PKG_HASH definition lines.
sed -i \
	-e "s|^PKG_VERSION:.*|PKG_VERSION:=$PKG_VERSION|" \
	-e "s|^PKG_HASH:.*|PKG_HASH:=$HASH|" \
	"$MAKEFILE"

echo
echo "Done. Review with:  git -C \"$REPO_ROOT\" diff --stat"
echo "Then build-validate via the validate-feed.yml CI (SDK job)."
