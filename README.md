# Freedom Tech Feed

A custom OpenWrt package feed for freedom-tech software.

## Packages

| Package | Description | Source |
|---------|-------------|--------|
| `tollgate-wrt` | Cashu-powered payment gateway for internet access | [OpenTollGate/tollgate-module-basic-go](https://github.com/OpenTollGate/tollgate-module-basic-go) |
| `fips` | Freedom Infrastructure Protocol Stack — mesh networking | [OpenTollGate/fips](https://github.com/OpenTollGate/fips) |
| `tollgate-rs` | TollGate Rust implementation | [OpenTollGate/tollgate-rs](https://github.com/OpenTollGate/tollgate-rs) |
| `mptcp-bonding` | Multi-WAN MPTCP bonding client for TollGate routers | [c03rad0r/tg-mptcp-server](https://github.com/c03rad0r/tg-mptcp-server) |

## Using the Feed

### OpenWrt 24.x (opkg)

```sh
echo "src/gz freedomtech https://releases.tollgate.me/feed/<arch>/Packages.gz" \
  >> /etc/opkg/customfeeds.conf
opkg update
opkg install tollgate-wrt
```

### OpenWrt 25.x (apk)

```sh
echo "https://releases.tollgate.me/feed/<arch>" \
  > /etc/apk/repositories.d/freedomtech.list
apk update
apk add tollgate-wrt
```

Replace `<arch>` with your router's architecture (e.g., `aarch64_cortex-a53`, `mipsel_24kc`).

## Feed Index Generation

The feed indices (Packages.gz, APKINDEX.tar.gz) are generated from built
`.ipk`/`.apk` artifacts by two scripts:

```sh
scripts/generate-packages-index.sh <artifact-dir>   # opkg Packages.gz
scripts/generate-apk-index.sh <artifact-dir>         # apk APKINDEX.tar.gz
```

These scripts are tested and currently in production use for TollGate releases
at `releases.tollgate.me`.

## Adding a Package to the Feed

1. Ensure the package has an OpenWrt Makefile with proper `Package` definition
2. Build the `.ipk`/`.apk` via OpenWrt SDK or CI
3. Place the artifact in the architecture directory
4. Run the index generation scripts
5. Upload to the feed hosting location

## Architecture

The feed targets all OpenWrt-supported architectures. Primary test targets:

- `aarch64_cortex-a53` (GL-MT6000)
- `mipsel_24kc` (GL-MT3000)

## Related

- [TollGate Project](https://github.com/OpenTollGate)
- [TollGate Release Manager](https://releases.tollgate.me)
- [net4sats](https://net4sats.cash)
- [OpenWrt SDK Documentation](https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk)

## License

The feed infrastructure scripts are MIT licensed. Each package retains its
own license — see the source repositories.
