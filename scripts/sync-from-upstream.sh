#!/bin/sh
# sync-from-upstream.sh - re-pin the package to an upstream release tag.
#
# Usage:
#   scripts/sync-from-upstream.sh <tag>      # e.g. v0.6.0-alpha1
#   scripts/sync-from-upstream.sh 0.6.0-alpha1
#
# What it does:
#   1. Downloads the release tarball for <tag> from codeload.github.com and
#      computes its sha256.
#   2. Rewrites PKG_SOURCE_VERSION (the tag body), PKG_SOURCE_COMMIT, PKG_HASH
#      and BOTH PKG_VERSION spellings in net/tollgate-wrt/Makefile:
#        apk  (>= 25.12) pre-release marker:  _alpha1   (-alpha1 is invalid)
#        opkg (<= 24.10) pre-release marker:  ~alpha1
#      Never a hand-written -rN: PKG_RELEASE owns the revision.
#   3. Re-vendors the tarball's packaging/files/ into net/tollgate-wrt/files/
#      byte for byte, so `diff -r net/tollgate-wrt/files <tarball>/packaging/
#      files` is empty.
#   4. Cross-checks net/tollgate-wrt/portal-assets/assets against the tarball's
#      asset-manifest.json and warns when the release expects different portal
#      bundles. Those are built with npm from the separate tollgate-captive-
#      portal-site repository and cannot be produced by an OpenWrt build.
#
# Review the diff and commit. Only the tarball download needs the network.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$REPO_ROOT/net/tollgate-wrt/Makefile"
FILES_DIR="$REPO_ROOT/net/tollgate-wrt/files"
ASSETS_DIR="$REPO_ROOT/net/tollgate-wrt/portal-assets/assets"
UPSTREAM="OpenTollGate/tollgate-module-basic-go"

TAG="${1:-}"
if [ -z "$TAG" ]; then
	echo "Usage: $0 <tag>   (e.g. v0.6.0-alpha1)" >&2
	exit 1
fi
TAG="v${1#v}"                    # normalise to vX.Y.Z[-suffix]
SOURCE_VERSION="${TAG#v}"        # 0.6.0-alpha1

# Only vX.Y.Z and vX.Y.Z-<suffix>N are accepted. A two-part suffix such as
# v0.6.0-rc-alpha1 publishes into the wrong release channel and breaks the apk
# version string (upstream documents this in docs/release-process.md).
if ! printf '%s' "$SOURCE_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc|pre)[0-9]+)?$'; then
	echo "ERROR: '$SOURCE_VERSION' is not a supported release tag shape." >&2
	echo "       expected vX.Y.Z or vX.Y.Z-(alpha|beta|rc|pre)N" >&2
	exit 1
fi

# Same version, spelled for each package manager. A release with no suffix is
# already valid for both, so the substitution is then a no-op.
APK_VERSION="$(printf '%s' "$SOURCE_VERSION" | sed 's/^\([0-9.]*\)-\(.*\)$/\1_\2/')"
OPKG_VERSION="$(printf '%s' "$SOURCE_VERSION" | sed 's/^\([0-9.]*\)-\(.*\)$/\1~\2/')"

URL="https://codeload.github.com/${UPSTREAM}/tar.gz/${TAG}"

for dep in curl tar sha256sum sed grep awk git; do
	command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: missing tool: $dep" >&2; exit 1; }
