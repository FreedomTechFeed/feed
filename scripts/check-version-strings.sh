#!/bin/sh
# check-version-strings.sh - deterministic pre-build gate for net/tollgate-wrt.
#
# Runs offline (no network unless --hash is given) and fails loudly on the
# mistakes that quietly break an OpenWrt package:
#
#   * a `-alphaN` pre-release marker in PKG_VERSION  -> TOKEN_INVALID on apk
#     (25.12+): apk's grammar allows '-' only as the literal -r<digits>.
#   * the apk spelling `0.6.0_alpha1` used on opkg   -> opkg ranks `_alpha1`
#     ABOVE the bare release, so the alpha would never upgrade to 0.6.0.
#   * a hand-written -rN inside PKG_VERSION          -> PKG_RELEASE owns it.
#   * the two PKG_VERSION spellings drifting apart from PKG_SOURCE_VERSION.
#   * missing metadata, an SPDX header that disagrees with PKG_LICENSE, or an
#     install step referencing a file that is not vendored.
#
# Usage:  sh scripts/check-version-strings.sh [--hash]
#   --hash  also download the pinned tarball and verify PKG_HASH
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$REPO_ROOT/net/tollgate-wrt"
MAKEFILE="$PKG_DIR/Makefile"

CHECK_HASH=0
[ "${1:-}" = "--hash" ] && CHECK_HASH=1

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1: expected '$2', got '$3'"; fi; }

[ -f "$MAKEFILE" ] || { echo "ERROR: $MAKEFILE not found" >&2; exit 1; }

val() { sed -n "s/^$1:=//p" "$MAKEFILE" | head -1; }

SOURCE_VERSION="$(val PKG_SOURCE_VERSION)"
COMMIT="$(val PKG_SOURCE_COMMIT)"
HASH="$(val PKG_HASH)"
RELEASE="$(val PKG_RELEASE)"
MAINTAINER="$(val PKG_MAINTAINER)"
LICENSE="$(val PKG_LICENSE)"
LICENSE_FILES="$(val PKG_LICENSE_FILES)"

echo "== version identity =="
[ -n "$SOURCE_VERSION" ] || { bad "PKG_SOURCE_VERSION is set"; SOURCE_VERSION=""; }

if printf '%s' "$SOURCE_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc|pre)[0-9]+)?$'; then
	ok "PKG_SOURCE_VERSION looks like a release tag body ($SOURCE_VERSION)"
else
	bad "PKG_SOURCE_VERSION '$SOURCE_VERSION' is not X.Y.Z[-suffixN]"
fi

case "$SOURCE_VERSION" in
*-*) EXP_APK="$(printf '%s' "$SOURCE_VERSION" | sed 's/^\([0-9.]*\)-\(.*\)$/\1_\2/')"
     EXP_OPKG="$(printf '%s' "$SOURCE_VERSION" | sed 's/^\([0-9.]*\)-\(.*\)$/\1~\2/')" ;;
*)   EXP_APK="$SOURCE_VERSION"; EXP_OPKG="$SOURCE_VERSION" ;;
esac

# The two PKG_VERSION lines sit inside the CONFIG_USE_APK conditional, apk first.
APK_VERSION="$(sed -n '/^ifeq (\$(CONFIG_USE_APK),y)$/,/^endif$/p' "$MAKEFILE" | sed -n 's/^PKG_VERSION:=//p' | head -1)"
OPKG_VERSION="$(sed -n '/^ifeq (\$(CONFIG_USE_APK),y)$/,/^endif$/p' "$MAKEFILE" | sed -n 's/^PKG_VERSION:=//p' | tail -1)"

check "apk PKG_VERSION spelling" "$EXP_APK" "$APK_VERSION"
check "opkg PKG_VERSION spelling" "$EXP_OPKG" "$OPKG_VERSION"

for v in "$APK_VERSION" "$OPKG_VERSION"; do
	case "$v" in
	*-alpha*|*-beta*|*-rc*|*-pre*) bad "PKG_VERSION '$v' uses '-' before a pre-release suffix (TOKEN_INVALID on apk)" ;;
	*'-r'[0-9]*) bad "PKG_VERSION '$v' carries a hand-written -rN (PKG_RELEASE owns it)" ;;
	*) ok "PKG_VERSION '$v' has no '-' suffix and no hand-written -rN" ;;
	esac
done
case "$APK_VERSION" in *'~'*) bad "apk PKG_VERSION uses '~' (opkg marker)";; *) ok "apk PKG_VERSION uses the '_' marker";; esac
case "$OPKG_VERSION" in *_*) bad "opkg PKG_VERSION uses '_' (ranks above the release on opkg)";; *) ok "opkg PKG_VERSION uses the '~' marker";; esac

echo "== source pin =="
[ -n "$HASH" ] && [ "$HASH" != "skip" ] && ok "PKG_HASH is a real sha256" || bad "PKG_HASH is empty or 'skip'"
printf '%s' "$HASH" | grep -qE '^[0-9a-f]{64}$' && ok "PKG_HASH is 64 hex chars" || bad "PKG_HASH is not a 64-char sha256"
printf '%s' "$COMMIT" | grep -qE '^[0-9a-f]{40}$' && ok "PKG_SOURCE_COMMIT is a full commit id" || bad "PKG_SOURCE_COMMIT is not a 40-char commit id"

