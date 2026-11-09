#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$project_dir/tun2socks"}
patch_file="$project_dir/patches/tun2socks-nextlink.patch"
expected_commit=bd06dbfa1d0c376fb0a38dd534edbe87cfcc56bb

if [ ! -f "$source_dir/.git" ] && [ ! -d "$source_dir/.git" ]; then
  if [ "$source_dir" != "$project_dir/tun2socks" ]; then
    echo 'The supplied tun2socks checkout is not initialized.' >&2
    exit 1
  fi
  git -C "$project_dir" submodule update --init -- tun2socks
fi

if [ "$(git -C "$source_dir" rev-parse HEAD)" != "$expected_commit" ]; then
  echo 'Unexpected tun2socks revision. Update the submodule pin and NextLink patch together.' >&2
  exit 1
fi

if git -C "$source_dir" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
  echo 'NextLink TUN patch is already applied.'
elif git -C "$source_dir" apply --check "$patch_file"; then
  git -C "$source_dir" apply "$patch_file"
  echo 'Applied the NextLink TUN patch.'
else
  echo 'NextLink TUN patch conflicts with local changes; no files were reset.' >&2
  exit 1
fi
