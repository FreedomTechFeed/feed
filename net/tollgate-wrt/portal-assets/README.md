# portal-assets/

The compiled captive-portal single-page app, as installed on the router at
`/etc/tollgate/tollgate-captive-portal-site/assets/`.

## Why these files are vendored here and not in `files/`

Upstream builds the portal with `npm` from a **separate repository**
(`OpenTollGate/tollgate-captive-portal-site`) in its own CI job
(`.github/workflows/build-package.yml`, `build-portal`), uploads the result as
the `portal-assets` artifact, and downloads it into
`packaging/files/tollgate-captive-portal-site/` right before packaging.

`net/tollgate-wrt/files/` in this repo is a **byte-for-byte** copy of the
pinned tag's `packaging/files/` — that is a deliberate property, checked by
`scripts/check-version-strings.sh --hash`, because it keeps the directory
identical to what an upstream submission would carry. The portal bundles are
therefore kept separately and overlaid at install time by
`Package/tollgate-wrt/install`.

An OpenWrt build cannot reproduce them: the SDK has no npm, and the package
build is not allowed to reach out to a second repository.

## Provenance of the current bundles

The eight files in `assets/` are exactly the bundles named by the pinned
release's own
`files/tollgate-captive-portal-site/asset-manifest.json`
(`assets/portal-BQ7wV0jU.js`, `assets/index-DxBkINUB.js`,
`assets/index-D9l7TVHN.css`, …). The filenames are Vite content hashes, and the
same names are referenced from the tag's `splash.html`, so a name match is the
release's own assertion that these are the bundles it expects.

`scripts/sync-from-upstream.sh` re-checks that on every re-pin and prints a
warning when a new release's manifest asks for different bundles.

**Not proven here:** that these bytes are the output of a fresh build of
`tollgate-captive-portal-site` at the revision upstream happened to use — that
revision is not pinned anywhere upstream (its CI builds `main`). Neither the
bundles nor the portal have been exercised on router hardware.

## Replacing them

```sh
git clone https://github.com/OpenTollGate/tollgate-captive-portal-site
cd tollgate-captive-portal-site && npm ci && npm run build
cp -a build/assets/. <this-dir>/assets/
```

Record the portal commit you built from in the commit message; upstream does
not pin one.
