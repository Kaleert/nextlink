# Amnezia Box core

Upstream: https://github.com/amnezia-vpn/amnezia-box
Source release: v1.260910.0
Commit: 16724484cfa00d9b2c14d8280dc055564e2e12ba
License: GPL-3.0-or-later (see LICENSE).

Unmodified upstream CLI, built with `with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_awg`.
Go: 1.27.3; Android NDK: 28.2.13676358. Full corresponding source is available at the pinned upstream commit. Reproduction script: `scripts/build_amnezia_core.sh`.

The binaries in Android jniLibs are executable PIE programs launched directly from the installed native-library directory, not JNI libraries. Downloaded core binaries in the app data directory still use the Android linker. They are used only for AmneziaWG profiles; the downloaded Xray and standard Sing-box cores remain separate.