echo "== metadata =="
printf '%s' "$MAINTAINER" | grep -qE '^.+ <.+@.+>$' && ok "PKG_MAINTAINER is 'Name <email>'" || bad "PKG_MAINTAINER '$MAINTAINER' is not 'Name <email>'"
[ -n "$LICENSE" ] && ok "PKG_LICENSE=$LICENSE" || bad "PKG_LICENSE missing"
[ -n "$LICENSE_FILES" ] && ok "PKG_LICENSE_FILES=$LICENSE_FILES" || bad "PKG_LICENSE_FILES missing"
[ "$RELEASE" = "1" ] && ok "PKG_RELEASE=$RELEASE" || bad "PKG_RELEASE should be 1 on a version bump (got '$RELEASE')"

# SPDX header in the Makefile must agree with PKG_LICENSE.
SPDX="$(sed -n 's/^# SPDX-License-Identifier: //p' "$MAKEFILE" | head -1)"
check "Makefile SPDX header == PKG_LICENSE" "$LICENSE" "$SPDX"

grep -q '^define Package/tollgate-wrt/conffiles$' "$MAKEFILE" && ok "conffiles registered" || bad "no conffiles block"
grep -q 'USE_PROCD=1' "$PKG_DIR/files/etc/init.d/tollgate-wrt" && ok "init script sets USE_PROCD=1" || bad "init script is not procd-based"
grep -q '^start_service()' "$PKG_DIR/files/etc/init.d/tollgate-wrt" && ok "init script defines start_service()" || bad "init script has no start_service()"
grep -q '^PKG_BUILD_DEPENDS:=golang/host' "$MAKEFILE" && ok "PKG_BUILD_DEPENDS pulls the Go host toolchain" || bad "PKG_BUILD_DEPENDS:=golang/host missing"
grep -q '^GO_PKG_LDFLAGS_X' "$MAKEFILE" && ok "ldflags version injection present" || bad "GO_PKG_LDFLAGS_X missing"

echo "== vendored runtime files =="
[ -d "$PKG_DIR/files" ] && [ -n "$(find "$PKG_DIR/files" -type f -print -quit)" ] && ok "files/ is populated ($(find "$PKG_DIR/files" -type f | wc -l | tr -d ' ') files)" || bad "files/ is empty or missing"
[ -d "$PKG_DIR/portal-assets/assets" ] && ok "portal-assets/assets present ($(find "$PKG_DIR/portal-assets/assets" -type f | wc -l | tr -d ' ') bundles)" || bad "portal-assets/assets missing"

# Every ./files/<path> referenced by the install recipe must exist.
missing=""
for ref in $(sed -n '/^define Package\/tollgate-wrt\/install$/,/^endef$/p' "$MAKEFILE" \
             | grep -oE '\./files/[^ ]+' | sort -u); do
	case "$ref" in
	*\**)
		dir="$PKG_DIR/$(dirname "${ref#./}")"
		pat="$(basename "$ref")"
		[ -n "$(find "$dir" -name "$pat" -print -quit 2>/dev/null)" ] || missing="$missing $ref"
		;;
	*)
		[ -e "$PKG_DIR/${ref#./}" ] || missing="$missing $ref"
		;;
	esac
done
if [ -z "$missing" ]; then ok "every referenced files/ path exists"; else bad "missing referenced paths:$missing"; fi

if [ "$CHECK_HASH" = "1" ]; then
	echo "== PKG_HASH vs live tarball =="
	URL="https://codeload.github.com/OpenTollGate/tollgate-module-basic-go/tar.gz/v$(val PKG_SOURCE_VERSION)?"
	WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
	curl -fsSL -o "$WORK/src.tar.gz" "$URL" || { bad "could not download $URL"; FAIL=$((FAIL+1)); }
	if [ -f "$WORK/src.tar.gz" ]; then
		LIVE="$(sha256sum "$WORK/src.tar.gz" | awk '{print $1}')"
		check "PKG_HASH == live tarball" "$HASH" "$LIVE"
		mkdir -p "$WORK/extracted"
		tar -xzf "$WORK/src.tar.gz" -C "$WORK/extracted"
		# A codeload tarball extracts under its own top-level directory
		# (<repo>-<tag>/), so packaging/files/ is NOT at $WORK/extracted/.
		# Locate it instead of assuming the depth.
		TAR_FILES="$(find "$WORK/extracted" -type d -path '*/packaging/files' -print -quit)"
		if [ -z "$TAR_FILES" ]; then
			bad "pinned tarball has no packaging/files/ tree"
		elif diff -r "$PKG_DIR/files" "$TAR_FILES" >"$WORK/files.diff" 2>&1; then
			printf '  PASS  files/ is byte-identical to the pinned tag'"'"'s packaging/files/ (%s files)\n' \
				"$(find "$PKG_DIR/files" -type f | wc -l | tr -d ' ')"
			PASS=$((PASS + 1))
		else
			bad "files/ differs from the pinned tag's packaging/files/ (diff, first 40 lines):"
			sed -n '1,40p' "$WORK/files.diff"
		fi
	fi
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
