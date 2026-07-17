# Freedom Tech OpenWrt Feed

An OpenWrt package feed with four independent packages:

| Package | Language | What it does |
|---|---|---|
| **tollgate-wrt** | Go | Cashu-powered WiFi payment gateway |
| **fips** | Rust | Decentralized mesh networking daemon |
| **tollgate-rs** | Rust | Cashu metered network access node |
| **mptcp-bonding** | shell | MPTCP multi-WAN bonding client |

Each package lives in its own `net/<name>/` directory and builds independently.
Go packages use `golang-package.mk`; Rust packages use `rust-package.mk`;
shell-only packages have no language helper.

## Why a separate feed repo

An earlier attempt ([upstream PR #125](https://github.com/OpenTollGate/tollgate-module-basic-go/pull/125))
tried to restructure upstream's Go source (`src/` → repo root) to satisfy
`golang-package.mk`. That touched ~120 files and could not be rebased.
`golang-package.mk` accepts `GO_PKG` pointing at a subdirectory, so **no
upstream restructure is needed**. Keeping the feed glue in this separate repo
means:

- zero rebase collisions with upstream development, forever;
- the package is usable as a `src-git` feed *today*;
- the `net/tollgate-wrt/` directory lifts cleanly into a future PR against
  [`openwrt/packages`](https://github.com/openwrt/packages) as a small,
  reviewable addition.

## Packages

### tollgate-wrt (Go)

Cashu-powered WiFi payment gateway. Builds two binaries (`tollgate-wrt`
service + `tollgate` CLI) from the upstream source tarball via
`golang-package.mk`. Depends on `nodogsplash` and `jq`.

### fips (Rust)

Distributed, decentralized mesh networking daemon. Four binaries: `fips`
(daemon), `fipsctl` (CLI), `fipstop` (TUI), `fips-gateway` (LAN gateway).
Built via `rust-package.mk`. Depends on `kmod-tun`, `kmod-nft-nat`.

### tollgate-rs (Rust)

Rust TollGate node — sells metered network access for Cashu micropayments.
One binary (`tollgate`). Built via `rust-package.mk` from the `tollgate-net`
workspace member. Work in progress — protocol surface still evolving.

### mptcp-bonding (shell)

MPTCP multi-WAN bonding client. Ships sysctl config, procd init, UCI schema,
and a setup-bond helper. No compilation. Depends on `shadowsocks-libev-ss-redir`.

## Using the feed

Add it to an OpenWrt build:

```sh
echo "src-git tollgate https://github.com/FreedomTechFeed/feed.git" >> feeds.conf
./scripts/feeds update tollgate
./scripts/feeds install tollgate-wrt fips tollgate-rs mptcp-bonding
```

Then enable packages in `make menuconfig` under **Network**, and build.

> Go packages depend on `nodogsplash` and `jq`; Rust packages depend on the
> `rust/host` toolchain; `mptcp-bonding` depends on `shadowsocks-libev-ss-redir`.
> All come from the standard `packages` feed — keep it enabled. The language
> helpers (`golang-package.mk`, `rust-package.mk`) also come from there.

## How it builds two binaries in one package

The upstream source has **two Go modules**:

- the service, the main module at `src/` (`github.com/OpenTollGate/tollgate-module-basic-go`),
- the CLI, a self-contained module at `src/cmd/tollgate-cli/` (`module tollgate-cli`).

`golang-package.mk` builds one module per Makefile. The `Makefile` overrides
`Build/Compile` to: (1) build the service through the framework helper, then
(2) build the CLI manually from its own module dir, reusing the framework's
exported cross-compile environment. One package, both binaries —
`/usr/bin/tollgate-wrt` and `/usr/bin/tollgate`.

## Syncing a new upstream release

```sh
scripts/sync-from-upstream.sh v0.5.1
```

This downloads the tarball for the given tag, recomputes `PKG_HASH`, sets
`PKG_VERSION`, and re-vendors `packaging/files/` into `net/tollgate-wrt/files/`.
Review the diff (the captive-portal-site assets change every release — that's
expected) and commit.

## Validation

`.github/workflows/validate-feed.yml` runs three jobs:

1. **validate** — Makefile lint (fields present, no `REPLACES`), `PKG_HASH`
   verified against the live tarball, every referenced `files/` path exists.
2. **go-smoke** — fast `go build` of both modules for amd64/arm64/mipsle
   (no SDK, catches source breakage quickly).
3. **build-sdk** — the authoritative proof: a real OpenWrt SDK compile of the
   package via `golang-package.mk`, including the nested CLI-module build.

The SDK job is the gate before submitting upstream. See [`PLAN.md`](PLAN.md)
for the full design and the highest-risk item.

## Submitting to `openwrt/packages` (future)

When each package is green in CI, its `net/<name>/` directory can be lifted
individually into a PR against `openwrt/packages`. The only change required
is the language-helper include path:

```diff
-include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk
+include ../../lang/golang/golang-package.mk
```

Follow the
[`openwrt/packages` contributing guide](https://github.com/openwrt/packages/blob/master/CONTRIBUTING.md)
(Signed-off-by, commit-message format) when opening that PR.

## License

`GPL-3.0-only` — matches upstream. The built `tollgate-wrt` package ships
upstream's `LICENSE`.
