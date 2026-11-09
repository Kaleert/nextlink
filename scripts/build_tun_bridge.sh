#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}
bash "$project_dir/scripts/prepare_tun_bridge.sh"
cd "$project_dir/t2swrapper"
gomobile bind -target=android/arm,android/arm64,android/amd64 -androidapi=21 -o t2swrapper.aar .
cp t2swrapper.aar "$project_dir/android/app/libs/t2swrapper.aar"
