# SPDX-License-Identifier: GPL-2.0-only
#
# fips — distributed, decentralized mesh networking daemon (Rust).
#
# Vendored as a src-link feed package. The upstream repo (jmcorgan/fips) is a
# single crate with four binaries: fips, fipsctl, fipstop, fips-gateway.
# rust-package.mk handles the cargo cross-compile (arch→triple map, .cargo
# linker config, CARGO_HOME scoping) — we only define the install layout.

include $(TOPDIR)/rules.mk

PKG_NAME:=fips
PKG_VERSION:=0.5.0~dev
PKG_RELEASE:=1

# Reproducibility: fips has no release tags yet, so we pin to a specific
# commit on master. Bump PKG_SOURCE_VERSION to a newer commit (or, once
# tagged, a tag) when upgrading.
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/jmcorgan/fips.git
PKG_SOURCE_VERSION:=30c5808
PKG_MIRROR_HASH:=d7982bca35c87891ee911f0d2292490d9a812ae7e1dd76cc0275c8ea02cd90a7

PKG_MAINTAINER:=FIPS Network
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

# rust-package.mk provides RUST_TARGET, Cargo/Compile, and Build/Compile.
# CARGO_PKG_NAME defaults to PKG_NAME (fips) — correct, since all four
# binaries (fips, fipsctl, fipstop, fips-gateway) live in the same crate.

define Package/fips
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=FIPS Mesh Network Daemon
  URL:=https://github.com/jmcorgan/fips
  DEPENDS:=+kmod-tun +kmod-br-netfilter +kmod-nft-nat \
	+kmod-nf-conntrack +ip-full
endef

define Package/fips/description
  FIPS is a distributed, decentralized mesh networking daemon. It routes
  traffic across nodes connected over UDP, TCP, or raw Ethernet (EtherType
  0x2121). Provides a TUN interface (fips0) with ULA IPv6 mesh addressing
  and a local DNS responder for .fips name resolution.

  Four binaries are installed:
    fips         — mesh daemon
    fipsctl      — CLI control and inspection tool
    fipstop      — live TUI dashboard (requires a terminal)
    fips-gateway — outbound LAN gateway (not started by default)
endef

define Package/fips/conffiles
/etc/fips/fips.yaml
endef

RUST_BIN_DIR:=$(PKG_BUILD_DIR)/target/$(RUST_TARGET)/release

define Package/fips/install
	# Binaries
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(RUST_BIN_DIR)/fips         $(1)/usr/bin/fips
	$(INSTALL_BIN) $(RUST_BIN_DIR)/fipsctl      $(1)/usr/bin/fipsctl
	$(INSTALL_BIN) $(RUST_BIN_DIR)/fipstop      $(1)/usr/bin/fipstop
	$(INSTALL_BIN) $(RUST_BIN_DIR)/fips-gateway $(1)/usr/bin/fips-gateway

	# procd init scripts
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/fips         $(1)/etc/init.d/fips
	$(INSTALL_BIN) ./files/etc/init.d/fips-gateway $(1)/etc/init.d/fips-gateway

	# Default config — installed as CONF so opkg will not overwrite it on upgrade
	$(INSTALL_DIR) $(1)/etc/fips
	$(INSTALL_CONF) ./files/etc/fips/fips.yaml $(1)/etc/fips/fips.yaml

	# Firewall helper script (called by UCI include and hotplug)
	$(INSTALL_BIN) ./files/etc/fips/firewall.sh $(1)/etc/fips/firewall.sh

	# dnsmasq drop-in: forward .fips queries to the FIPS DNS responder
	$(INSTALL_DIR) $(1)/etc/dnsmasq.d
	$(INSTALL_DATA) ./files/etc/dnsmasq.d/fips.conf $(1)/etc/dnsmasq.d/fips.conf

	# sysctl: enable br_netfilter so AF_PACKET sees frames on bridge member ports
	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_DATA) ./files/etc/sysctl.d/fips-bridge.conf $(1)/etc/sysctl.d/fips-bridge.conf
	$(INSTALL_DATA) ./files/etc/sysctl.d/fips-gateway.conf $(1)/etc/sysctl.d/fips-gateway.conf

	# Hotplug: apply firewall rules when the FIPS TUN interface comes up
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net
	$(INSTALL_BIN) ./files/etc/hotplug.d/net/99-fips $(1)/etc/hotplug.d/net/99-fips

	# UCI defaults: one-time first-boot firewall and module setup
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-fips-setup $(1)/etc/uci-defaults/90-fips-setup

	# sysupgrade: preserve /etc/fips/ (config + identity key) across firmware upgrades
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/fips $(1)/lib/upgrade/keep.d/fips
endef

$(eval $(call BuildPackage,fips))