done
[ -f "$MAKEFILE" ] || { echo "ERROR: $MAKEFILE not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading $URL"
curl -fsSL -o "$WORK/source.tar.gz" "$URL"
HASH="$(sha256sum "$WORK/source.tar.gz" | awk '{print $1}')"
echo "==> sha256 = $HASH"

echo "==> Extracting"
mkdir -p "$WORK/extract"
tar -xzf "$WORK/source.tar.gz" -C "$WORK/extract"
SRC_FILES="$WORK/extract/${UPSTREAM#*/}-${SOURCE_VERSION}/packaging/files"
[ -d "$SRC_FILES" ] || { echo "ERROR: packaging/files/ not found in the tarball (layout changed?)" >&2; exit 1; }

COMMIT="$(git ls-remote "https://github.com/${UPSTREAM}.git" "refs/tags/${TAG}^{}" 2>/dev/null | awk '{print $1}')"
[ -n "$COMMIT" ] || COMMIT="$(git ls-remote "https://github.com/${UPSTREAM}.git" "refs/tags/${TAG}" 2>/dev/null | awk '{print $1}')"
[ -n "$COMMIT" ] || { echo "ERROR: could not resolve ${TAG} to a commit" >&2; exit 1; }
echo "==> commit = $COMMIT"

echo "==> Re-vendoring packaging/files/ into net/tollgate-wrt/files/"
rm -rf "$FILES_DIR"
mkdir -p "$FILES_DIR"
cp -a "$SRC_FILES/." "$FILES_DIR/"
find "$FILES_DIR" -type f | wc -l | awk '{printf "    %d files copied\n", $1}'

MANIFEST="$FILES_DIR/tollgate-captive-portal-site/asset-manifest.json"
if [ -f "$MANIFEST" ] && [ -d "$ASSETS_DIR" ]; then
	want="$(grep -oE '"assets/[^"]+"' "$MANIFEST" | tr -d '"' | sort)"
	have="$(cd "$ASSETS_DIR" && find . -type f | sed 's|^\./|assets/|' | sort)"
	if [ "$want" = "$have" ]; then
		echo "==> portal-assets/ matches the release manifest ($(printf '%s\n' "$have" | wc -l | tr -d ' ') bundles)"
	else
		echo "!! WARNING: portal-assets/ does not match this release's asset-manifest.json" >&2
		echo "!! Rebuild the SPA from OpenTollGate/tollgate-captive-portal-site" >&2
		echo "!! (npm ci && npm run build) and replace portal-assets/assets/ - see portal-assets/README.md" >&2
		printf '   manifest wants:\n%s\n   vendored:\n%s\n' "$want" "$have" >&2
	fi
fi

echo "==> Updating Makefile"
awk -v apk="$APK_VERSION" -v opkg="$OPKG_VERSION" -v srcver="$SOURCE_VERSION" \
    -v commit="$COMMIT" -v hash="$HASH" '
	/^PKG_SOURCE_VERSION:=/ { print "PKG_SOURCE_VERSION:=" srcver; next }
	/^PKG_SOURCE_COMMIT:=/  { print "PKG_SOURCE_COMMIT:=" commit; next }
	/^PKG_HASH:=/           { print "PKG_HASH:=" hash; next }
	/^ifeq \(\$\(CONFIG_USE_APK\),y\)$/ { inblk = 1; print; next }
	inblk && /^PKG_VERSION:=/ { n++; print "PKG_VERSION:=" (n == 1 ? apk : opkg); next }
	inblk && /^endif$/ { inblk = 0; print; next }
	{ print }
' "$MAKEFILE" > "$WORK/Makefile.new"
mv "$WORK/Makefile.new" "$MAKEFILE"

# Prove the rewrite actually landed the values we computed.
for expect in "PKG_SOURCE_VERSION:=$SOURCE_VERSION" "PKG_SOURCE_COMMIT:=$COMMIT" "PKG_HASH:=$HASH" \
              "PKG_VERSION:=$APK_VERSION" "PKG_VERSION:=$OPKG_VERSION"; do
	grep -qxF "$expect" "$MAKEFILE" || { echo "ERROR: Makefile rewrite failed for '$expect'" >&2; exit 1; }
done

echo
echo "   PKG_SOURCE_VERSION = $SOURCE_VERSION"
echo "   PKG_VERSION (apk)  = $APK_VERSION"
echo "   PKG_VERSION (opkg) = $OPKG_VERSION"
echo "   PKG_HASH           = $HASH"
echo
echo "Done. Verify with:"
echo "  git -C $REPO_ROOT diff --stat"
echo "  diff -r $FILES_DIR $SRC_FILES    # must print nothing"
echo "  sh $REPO_ROOT/scripts/check-version-strings.sh"
