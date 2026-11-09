#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -n 1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\+[0-9]+$ ]] || { echo "Invalid pubspec version: $VERSION" >&2; exit 2; }
BUILD_NAME="${VERSION%+*}"
BUILD_NUMBER="${VERSION##*+}"
OUT="releases/$VERSION"
mkdir -p "$OUT"

android_arch() {
    case "$1" in
       arm64-v8a) printf android-arm64;;
       armeabi-v7a) printf android-arm;;
       x86_64) printf android-x64;;
       *) echo "Unsupported Android ABI: $1" >&2; exit 2;;
    esac
}

android_build() {
    local abi="$1" target flavor apk
    target="$(android_arch "$abi")"
    [[ "$2" == original || "$2" == shadow ]] || { echo "Unsupported flavor: $2" >&2; exit 2; }
    # The shadow payload is local, not fetched during release builds.
    if [[ "$2" == shadow ]]; then
        local source="dist/shadow/android/$abi" assets="android/app/src/shadow/assets/preload"
        local native="android/app/src/shadow/jniLibs"
        for f in libxray.so libsingbox.so libawg.so; do
            test -s "$source/$f" || { echo "Missing $source/$f" >&2; exit 1; }
        done
        for f in geoip.dat geosite.dat; do
            test -s "dist/shadow/$f" || { echo "Missing dist/shadow/$f" >&2; exit 1; }
        done
        # Remove previously staged ABIs: otherwise the APK is not truly arch-specific.
        rm -rf "$assets"
        mkdir -p "$assets"
        cp dist/shadow/{geoip,geosite}.dat "$assets/"
        # Native executable ELF files live in the APK native library location,
        # not in assets/preload (which would duplicate them after installation).
        rm -rf "$native"
        mkdir -p "$native/$abi"
        cp "$source/"{libxray.so,libsingbox.so,libawg.so} "$native/$abi/"
    fi
    flavor="$2"
    # Remove stale APKs so we never accidentally package a previous build.
    rm -f build/app/outputs/flutter-apk/app-*.apk

    flutter build apk --release --split-per-abi \
        --flavor "$flavor" --target-platform "$target" \
        --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"

    # Flutter names split APKs differently depending on flavor/version.
    # Select by filename first; verify actual packaged ABI below.
    apk="$(find build/app/outputs/flutter-apk -maxdepth 1 \
        -type f -name "app-$abi-$flavor-release.apk" -print -quit)"

    test -n "$apk" && test -s "$apk" || {
        echo "ABI-specific APK not found. Generated files:" >&2
        ls -lh build/app/outputs/flutter-apk/*.apk >&2
        exit 1
    }
    local suffix=""
    [[ "$flavor" == shadow ]] && suffix="-s"
    python3 scripts/verify_android_apk.py "$apk" --abi "$abi" --flavor "$flavor"
    cp "$apk" "$OUT/NextLink-$abi$suffix.apk"
    (cd "$OUT" && sha256sum "NextLink-$abi$suffix.apk" > "NextLink-$abi$suffix.apk.sha256")
    echo "Built: $OUT/NextLink-$abi$suffix.apk"
}

linux_build() {
    local arch suffix bundle staging
    arch="$(uname -m)"
    [[ "$arch" == x86_64 || "$arch" == aarch64 ]] || {
        echo "Unsupported Linux host architecture: $arch" >&2; exit 2;
    }
    flutter build linux --release
    # Flutter may use x64 or x86_64 in its build path.
    bundle="$(find build/linux -type f -path "*/release/bundle/nextlink" -print -quit | xargs -r dirname)"
    test -n "$bundle" && test -x "$bundle/nextlink" || { echo "Flutter Linux bundle not found" >&2; exit 1; }
    staging="$(mktemp -d)"
    trap 'rm -rf "$staging"' RETURN
    mkdir -p "$staging/NextLink"
    cp -a "$bundle/." "$staging/NextLink/"
    if [[ "$1" == shadow ]]; then
        local src="dist/shadow/linux/$arch"
        for f in xray sing-box amnezia-box geoip.dat geosite.dat; do
            test -s "$src/$f" || { echo "Missing $src/$f" >&2; exit 1; }
        done
        mkdir -p "$staging/NextLink/data/preload"
        cp "$src/"{xray,sing-box,amnezia-box,geoip.dat,geosite.dat} \
            "$staging/NextLink/data/preload/"
        suffix="-s"
    else
        suffix=""
    fi
    tar -C "$staging" -czf "$OUT/NextLink-$arch$suffix.tar.gz" NextLink
    echo "Built: $OUT/NextLink-$arch$suffix.tar.gz"
}

case "${1:-}" in
    android) android_build "${2:?Android ABI required}" "${3:?original or shadow required}";;
    linux) linux_build "${2:?original or shadow required}";;
    *) echo "Usage: $0 android arm64-v8a|armeabi-v7a|x86_64 original|shadow" >&2
       echo "       $0 linux original|shadow" >&2; exit 2;;
esac
