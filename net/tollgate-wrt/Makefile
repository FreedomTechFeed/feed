#
# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 TollGate <tollgate@tollgate.me>
#
# tollgate-wrt - Cashu-powered WiFi payment gateway for OpenWrt.
#
# Source-built from the upstream release tarball with OpenWrt's
# golang-package.mk. Upstream is NOT modified and NOT restructured: its Go
# service module lives in src/ inside the release tarball, and
# golang-package.mk only enables Go module mode when $PKG_BUILD_DIR/go.mod
# exists (lang/golang/golang-build.sh:100). PKG_BUILD_DIR therefore points at
# that src/ subdirectory, which also makes the src/*.go `replace` directives
# resolve against their sibling directories in the extracted tree.
# Upstream PR #125 tried to move src/ to the repository root instead and could
# not be rebased; this layout exists precisely so that never has to happen.
#
# One package, two binaries:
#   /usr/bin/tollgate-wrt   the service (module root main package, src/main.go)
#   /usr/bin/tollgate       the CLI   (a SEPARATE module, src/cmd/tollgate-cli)
#
# The CLI is its own Go module (`module tollgate-cli`) with no `replace` back
# into the service module, so no GO_PKG_BUILD_PKG value can reach it: `go
# install` cannot cross a module boundary. Build/Compile therefore builds the
# service through the framework helper and then builds the CLI from its own
# module directory with the framework's exported cross-compile environment.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=tollgate-wrt

#
# Version identity - two spellings of the SAME upstream release.
#
# PKG_SOURCE_VERSION is the body of the upstream release tag: v0.6.0-alpha1
#                      -> 0.6.0-alpha1
# PKG_VERSION        is that version written for the package manager:
#   apk (OpenWrt >= 25.12)  -> 0.6.0_alpha1
#   opkg (OpenWrt <= 24.10) -> 0.6.0~alpha1
#
# Why they differ (both spellings are proven with the real tools, see README):
#   * apk's version grammar is digit{.digit}*[_suffix#]*[-r#]; a '-' is legal
#     only as the literal -r<digits> revision. `0.6.0-alpha1-r1` is therefore
#     TOKEN_INVALID and the package would not install at all. The pre-release
#     marker must be `_alpha1`.
#   * opkg splits the version at the LAST hyphen and ranks `_alpha1` ABOVE the
#     bare release, so the apk spelling would make the alpha look newer than
#     0.6.0 forever. opkg's own pre-release marker is `~alpha1`.
# Never write -rN into PKG_VERSION: PKG_RELEASE owns the revision and resets
# to 1 on every version bump.
#
PKG_SOURCE_VERSION:=0.6.0-alpha1
PKG_SOURCE_COMMIT:=414650310b829ae6715fcffbc473e62a25655ed6

ifeq ($(CONFIG_USE_APK),y)
PKG_VERSION:=0.6.0_alpha1
else
PKG_VERSION:=0.6.0~alpha1
endif
PKG_RELEASE:=1

