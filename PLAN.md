# Plan — OpenWrt feed for `tollgate-module-basic-go`

## Goal

Turn this repo into a clean OpenWrt **`src-git` feed** that builds the
`tollgate-wrt` package from upstream source via `golang-package.mk`, so that:

1. It is usable **today** by firmware builders (`feeds.conf` → this repo).
2. It lifts cleanly into a future PR against [`openwrt/packages`](https://github.com/openwrt/packages),
   achieving the upstream merge that PR [#125](https://github.com/OpenTollGate/tollgate-module-basic-go/pull/125)
   was pursuing.

## Why this approach (lessons from PR #125)

PR #125 tried to restructure upstream's Go source from `src/` → repo root.
That touched ~120 files, conflicted with 14 subsequent merges to `main`, and
was un-reviewable. c03rad0r's June-8 rescue proved the right idea:
**`golang-package.mk` accepts `GO_PKG` pointing at a subdirectory** — no
upstream restructure needed.

By putting the feed glue in **this separate repo**:

- The upstream repo (`tollgate-module-basic-go`) stays **100% untouched** →
  zero rebase collisions forever.
- The eventual `openwrt/packages` PR is a small, reviewable addition of
  `net/tollgate-wrt/{Makefile,files}` — no source shuffle.

## Design

- **One package, two binaries.** A single `Package/tollgate-wrt` installs both
  `/usr/bin/tollgate-wrt` (the service) and `/usr/bin/tollgate` (the CLI). They
  are one functional unit, so there is no dependency-direction problem.
- **Two Go modules, one Makefile.** The service lives in the upstream module
  `github.com/OpenTollGate/tollgate-module-basic-go` (go.mod at `src/`); the CLI
  is a self-contained separate module at `src/cmd/tollgate-cli/`. We override
  `Build/Compile` to: (1) run the default `golang-package.mk` build for the
  service, then (2) a manual `go build` of the CLI from its own module dir,
  reusing the framework's exported cross-compile/toolchain env.
- **Source fetched, not vendored.** `PKG_SOURCE_URL` downloads the upstream
  `v0.5.0` tarball; `PKG_HASH` pins it. `PKG_BUILD_DIR` points at the tarball's
  `src/` so `golang-package.mk` operates on the module root.
- **Runtime `files/` ARE vendored** here (init.d, uci-defaults, captive-portal
  site, hotplug, keep.d) — copied from upstream `packaging/files/` via
  `scripts/sync-from-upstream.sh` and re-synced per release.
- **Upstream policy compliance** (enforced by CI): no `REPLACES`, no `luci`
  dependency, `GPL-3.0-only`, real `PKG_HASH`.

### Layout

```
feed/
├── net/tollgate-wrt/
│   ├── Makefile          # single package; builds service + CLI
│   └── files/            # vendored from upstream packaging/files/
├── scripts/
│   └── sync-from-upstream.sh   # re-vendor files/ + recompute PKG_HASH for a tag
├── .github/workflows/
│   └── validate-feed.yml # lint + PKG_HASH verify + OpenWrt SDK build
├── README.md
├── AGENTS.md
└── PLAN.md               # this file
```

### golang-package.mk include path

- **Standalone feed (this repo):**
  `include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk`
- **When lifted into `openwrt/packages` (future PR):** change that single line to
  `include ../../lang/golang/golang-package.mk`

This one-liner swap is the only feed-vs-upstream difference.

### Key Makefile fields

```makefile
PKG_NAME:=tollgate-wrt
PKG_VERSION:=0.5.0
PKG_RELEASE:=1
PKG_SOURCE:=tollgate-module-basic-go-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/OpenTollGate/tollgate-module-basic-go/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=<sha256>
PKG_BUILD_DIR:=$(BUILD_DIR)/tollgate-module-basic-go-$(PKG_VERSION)/src
GO_PKG:=github.com/OpenTollGate/tollgate-module-basic-go
GO_PKG_BUILD_PKG:=$(GO_PKG)
DEPENDS:=+nodogsplash +jq $(GO_ARCH_DEPENDS)
```

## Highest-risk item (gated by CI)

PR #125 never finished proving that `golang-package.mk` works when the module's
`go.mod` lives in a tarball **subdirectory** (`src/`) — plus our extra nested
CLI-module build. The `validate-feed.yml` **OpenWrt SDK build job** is the gate
that proves both compile before any upstream submission.

## Testing pipeline (CI)

`.github/workflows/validate-feed.yml` *is* the testing pipeline. Three jobs:

| Job | Purpose | When it runs |
|---|---|---|
| `validate` | Makefile field lint (no `REPLACES`), `PKG_HASH` vs the live tarball, every referenced `files/` path exists | every push/PR |
| `go-smoke` | plain `go build` of both Go modules for amd64/arm64/mipsle | every push/PR |
| `build-sdk` | authoritative OpenWrt SDK compile via `golang-package.mk` | main pushes, PRs, tags, weekly, manual dispatch |

`build-sdk` builds a **3-target matrix** so the real TollGate hardware arches
are proven, not just x86-64:

- `x86-64` — host-runnable (amd64)
- `mediatek-filogic` — GL-MT6000 (`aarch64_cortex-a53`)
- `ramips-mt7621` — GL-MT3000 (`mipsel_24kc`)

Each SDK job **uploads** the built `.ipk`/`.apk` as a workflow artifact
(`tollgate-wrt-<target>`) so it can be downloaded for on-router testing
without a local rebuild.

Binary runtime smoke (qemu) is intentionally **not** included, to keep the
pipeline simple. The maintainer-facing proof is the SDK compile itself; runtime
validation happens on real hardware with the uploaded artifacts.

Cost: each `build-sdk` job is slow (~30–60 min, it bootstraps the Go toolchain).
The 3-target matrix runs on main pushes / PRs / tags, so expect ~3× that in CI
minutes on those events (the jobs run in parallel).

SDK image contract (gotcha): since OpenWrt 24.10 the snapshot SDK images
(`-master`/`-SNAPSHOT`) ship an **empty `/builder` plus a `setup.sh`** — the
job must run `./setup.sh` (download + extract the SDK) before feeds/make work.
The job also runs `feeds install -a` (not just `tollgate-wrt`) so the
`golang/host` toolchain and `nodogsplash`/`jq` from the `packages` feed are
available.

## Checklist

- [x] Write `PLAN.md` (this document)
- [x] Wipe unneeded current repo contents
      (`FEED-MANIFEST.conf`, `docs/`, `scripts/generate-*-index.sh`, old workflow)
- [x] Vendor `files/` from upstream `v0.5.0` and pin `PKG_HASH`
- [x] Write `net/tollgate-wrt/Makefile` (single package, both binaries)
- [x] Write `scripts/sync-from-upstream.sh` (idempotent, `shellcheck` clean)
- [x] Write `.github/workflows/validate-feed.yml` (validate + go-smoke + build-sdk)
- [x] Enhance `build-sdk`: run on main pushes, 3-arch matrix (x86-64 +
      mediatek-filogic + ramips-mt7621), upload package artifacts
      (smoke test intentionally omitted to keep it simple)
- [x] Rewrite `README.md` and `AGENTS.md`
- [x] Verify: Makefile lint, hash check, referenced-paths check, `shellcheck`
- [ ] _(future)_ First green `build-sdk` run across all 3 arches
- [ ] _(future)_ Lift `net/tollgate-wrt/` into a PR to `openwrt/packages`
      (swap the `golang-package.mk` include path)

## Phase 4: Expand feed (fips, tollgate-rs, mptcp-bonding)

Added three more independent packages alongside `tollgate-wrt`:

| Package | Dir | Build system | Source |
|---|---|---|---|
| `fips` | `net/fips/` | `rust-package.mk` | jmcorgan/fips (pinned commit 30c5808) |
| `tollgate-rs` | `net/tollgate-rs/` | `rust-package.mk` | OpenTollGate/tollgate-rs (pinned commit be5400f) |
| `mptcp-bonding` | `net/mptcp-bonding/` | pure files | c03rad0r/tg-mptcp-server |

Each package has its own `net/<name>/` directory — no bundling.

### rust-package.mk include path

Same pattern as golang-package.mk:

- **Standalone feed:** `include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk`
- **In openwrt/packages:** `include ../../lang/rust/rust-package.mk`

### CI extensions

- `validate` job: generalized to lint ALL `net/*/Makefile` files (not just
  tollgate-wrt). Checks common fields + language-specific fields + referenced
  `files/` paths.
- Added `rust-smoke` job: cross-compiles fips and tollgate-rs for
  `x86_64-unknown-linux-musl` outside the SDK. Non-blocking initially
  (`continue-on-error`) since C-dep crates may need SDK cross-headers.
- `build-sdk` job: still only tollgate-wrt. Rust SDK builds to be added once
  `rust/host` is confirmed in the SDK image.

### Phase 4 checklist

- [x] Port fips to `net/fips/` with `rust-package.mk`
- [x] Port tollgate-rs to `net/tollgate-rs/` with `rust-package.mk`
- [x] Port mptcp-bonding to `net/mptcp-bonding/`
- [x] Update AGENTS.md, README.md
- [x] Generalize validate-feed.yml CI for all packages
- [x] Add rust-smoke CI job
- [ ] _(future)_ First green Rust SDK build
- [ ] _(future)_ Lift Rust packages into `openwrt/packages` PRs
