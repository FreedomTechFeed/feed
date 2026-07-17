# AGENTS.md — Freedom Tech OpenWrt Feed

Guidance for AI agents (and humans) working in this repo.

## What this repo is

An OpenWrt **`src-git` feed** with four independent packages:

| Package | Language | Build system | Source | Status |
|---|---|---|---|---|
| `tollgate-wrt` | Go | `golang-package.mk` | [OpenTollGate/tollgate-module-basic-go](https://github.com/OpenTollGate/tollgate-module-basic-go) | ready |
| `fips` | Rust | `rust-package.mk` | [jmcorgan/fips](https://github.com/jmcorgan/fips) | ready |
| `tollgate-rs` | Rust | `rust-package.mk` | [OpenTollGate/tollgate-rs](https://github.com/OpenTollGate/tollgate-rs) | wip |
| `mptcp-bonding` | shell | pure files (no compile) | [c03rad0r/tg-mptcp-server](https://github.com/c03rad0r/tg-mptcp-server) | ready |

Each package lives in its own `net/<name>/` directory and is built
independently. They are NOT bundled.

## Layout

```
net/tollgate-wrt/           # Go: Cashu-powered WiFi payment gateway
net/fips/                   # Rust: decentralized mesh networking daemon
net/tollgate-rs/            # Rust: Cashu metered access node
net/mptcp-bonding/          # shell: MPTCP multi-WAN bonding client
scripts/sync-from-upstream.sh
.github/workflows/validate-feed.yml
PLAN.md                     # design + checklist (keep the checklist current)
```

## Golden rules

1. **Never modify the upstream repo.** Each package downloads the source and
   builds it as-is. If something needs to change upstream, change it there, tag
   a release, then update `PKG_SOURCE_VERSION` / `PKG_HASH` here.
2. **Independent packages.** Each `net/<name>/` is standalone. Do not add
   cross-dependencies between feed packages unless they genuinely require each
   other at runtime.
3. **Use the right build framework:**
   - Go packages → `include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk`
   - Rust packages → `include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk`
   - Shell/file-only packages → `include $(INCLUDE_DIR)/package.mk` (no language helper)
4. **Upstream policy compliance** (enforced by CI): no `REPLACES`, no `luci`
   dependency, real `PKG_HASH` / `PKG_MIRROR_HASH` (never `skip`).
5. **`files/` are vendored**, not generated here. Update them only via
   `scripts/sync-from-upstream.sh <tag>` (tollgate-wrt) or manual sync.

## Package-specific notes

### tollgate-wrt (Go)

Two binaries in two separate Go modules. The service is the main module at
`src/`; the CLI is a self-contained module at `src/cmd/tollgate-cli/`. The
`Build/Compile` override builds both. Release: `scripts/sync-from-upstream.sh v0.5.1`.

### fips (Rust)

Single crate with four binaries (fips, fipsctl, fipstop, fips-gateway).
`rust-package.mk` handles cargo cross-compile. No release tags yet — pinned to
a commit hash. Update `PKG_SOURCE_VERSION` when bumping.

### tollgate-rs (Rust)

Workspace with three crates; the `tollgate` binary lives in the `tollgate-net`
member (`CARGO_PKG_NAME:=tollgate-net`). No release tags yet — pinned to a
commit hash. Protocol surface still evolving.

### mptcp-bonding (shell)

No compilation. Ships init script, sysctl config, UCI schema, and setup-bond
helper. Depends on `shadowsocks-libev-ss-redir`.

## Verification

- The `validate` job lints every `net/*/Makefile` and verifies referenced
  `files/` paths exist. Runs on every push/PR.
- The `go-smoke` job does a fast cross-compile of the Go package.
- The `build-sdk` job is the authoritative SDK compile gate for tollgate-wrt.
  Rust SDK builds will be added once `rust/host` is confirmed in the SDK image.

## Submitting upstream (future)

Each `net/<name>/` directory can be lifted individually into a PR to
`openwrt/packages`. Swap the language-helper include path:

```diff
-include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk
+include ../../lang/golang/golang-package.mk
```

Same pattern for `rust-package.mk`. See README and PLAN.md.
