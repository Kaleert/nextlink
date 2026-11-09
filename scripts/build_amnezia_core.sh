#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${NEXTLINK_AWG_SOURCE_DIR:-/tmp/nextlink-amnezia-box-source}
ndk_dir=${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/28.2.13676358}
if [ ! -d "$source_dir/.git" ]; then
  git clone --branch v1.260910.0 --depth 1 https://github.com/amnezia-vpn/amnezia-box.git "$source_dir"
fi
[ "$(git -C "$source_dir" rev-parse HEAD)" = 16724484cfa00d9b2c14d8280dc055564e2e12ba ]
# Android's linker retains its own argv[0] when executing a downloaded PIE.
python3 - "$source_dir/cmd/sing-box/main.go" <<'PATCHPY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);s=p.read_text()
if 'os.Args = os.Args[1:]' not in s:
 s=s.replace('import "github.com/sagernet/sing-box/log"', 'import ("github.com/sagernet/sing-box/log"; "os"; "path/filepath")')
 s=s.replace('func main() {', 'func main() {\n if len(os.Args) > 1 && (filepath.Base(os.Args[0]) == "linker" || filepath.Base(os.Args[0]) == "linker64") { os.Args = os.Args[1:] }')
 p.write_text(s)
PATCHPY
cd "$source_dir"
build_core() {
  local go_arch=$1 abi=$2 compiler=$3
  mkdir -p "$project_dir/dist/wg/$abi"
  CGO_ENABLED=1 CC="$ndk_dir/toolchains/llvm/prebuilt/linux-x86_64/bin/$compiler" GOOS=android GOARCH="$go_arch" GOARM=7 \
    go build -buildmode=pie -trimpath -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_awg \
    -ldflags '-s -w -X github.com/sagernet/sing-box/constant.Version=1.260910.0-nextlink' \
    -o "$project_dir/dist/wg/$abi/libawg.so" ./cmd/sing-box
}
build_core arm64 arm64-v8a aarch64-linux-android21-clang
build_core arm armeabi-v7a armv7a-linux-androideabi21-clang
build_core amd64 x86_64 x86_64-linux-android21-clang

python3 "$project_dir/scripts/prepare_wg_download.py"
