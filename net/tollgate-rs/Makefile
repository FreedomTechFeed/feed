# SPDX-License-Identifier: GPL-2.0-only
#
# tollgate-rs — Rust TollGate node: sells metered network access for Cashu.
#
# Vendored as a src-link feed package. The upstream repo (OpenTollGate/
# tollgate-rs) is a workspace; the `tollgate` binary lives in the
# tollgate-net crate. rust-package.mk handles the cargo cross-compile.

include $(TOPDIR)/rules.mk

PKG_NAME:=tollgate-rs
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

# Reproducibility: tollgate-rs has no release tags yet, so we pin to a
# specific commit. Bump PKG_SOURCE_VERSION to a newer commit (or, once
# tagged, a tag) when upgrading.
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/OpenTollGate/tollgate-rs.git
PKG_SOURCE_VERSION:=be5400f
PKG_MIRROR_HASH:=d1c59d546acdfdd54304a7a268481de45822267c7f494b32f4a72672d08f5f1f

PKG_MAINTAINER:=TollGate <tollgate@tollgate.me>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
# NOTE on the rust-package.mk include path:
#   As a standalone src-git feed, the rust helpers live in the consumer's
#   installed `packages` feed, so we anchor at $(TOPDIR)/feeds/packages/... .
#   When this directory is lifted into openwrt/packages as an upstream PR,
#   swap this single line for:
#     include ../../lang/rust/rust-package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

# The `tollgate` binary lives in the tollgate-net workspace member.
CARGO_PKG_NAME:=tollgate-net

define Package/tollgate-rs
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=TollGate-RS node (Cashu metered access)
  URL:=https://github.com/OpenTollGate/tollgate-rs
  DEPENDS:=+ca-bundle +ip-full
endef

define Package/tollgate-rs/description
  Rust TollGate node. Sells metered network access for Cashu micropayments:
  peers announce, pay a bootstrap token, and receive time/byte-metered access.

  First deployment target is plain-IP bootstrap-only mode (listen on
  127.0.0.1:4747 by default). FIPS mesh integration and Spilman channels are
  layered on later — the package ships the `tollgate` daemon and a procd
  init script that runs it against /etc/tollgate/tollgate.yaml.

  STATUS: work in progress — the protocol surface and config schema are still
  evolving. Expect breaking changes before the first tagged release.
endef

define Package/tollgate-rs/conffiles
/etc/tollgate/tollgate.yaml
/etc/config/tollgate-rs
endef

RUST_BIN_DIR:=$(PKG_BUILD_DIR)/target/$(RUST_TARGET)/release

define Package/tollgate-rs/install
	# Daemon binary
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(RUST_BIN_DIR)/tollgate $(1)/usr/bin/tollgate

	# procd init script
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/tollgate-rs $(1)/etc/init.d/tollgate-rs

	# Default config — installed as CONF so opkg/apk will not clobber it on upgrade
	$(INSTALL_DIR) $(1)/etc/tollgate
	$(INSTALL_CONF) ./files/etc/tollgate/tollgate.yaml $(1)/etc/tollgate/tollgate.yaml

	# UCI config: listen address / enabled flag
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/etc/config/tollgate-rs $(1)/etc/config/tollgate-rs

	# sysupgrade: preserve /etc/tollgate/ across firmware upgrades
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/tollgate-rs $(1)/lib/upgrade/keep.d/tollgate-rs
endef

$(eval $(call BuildPackage,tollgate-rs))
