#!/usr/bin/env bash
user=user
remote=address
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$project_dir/dist/wg/manifest.json" ] || { echo 'Сначала выполните scripts/build_amnezia_core.sh'; exit 1; }
ssh $user@$remote 'mkdir -p ~/download/wg'
# Publish binaries before the manifest so readers never see checksums for missing files.
rsync -av --progress --exclude=manifest.json "$project_dir/dist/wg/" "$user@$remote:download/wg/"
rsync -av "$project_dir/dist/wg/manifest.json" "$user@$remote:download/wg/manifest.json"
echo "WG опубликован: https://$remote/download/wg/manifest.json"