#
# Immutable source pin: the release tarball for the tag above, by sha256.
# Mutable archives, "latest" and branch heads are not acceptable sources for
# an OpenWrt package (upstream contribution rules).
#
PKG_SOURCE:=tollgate-module-basic-go-$(PKG_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/OpenTollGate/tollgate-module-basic-go/tar.gz/v$(PKG_SOURCE_VERSION)?
PKG_HASH:=c0ca1b37cbccde8e46de8e42287185d322c648bb10ad317b3e496a136a0e35f7

PKG_MAINTAINER:=TollGate <tollgate@tollgate.me>
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

# The release tarball keeps the Go service module in src/, so the module root
# (and therefore the go.mod golang-package.mk looks for) is that subdirectory.
PKG_BUILD_DIR:=$(BUILD_DIR)/tollgate-module-basic-go-$(PKG_SOURCE_VERSION)/src

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/OpenTollGate/tollgate-module-basic-go
# Build the module-root main package (src/main.go). Its go.mod pulls in every
# sub-module through the replace graph.
GO_PKG_BUILD_PKG:=$(GO_PKG)

#
# Version injection. src/cli is a separate sub-module whose import path keeps
# the /src segment - the same symbol upstream's own CI sets:
#   -X .../src/cli.Version=<tag>
# The service links src/cli (it builds the Unix-socket CLI server from it), so
# this value is what the running service reports through its `version` API.
# The CLI binary does NOT link src/cli, so the CLI module build below receives
# the flag as a harmless no-op; see test-version.sh for how the package's
# version is asserted in CI.
#
GO_PKG_LDFLAGS_X:= \
	$(GO_PKG)/src/cli.Version=v$(PKG_SOURCE_VERSION) \
	$(GO_PKG)/src/cli.GitCommit=$(PKG_SOURCE_COMMIT) \
	$(GO_PKG)/src/cli.BuildTime=$(SOURCE_DATE_EPOCH)

# NOTE on the golang-package.mk include path:
#   As a standalone src-git feed the golang helpers live in the consumer's
#   installed `packages` feed, so we anchor at $(TOPDIR)/feeds/packages/... .
#   When this directory is lifted into openwrt/packages (or into a fork of it)
#   this single line becomes:
#     include ../../lang/golang/golang-package.mk
#   Nothing else in this directory changes.
include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/tollgate-wrt
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=Captive Portals
	TITLE:=TollGate - Cashu-powered WiFi Payment Gateway
	URL:=https://tollgate.me
	DEPENDS:=+nodogsplash +jq $(GO_ARCH_DEPENDS)
endef

define Package/tollgate-wrt/description
	TollGate turns an OpenWrt router into a Cashu-powered payment gateway
	for internet access. Customers pay in sats (time- or data-based); the
	router gates network access via NoDogSplash and sweeps balances to
	configured Lightning addresses.
endef

# Config that must survive an upgrade. The service creates these on first run;
# /etc/tollgate as a whole is also listed in files/lib/upgrade/keep.d/tollgate
# so sysupgrade keeps it.
define Package/tollgate-wrt/conffiles
/etc/tollgate/config.json
/etc/tollgate/identities.json
/etc/tollgate/install.json
endef

#
# Extraction + layout diagnostic. Upstream's go.mod lives in a tarball
# subdirectory (src/), and golang-package.mk expects go.mod at PKG_BUILD_DIR,
# so extract to $(BUILD_DIR) (the parent) and verify the module root landed
# where PKG_BUILD_DIR points - a failure here is otherwise reported much later
# as a confusing golang-build.sh error.
#
# NOTE: use `-xf <file>` explicitly, NOT $(TAR_OPTIONS). OpenWrt defines
# TAR_OPTIONS:=-xf -` (read the archive from stdin), which only works when the
# archive is piped in; here it is a downloaded file in $(DL_DIR).
#
define Build/Prepare
	mkdir -p $(BUILD_DIR)
	$(TAR) -C $(BUILD_DIR) -xf $(DL_DIR)/$(PKG_SOURCE)
	$(Build/Patch)
	@echo "=== PKG_BUILD_DIR = $(PKG_BUILD_DIR) ==="
	@ls -la $(PKG_BUILD_DIR)
	@test -f $(PKG_BUILD_DIR)/go.mod && echo "go.mod: OK" || { echo "go.mod: MISSING at $(PKG_BUILD_DIR)"; exit 1; }
endef

#
# Build both binaries: the service through the framework helper, then the CLI
# from its own module directory. Make runs each recipe line in a separate
# shell, so the cross-compile environment GO_PKG_VARS set up for the service
# does not carry over - we re-establish it explicitly (it adds `go` to PATH and
# exports GOOS/GOARCH/GOARM/GOMIPS/CGO_ENABLED/CC/GOCACHE/GOMODCACHE).
#
define Build/Compile
	$(call GoPackage/Build/Compile)
	cd $(PKG_BUILD_DIR)/cmd/tollgate-cli && \
		$(GO_PKG_VARS) go build -trimpath \
			-ldflags "$(GO_PKG_LDFLAGS_X:%=-X %)" \
			-o $(GO_PKG_BUILD_BIN_DIR)/tollgate-cli .
endef

define Package/tollgate-wrt/preinst
#!/bin/sh

[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

# Record the install timestamp so the captive portal / wizard can show it.
if [ -f /etc/tollgate/install.json ]; then
	CURRENT_TIMESTAMP=$$(date +%s)
	if ! jq ".install_time = $$CURRENT_TIMESTAMP" /etc/tollgate/install.json > /tmp/install.json.tmp; then
		echo "Error: Failed to update install_time using jq" >&2
		exit 1
	fi
	if ! mv /tmp/install.json.tmp /etc/tollgate/install.json; then
		echo "Error: Failed to move temporary file to /etc/tollgate/install.json" >&2
		exit 1
	fi
else
	mkdir -p /etc/tollgate
	CURRENT_TIMESTAMP=$$(date +%s)
	if ! echo "{\"install_time\": $$CURRENT_TIMESTAMP}" > /etc/tollgate/install.json; then
		echo "Error: Failed to create /etc/tollgate/install.json" >&2
		exit 1
	fi
fi

exit 0
endef

define Package/tollgate-wrt/postinst
#!/bin/sh

[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

# Run the oneshot UCI defaults immediately so an install on a running router
# takes effect without waiting for the next boot, then enable the service.
for script in /etc/uci-defaults/90-tollgate-captive-portal-symlink \
              /etc/uci-defaults/99-tollgate-setup; do
	if [ -x "$$script" ]; then
		"$$script" || echo "Warning: $$script exited with code $$?" >&2
	fi
done

if [ -x /etc/init.d/tollgate-wrt ]; then
	/etc/init.d/tollgate-wrt enable 2>/dev/null || true
fi

exit 0
endef

# Runtime files come from ./files/ (a verbatim copy of the pinned tag's
# packaging/files/, re-synced by scripts/sync-from-upstream.sh) plus
# ./portal-assets/, which upstream injects from its own CI artifact because the
# captive-portal SPA is built with npm from a separate repository - OpenWrt's
# build system has no npm and no way to reach that repository.
define Package/tollgate-wrt/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/tollgate-module-basic-go $(1)/usr/bin/tollgate-wrt
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/tollgate-cli $(1)/usr/bin/tollgate

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/tollgate-wrt $(1)/etc/init.d/

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-tollgate-captive-portal-symlink $(1)/etc/uci-defaults/
	# 99-tollgate-setup carries the release version. Upstream substitutes the
	# __TOLLGATE_VERSION__ placeholder when it stages this file (the literal
	# that used to sit here, v0.6.2, never matched a release tag); we do the
	# same substitution so the setup-version marker tracks the package. On a
	# tarball that predates the placeholder this is a byte-for-byte no-op.
	sed 's|__TOLLGATE_VERSION__|v$(PKG_SOURCE_VERSION)|g' \
		./files/etc/uci-defaults/99-tollgate-setup > $(1)/etc/uci-defaults/99-tollgate-setup
	chmod 0755 $(1)/etc/uci-defaults/99-tollgate-setup

	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/95-tollgate-restart $(1)/etc/hotplug.d/iface/

	$(INSTALL_DIR) $(1)/etc/nftables.d
	$(INSTALL_DATA) ./files/etc/nftables.d/20-nds-enforce.nft $(1)/etc/nftables.d/
	$(INSTALL_DATA) ./files/etc/nftables.d/30-backend-firewall.nft $(1)/etc/nftables.d/

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/check_package_path $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/bin/tollgate-apply-ssl $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/bin/tollgate-remove-ssl $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/usr/local/bin
	$(INSTALL_BIN) ./files/usr/local/bin/first-login-setup $(1)/usr/local/bin/

	$(INSTALL_DIR) $(1)/usr/share/man/man8
	$(INSTALL_DATA) ./files/man/man8/*.8 $(1)/usr/share/man/man8/

	$(INSTALL_DIR) $(1)/etc/tollgate/ecash
	$(INSTALL_DIR) $(1)/etc/crontabs

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/tollgate $(1)/lib/upgrade/keep.d/

	$(INSTALL_DIR) $(1)/etc/tollgate/tollgate-captive-portal-site
	$(CP) ./files/tollgate-captive-portal-site/. $(1)/etc/tollgate/tollgate-captive-portal-site/
	$(CP) ./portal-assets/assets $(1)/etc/tollgate/tollgate-captive-portal-site/
endef

$(eval $(call BuildPackage,tollgate-wrt))
