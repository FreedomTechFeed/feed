#!/bin/sh
# sync-from-canonical.sh — make this repo a WRAPPER of the canonical recipe.
#
# THINKING ALOUD. This repo (Gen-1) and FreedomTechFeed/packages' net/
# tollgate-wrt (Gen-2) are two hand-maintained copies of one OpenWrt
# recipe. Gen-2 grew vendor.lock.json, build-in-CI portal bundling, both-
# directions tarball-parity gating, main-tip SHA pins and the apk-legal
# pre-release scheme; Gen-1 stayed on the v0.5.0 release tarball with
# committed built portal assets (violating the build-in-CI rule Gen-2
# enforces), a CLI version injection Gen-2 fixed in pre5, and no CVM
# daemon. Same defect class, two lifetimes, zero shared declarations —
# the definition of split brain. The DRY end-state: ONE recipe (Gen-2,
# where the fences live), and this repo either mirrors it or points at
# it. This script does the mirroring, mechanically.
#
# What it does:
#   1. fetches FreedomTechFeed/packages at the requested ref (default:
#      master),
#   2. copies net/tollgate-wrt/ over this repo's copy WHOLESALE (recipe,
#      tests, scripts, vendor.lock.json — the fences come with it),
#   3. rewrites ONE line for standalone-feed use: Gen-2 includes golang-
#      package.mk relatively (../../lang/golang/...); a standalone src-git
#      feed must anchor at the consumer's installed packages feed
#      ($(TOPDIR)/feeds/packages/...) — the single-line swap Gen-1's old
#      Makefile header documented,
#   4. records the source ref in net/tollgate-wrt/.canonical-source so a
#      stale mirror is visible at a glance.
#
# After running: review the diff, then bump PKG_* per the canonical
# recipe's own repin procedure (Gen-2's docs) — this script deliberately
# does NOT move the pin; publishing different bits from a feed is a
# release decision, not a sync side effect.
#
# Usage: scripts/sync-from-canonical.sh [ref]     # default master

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_ROOT/net/tollgate-wrt"
CANONICAL_REF="${1:-master}"

for dep in git; do
	command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: missing tool: $dep" >&2; exit 1; }
done
[ -d "$DEST" ] || { echo "ERROR: $DEST not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Fetching FreedomTechFeed/packages @ $CANONICAL_REF"
git clone -q --depth 1 -b "$CANONICAL_REF" \
	https://github.com/FreedomTechFeed/packages.git "$WORK/packages"

SRC="$WORK/packages/net/tollgate-wrt"
[ -f "$SRC/Makefile" ] || { echo "ERROR: no net/tollgate-wrt in the canonical ref" >&2; exit 1; }

echo "==> Copying the canonical recipe wholesale (fences included)"
rm -rf "$DEST"
cp -a "$SRC" "$DEST"

echo "==> Standalone-feed include swap (the ONE Gen-1/Gen-2 layout difference)"
sed -i \
	-e 's|^include \.\./\.\./lang/golang/golang-package\.mk|include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|' \
	"$DEST/Makefile"
grep -q 'feeds/packages/lang/golang/golang-package.mk' "$DEST/Makefile" || {
	echo "ERROR: include rewrite did not apply — the canonical include line changed;" >&2
	echo "       update this script's sed to match it." >&2
	exit 1
}

echo "==> Recording the mirror source"
git -C "$WORK/packages" rev-parse HEAD > "$DEST/.canonical-source"

echo
echo "Done. Review with: git -C \"$REPO_ROOT\" diff --stat"
echo "The canonical recipe's tests run here too — try:"
echo "  sh net/tollgate-wrt/test-build-contract.sh   # contract fence (TG_FEED_ROOT=<packages checkout>)"
