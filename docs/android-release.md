# Android-релизы: Original и Shadow

> Руководство для сопровождающих. Текущий автоматизированный релиз: **Android ARM64**. Linux не участвует.

Сборка Linux не входит в текущий CI и не блокирует выпуск Android.

## Версия и имена файлов

`pubspec.yaml` is the source of truth: `version: 1.0.0-beta+4` becomes Git tag `v1.0.0-beta+4`, `versionName=1.0.0-beta` and `versionCode=4`. Release script creates:

- `releases/1.0.0-beta+4/NextLink-arm64-v8a.apk` (Original)
- `releases/1.0.0-beta+4/NextLink-arm64-v8a-s.apk` (Shadow)

Other architectures are deliberately disabled in CI until their binaries are available and tested.

## Подпись: создать ключ один раз

Run locally, **never in CI**, and store the keystore/passwords in a password manager and an offline backup:

```bash
keytool -genkeypair -v -keystore android/upload-keystore.jks -alias nextlink \
  -keyalg RSA -keysize 3072 -validity 10000
cp android/key.properties.example android/key.properties
# Edit android/key.properties: actual storePassword and keyPassword
```

Don't lose this key. To update installed APKs later, sign them with the **same** keystore and alias. Do not upload `*.jks` or `key.properties` into your repository. Original/Shadow use the same package ID and signing key.

For GitHub Actions set repository **Settings → Secrets and variables → Actions**:

| Secret | Meaning |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Output of `base64 -w0 android/upload-keystore.jks` (Linux) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `nextlink` or chosen alias |
| `ANDROID_KEY_PASSWORD` | Alias password |

The pipeline creates `android/key.properties` only on the ephemeral runner. If secrets are missing, release build fails; it does not fall back to debug signing.

## Ресурсы Shadow (не хранятся в Git)

Shadow needs these local files before packaging:

```text
dist/shadow/geoip.dat
dist/shadow/geosite.dat
dist/shadow/android/arm64-v8a/libxray.so
dist/shadow/android/arm64-v8a/libsingbox.so
dist/shadow/android/arm64-v8a/libawg.so
```

Prepare the files from your verified local binaries. They must be Android ARM64 ELF executables; do not use desktop Linux executables. Create a one-time seed archive:

```bash
tar -czf NextLink-shadow-arm64-v8a.tar.gz \
  dist/shadow/geoip.dat dist/shadow/geosite.dat \
  dist/shadow/android/arm64-v8a/libxray.so \
  dist/shadow/android/arm64-v8a/libsingbox.so \
  dist/shadow/android/arm64-v8a/libawg.so
```

Upload to an **existing draft or published GitHub Release** with tag `nextlink-shadow-seeds` and asset name `NextLink-shadow-arm64-v8a.tar.gz` using the GitHub UI or `gh` CLI. Example, when creating the seeds release for the first time:

```bash
gh release create nextlink-shadow-seeds NextLink-shadow-arm64-v8a.tar.gz \
  --title 'NextLink build inputs (ARM64)' --notes 'Versioned Shadow build inputs, not an app release.' --latest=false
```

That archive can be large. If repository or binaries aren't redistributable, **do not publish the seed release publicly**: use a private repository or protected artifact storage. A private seed release can be downloaded by Actions with the repository token.

When replacing the seed archive, verify binary provenance and checksums separately. The pipeline checks ELF headers/ZIP layout, not software supply-chain authenticity.

## CI и публикация

- `main` / pull request: static analysis, offline Dart tests, Python packaging tests, debug Original APK.
- `workflow_dispatch`: builds signed Original; enable **build_shadow** to also build Shadow from `nextlink-shadow-seeds`.
- Push tag `v1.0.0-beta+4`: build both signed variants, verify contents, publish GitHub prerelease with APKs and SHA-256 sums.

Run locally:

```bash
bash scripts/build_releases.sh android arm64-v8a original
bash scripts/build_releases.sh android arm64-v8a shadow
```

The release script verifies the APK's ABI and resource isolation. **It does not prove that Android can execute native cores**. On clean installation, test Xray/sing-box/AWG, LAN bypass, tunnel stop/start and no-network preload.

## Обновление существующих установок

Existing debug-signed installs cannot be updated in place by a newly release-signed APK, even if applicationId and versionCode match. Backup subscriptions/settings, uninstall the old app, then install the release-signed version once. Future Original and Shadow builds signed with the same release key can update each other when versionCode permits.
