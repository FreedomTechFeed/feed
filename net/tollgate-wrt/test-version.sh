#!/bin/sh
#
# SPDX-License-Identifier: GPL-3.0-only
#
# shellcheck shell=busybox
#
# Version check for the openwrt/packages CI harness. The generic check runs
# every installed executable with --version / -version / version / -v / -V /
# --help / -help / -? and greps the output for $PKG_VERSION. Neither of this
# package's binaries can satisfy that:
#
#   * tollgate-wrt has no flag parser at all - it ignores its arguments and
#     starts the service, so the generic probe hangs until the harness kills
#     it and never prints a version;
#   * tollgate is a socket client - `--version` exits 1 with "unknown flag:
#     --version" (the cobra root command has no Version field), and
#     `tollgate version` needs the running service's Unix socket.
#
# Both behaviours were captured against the release tarball this package is
# built from (see the feed README). The version *is* compiled into the binary:
# the Makefile injects the same ldflags symbol upstream's own CI uses, and the
# running service reports it over its socket API. Assert it directly in the
# compiled binary instead - `strings` is one of the harness' TEST_PACKAGES.
#
case "$PKG_NAME" in
tollgate-wrt)
	# PKG_VERSION is normalised for the package manager (0.6.0_alpha1 on apk,
	# 0.6.0~alpha1 on opkg); the value injected into the binary is the
	# upstream tag form, v0.6.0-alpha1.
	want="v$(echo "$PKG_VERSION" | tr '_~' '-')"
	strings /usr/bin/tollgate-wrt | grep -F -- "$want"
	;;
*)
	echo "Untested package: $PKG_NAME" >&2
	exit 1
	;;
esac
