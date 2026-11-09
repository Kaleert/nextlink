# GitHub Actions — Android Original + Shadow

`push` and PR on `main` run analysis/tests and Original debug build. Pushing an Android version tag (`v1.0.0-beta+4`) triggers both signed **ARM64** APKs and publishes a prerelease. Manual `workflow_dispatch` builds both by default and can skip Shadow.

## Public core sources

- sing-box and AmneziaWG: `Kaleert/nextlink-cores` release `cores-v1`. Both are validated with the corresponding JSON manifest (`SHA-256` and `size`).
- Xray: official pinned release `v26.10.31`, ARM64 Android ZIP. The script prints its SHA-256; set the `NEXTLINK_XRAY_SHA256` repository **variable** to the hash of the verified ZIP to enforce an exact build input.
- GeoIP/GeoSite: jsDelivr mirror of Loyalsoldier's `release` branch. These are **mutable** upstream rules. Pin/checksum them before claiming byte-for-byte reproducible releases.

CI does not require heavy core binaries committed to Git. It downloads them for Shadow and stages `dist/shadow/...`, which `scripts/build_releases.sh` consumes. The packaging verifier checks ELF headers, ABI and the APK layout. It does **not** test VPN connections on real Android hardware.

## Release signing

Configure these repository Actions secrets before tag or dispatch release runs:

- `ANDROID_KEYSTORE_BASE64`: `base64 -w0 android/upload-keystore.jks`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

**Never commit private keys, key.properties or secrets.** Preserve the signing key for upgrades. Existing debug-signed installs cannot be upgraded in place with a new signing key.

## Publishing

Make sure the `nextlink` repository has a first commit and workflow on `main`. Test the CI run. Version in `pubspec.yaml` must match the tag.

```sh
git tag 'v1.0.0-beta+4'
git push origin 'v1.0.0-beta+4'
```

GitHub Actions creates `NextLink-arm64-v8a.apk` (Original) and `NextLink-arm64-v8a-s.apk` (Shadow), plus individual `.sha256` files. If you pushed the tag before fixing the workflow, delete the failed tag and recreate it only after verifying it isn't referenced by published releases, or run a manual workflow from the tag.

Before public release, install each APK on an ARM64 Android device and check installation, Xray/sing-box/AWG startup, LAN routing, VPN stop, and update from existing signed version.
