# AGENTS.md — Freedom Tech Feed

Instructions for AI coding agents working in this repository.

## What This Is

A custom OpenWrt package feed (`opkg`/`apk` repository) that collects
freedom-tech software: TollGate, FIPS, TollGate-RS, and MPTCP bonding.

## Repository Layout

```
feed/
├── README.md                  # User-facing feed documentation
├── FEED-MANIFEST.conf         # Package list (name | source | status)
├── scripts/
│   ├── generate-packages-index.sh  # opkg Packages.gz generator (per arch)
│   ├── generate-apk-index.sh       # apk APKINDEX.tar.gz generator (per arch)
│   └── index-feed.sh               # orchestrator: group by arch, run both
├── docs/
│   └── feed-strategy.md       # Architecture decision: hybrid custom repo
└── .github/workflows/
    └── build-feed.yml         # CI: auto-generate indices on every release
```

## Key Decisions

1. **Hybrid Custom Repository** — package indices hosted at
   `releases.tollgate.me`, NOT merged into upstream OpenWrt feeds.
2. **Both package formats** — `opkg` (.ipk, OpenWrt ≤24.x) and `apk`
   (.apk, OpenWrt 25.x+) supported via separate index generators.
3. **All architectures** — the feed targets every OpenWrt-supported arch,
   not just specific routers.

## Scripts

The index generation scripts are tested and in production use. They were
originally developed for the net4sats-mvp project and migrated here.

```sh
# Generate opkg index from a directory of .ipk files
scripts/generate-packages-index.sh /path/to/artifacts/

# Generate apk index from a directory of .apk files
scripts/generate-apk-index.sh /path/to/artifacts/

# Orchestrate both, for a mixed directory of .ipk/.apk across architectures:
# detects each file's arch from its embedded metadata, groups by arch, and runs
# the matching generator(s) per arch, emitting <out>/<arch>/{Packages.gz,APKINDEX.tar.gz}.
scripts/index-feed.sh /path/to/artifacts/ /path/to/feed-output/
```

CI (`.github/workflows/build-feed.yml`) calls `index-feed.sh` automatically on
every release: it downloads the release's `.ipk`/`.apk` assets, indexes every
architecture present, and publishes the feed tree to the GitHub Release and to
the `gh-pages` branch.

## Contributing

- One logical change per PR, targeting `main`.
- Test index generation scripts before pushing.
- No coding-assistant attribution in commits.
